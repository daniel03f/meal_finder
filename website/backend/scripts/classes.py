from pathlib import Path
from backend.scripts.image_embedding import EmbeddingCreator


class ClassManager:
    """
    Manages classes and their assigned crops.
    """
    def __init__(self, db_manager):
        """
        Initializes the ClassManager.
        :param db_manager: DatabaseManager instance
        """
        self.db = db_manager
        self.embedder = EmbeddingCreator(db_manager)


    async def assign_crop_to_class(self, crop_path, class_name, crops_root):
        """
        Assign a crop to a class.
        :param crop_path: Path to the crop image
        :param class_name: Name of the class
        :param crops_root: Root directory for crops
        :returns: True if assigned successfully, False otherwise
        """
        crop_path = Path(crop_path)
        crops_root = Path(crops_root)

        try:
            relative_path = crop_path.relative_to(crops_root)
            path_to_store = str(relative_path).replace('\\', '/')
        except ValueError:
            # If crop_path is not under crops_root, use absolute path
            path_to_store = str(crop_path).replace('\\', '/')

        # Create class if it doesn't exist
        await self.db.create_class(class_name)

        return await self.db.assign_crop_to_class(path_to_store, class_name)


    async def classify_crop(self, crop_image_path, limit_per_class=2, threshold=0.8, class_names=None):
        """
        Classifies a single crop image based on embedding similarity and class voting.
        Uses SQLite Vector quantized scanning for efficient similarity search.

        :param crop_image_path: Path to the crop image to classify
        :param limit_per_class: : Number of similar crops to consider for voting
        :param threshold: Confidence threshold for assigning a class
        :param class_names: Optional class list to limit search to specific classes
        :returns: dict with predicted_class, confidence, similar_crops
        """
        # Create or fetch embedding
        crop = await self.db.get_crop(crop_image_path)
        if crop and crop.get('embedding'):
            crop_embedding = crop['embedding']
        else:
            path = Path(__file__).parent.parent / "crops" / crop_image_path
            crop_embedding = self.embedder.embed_image(path)

        target_classes = class_names if class_names else None

        best_class, confidence = await self.db.find_best_class(
            crop_embedding,
            exclude_path=crop_image_path,
            class_names=target_classes,
            limit_per_class=limit_per_class,
        )

        if best_class is None or confidence < threshold:
            best_class = None

        return {
            'predicted_class': best_class,
            'confidence': float(confidence),
        }

    async def get_similar_crops(self, crop_image_path, top_k=5, class_name=None):
        """
        Return similar crops for a given crop.
        """
        crop = await self.db.get_crop(crop_image_path)
        if crop and crop.get('embedding'):
            crop_embedding = crop['embedding']
        else:
            path = Path(__file__).parent.parent / "crops" / crop_image_path
            crop_embedding = self.embedder.embed_image(path)

        similar = await self.db.find_similar_crops(
            crop_embedding, top_k=top_k, class_name=class_name, exclude_path=crop_image_path
        )
        return similar
