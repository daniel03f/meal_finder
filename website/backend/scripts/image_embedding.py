from PIL import Image
from torchvision import transforms
from tqdm import tqdm
from sklearn.preprocessing import normalize
from sklearn.decomposition import PCA
import numpy as np
import hdbscan
import umap
import tensorflow as tf
from pathlib import Path



def cluster_embeddings(embeddings_data, min_cluster_size=5, min_samples=3):
    """
    ClustersDialog embeddings using HDBScan
    :param embeddings_data: List with embedding data
    :param min_cluster_size: Minimum size for a cluster
    :param min_samples: Conservativeness of clustering (higher = stricter)
    :returns: Dict of clusters with cluster_id as key and list of items
    """
    if not embeddings_data:
        return {}, None

    embeddings = np.array([item['embedding'] for item in embeddings_data])

    embeddings_normalized = normalize(embeddings, norm='l2')

    # Reduce dimensionality because HDBScan can be slow/inaccurate with high-dimensional data
    if len(embeddings) > 50:
        embeddings_reduced = PCA(n_components=50).fit_transform(embeddings_normalized)
    else:
        embeddings_reduced = embeddings_normalized

    clusterer = hdbscan.HDBSCAN(
        min_cluster_size=min_cluster_size,
        min_samples=min_samples,
        cluster_selection_method='eom',
        cluster_selection_epsilon_max=0.7,
        core_dist_n_jobs=-1
    )

    labels = clusterer.fit_predict(embeddings_reduced)
    outlier_scores = clusterer.outlier_scores_

    clusters = {}
    noise_items = []
    for idx, (item, label, outlier_score) in enumerate(zip(embeddings_data, labels, outlier_scores)):
        label = int(label)
        if label == -1:
            noise_items.append({
                'crop_file': item['crop_file'],
                'crop_path': item['crop_path'],
                'assigned_class': item.get('assigned_class'),
                'outlier_score': float(outlier_score)
            })
            continue
        if label not in clusters:
            clusters[label] = []
        clusters[label].append({
            'crop_file': item['crop_file'],
            'crop_path': item['crop_path'],
            'assigned_class': item['assigned_class'],
            'cluster_probability': float(clusterer.probabilities_[idx])
        })
    if noise_items:
        clusters[-1] = noise_items

    return clusters, clusterer


def suggest_classes_from_clusters(clusters, min_cluster_size=5):
    """
    Suggests classes based on clusters.
    :param clusters: Dict of clusters from cluster_embeddings
    :param min_cluster_size: Minimum size of cluster to be suggested as class
    :returns: List of suggested classes with cluster_id, size and sample crops
    """
    suggestions = []
    for cluster_id, items in clusters.items():
        if len(items) >= min_cluster_size:
            suggestions.append({
                'cluster_id': cluster_id,
                'size': len(items),
                'samples': items
            })

    suggestions.sort(key=lambda x: x['cluster_id'])
    return suggestions


def reduce_embeddings_to_2d(embeddings_data):
    """
    Reduces embeddings to 2D using UMAP for visualization.
    :param embeddings_data: List with embedding data
    :returns: 2D numpy array of reduced embeddings
    """
    embeddings = np.array([item['embedding'] for item in embeddings_data])
    embeddings_normalized = normalize(embeddings, norm='l2')

    reducer = umap.UMAP(
        n_components=2,
        n_neighbors=10,
        min_dist=0.0,
        metric='cosine',
        random_state=42
    )

    embeddings_2d = reducer.fit_transform(embeddings_normalized)
    return embeddings_2d


def get_cluster_plot_data(embeddings_data, clusterer):
    """
    Prepares data for cluster visualization plot.
    :param embeddings_data: List with embedding data
    :param clusterer: Fitted HDBSCAN clusterer
    :returns: Dict with plot data
    """
    embeddings_2d = reduce_embeddings_to_2d(embeddings_data)

    labels = clusterer.labels_

    plot_data = []
    for idx, (item, label) in enumerate(zip(embeddings_data, labels)):
        plot_data.append({
            'x': float(embeddings_2d[idx, 0]),
            'y': float(embeddings_2d[idx, 1]),
            'cluster_id': int(label),
            'crop_path': item['crop_path'],
            'assigned_class': item.get('assigned_class'),
            'outlier_score': float(clusterer.outlier_scores_[idx]) if label == -1 else None
        })

    return plot_data


class EmbeddingCreator:
    def __init__(self, db_manager):
        """
        Initializes the EmbeddingClusterer.
        :param db_manager: DatabaseManager instance
        """
        self.db = db_manager

        # Preprocessing for DINOv2/v3 ViT-S16: resize to 98x98, ImageNet normalization
        self.preprocess = transforms.Compose([
            transforms.Resize((98, 98)),
            transforms.ToTensor(),
            transforms.Normalize(
                mean=[0.485, 0.456, 0.406],
                std=[0.229, 0.224, 0.225]
            ),
        ])

        # Self converted model
        model_path = Path(__file__).parent.parent / "dinov3_vits16_pretrain_lvd1689m-08c60483_float32.tflite"
        self.interpreter = tf.lite.Interpreter(model_path=str(model_path))
        self.interpreter.allocate_tensors()
        self.input_details = self.interpreter.get_input_details()
        self.output_details = self.interpreter.get_output_details()

    def embed_image(self, img_path):
        """
        Create embedding for a single image using DINOv2/v3 ViT-S16.
        :param img_path: Path to image
        :return: Numpy array with embedding with float values that is the normalized embedding of the image
        """
        img = Image.open(img_path).convert("RGB")

        # Resize image to 98x98, normalize with ImageNet stats, convert to numpy array
        # Add batch dimension: (1, C, H, W)
        tensor = self.preprocess(img).unsqueeze(0).numpy()

        # Transpose pytorch tensor to match tflite input tensor
        tensor = np.transpose(tensor, (0, 2, 3, 1))

        # Run inference with TFLite model
        self.interpreter.set_tensor(self.input_details[0]['index'], tensor)
        self.interpreter.invoke()

        # Get the output embedding and normalize it
        embedding = self.interpreter.get_tensor(self.output_details[0]['index'])[0]

        # Normalize the embedding to unit length(Euclidian norm)
        return embedding / np.linalg.norm(embedding)

    async def embed_crops(self, crop_root, batch_size=256, processed_origins=1):
        """
        Create embeddings for crops.
        :param crop_root: root directory for crop images
        :param batch_size: GPU batch size
        :param processed_origins: Amount of origins to process (1 for single origin mode), large number for all
        :return: dict with status information
        """
        unprocessed_origins = await self.db.get_unprocessed_origins()

        if not unprocessed_origins:
            status = await self.db.get_embeddings_status()
            return {
                'status': 'complete',
                'message': 'All origin images already processed',
                'crops_processed': 0,
                **status
            }

        # Determine which origins to process
        process_all = processed_origins >= len(unprocessed_origins)

        if process_all:
            origins_to_process = unprocessed_origins
            desc_prefix = f"Processing all {len(origins_to_process)} origin images"
        else:
            origins_to_process = unprocessed_origins[:processed_origins]
            desc_prefix = f"Processing {len(origins_to_process)} origin image(s)"

        total_processed = 0
        origin_iter = tqdm(origins_to_process, desc=desc_prefix) if len(origins_to_process) > 1 else origins_to_process

        for origin in origin_iter:
            crops = await self.db.get_crops_by_origin(origin)

            batch_iter = range(0, len(crops), batch_size)
            if len(origins_to_process) > 1:
                batch_iter = tqdm(batch_iter, desc=f"  {origin}", leave=False)

            for i in batch_iter:
                batch = crops[i:i + batch_size]

                for crop_row in batch:
                    try:
                        crop_path = crop_root / crop_row['crop_path']
                        embedding = self.embed_image(str(crop_path))
                        await self.db.update_embedding(crop_row['crop_path'], embedding)
                        total_processed += 1
                    except Exception as e:
                        print(f"Failed to embed {crop_row['crop_path']}: {e}")

        # Rebuild the quantized vector index so the new embeddings are searchable
        await self.db.refresh_vector_index()

        status = await self.db.get_embeddings_status()

        result = {
            'status': 'success',
            'crops_processed': total_processed,
            **status
        }

        # Add origin_image for single origin mode
        if len(origins_to_process) == 1:
            result['origin_image'] = origins_to_process[0]

        return result
