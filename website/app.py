from pathlib import Path
import cv2
import pandas as pd
from quart import Quart, render_template, request, jsonify, send_from_directory
from quart_cors import cors

from backend.scripts.classes import ClassManager
from backend.scripts.crop_images import CropProcessor
from backend.scripts.database_manager import DatabaseManager
from backend.scripts.image_embedding import EmbeddingCreator, \
    cluster_embeddings, suggest_classes_from_clusters, get_cluster_plot_data

# Configuration
ROOT = Path(__file__).parent
OUTPUT_ROOT = ROOT / "backend/crops"
DB_PATH = ROOT / "image_embeddings.sqlite"
DATASET_PATH = r"C:\Users\2dani\Documents\Fh\Bachelorarbeit\ProductImages\SKU110K_fixed"


app = Quart(__name__,)
app.config.from_object(__name__)

cors(app, allow_origin="*")

# load the configuration
app.config.from_object(__name__)

@app.before_serving
async def startup():
    """Initialize resources before serving requests."""
    await db.connect()
    print("Database connected successfully")


@app.after_serving
async def shutdown():
    """Cleanup resources after serving."""
    await db.close()
    print("Database connection closed")


async def get_crop_splits(page, page_size, split):
    """Helper function to get crops by split with pagination."""
    # TODO: Return the filtered data count from the database directly
    try:
        if split == 'all':
            filtered_data = await db.get_all_crops_with_embeddings(page, page_size)
            total_count = (await db.get_embeddings_status())['total_embeddings']
        elif split in ['train', 'val', 'test', 'uploaded']:
            filtered_data = await db.get_crops_with_embeddings_by_split(split, page, page_size)
            total_count = await db.count_embedded_crops_by_split(split)
        elif split == 'assigned':
            filtered_data = await db.get_crops_with_embeddings_class(page, page_size)
            total_count = await db.count_embedded_assigned_crops()
        elif split == 'unassigned':
            filtered_data = await db.get_crops_with_embeddings_without_class(page, page_size)
            total_count = await db.count_embedded_unassigned_crops()
        else:
            filtered_data = []
            total_count = 0
    except Exception as e:
        print(f"Error fetching crops: {e}")
        filtered_data = []
        total_count = 0

    return filtered_data, total_count

@app.route('/')
async def index():
    return await render_template('index.html')


@app.route('/api/crops')
async def get_crops():
    """Returns list of crops filtered by split or assignment status."""
    page = int(request.args.get('page', 0))
    page_size = int(request.args.get('page_size', 120))
    split = request.args.get('split', 'all')

    filtered_data, total_count = await get_crop_splits(page, page_size, split)

    return jsonify({
        'crops': filtered_data,
        'total': total_count,
        'page': page,
        'page_size': page_size
    })


@app.route('/api/crops/<path:filename>', methods=['GET', 'DELETE'])
async def manage_crop(filename):
    """
    Delete or  get a crop image.
    :param filename: Name of the crop image file
    :return: JSON response indicating success or failure
    """
    if request.method == 'DELETE':
        # Delete crop from filesystem and database
        crop_path = OUTPUT_ROOT / filename
        if crop_path.exists():
            crop_path.unlink()

        # TODO: Delete empty parent directories batch and picture group if needed
        # TODO: Delete origin image if no more crops exist for it
        # (Maybe dont create origin images for uploaded crops)
        await db.delete_crop(filename)
        return jsonify({'success': True})

    elif request.method == 'GET':
       return await send_from_directory(OUTPUT_ROOT, filename)

    return jsonify({'success': False, 'error': 'Method not allowed'}), 405


@app.route('/api/crops/upload', methods=[ 'POST'])
async def manage_upload_crop():
    """
    Get all uploaded crops or upload a new crop image.
    :returns: JSON response with upload status or list of uploaded crops
    """
    image = (await request.files).get('image', None)
    if not image:
        return jsonify({'success': False, 'error': 'No image provided'}), 400

    try:
        filename = image.filename

        # Save image temporarily
        temp_dir = OUTPUT_ROOT / "temp"
        temp_dir.mkdir(parents=True, exist_ok=True)
        temp_image_path = temp_dir / filename
        await image.save(str(temp_image_path))

        # Read image to get dimensions
        img = cv2.imread(str(temp_image_path))
        if img is None:
            temp_image_path.unlink()
            return jsonify({'success': False, 'error': 'Invalid image file'}), 400

        h, w = img.shape[:2]

        # Create DataFrame with single bounding box covering entire image

        annotations = pd.DataFrame([{
            'image_name': filename,
            'x1': 0,
            'y1': 0,
            'x2': w,
            'y2': h,
            'image_width': w,
            'image_height': h
        }])

        # Use create_crops_from_image
        success = await crop_manager.create_crops_from_image(
            batch_idx=0,
            img_name=filename,
            annotations=annotations,
            img_dir=temp_dir,
            split_name="uploaded",
            create_embedding=True
        )

        # Clean up temporary file
        if temp_image_path.exists():
            temp_image_path.unlink()

        if success:
            return jsonify({'success': True, 'filename': filename})
        else:
            return jsonify({'success': False, 'error': 'Failed to create crop'}), 500

    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/api/crops/<path:crop_path>/infer')
async def infer_class_for_crop(crop_path):
    """
    Infers class for uploaded crops based on embeddings.
    :param crop_path: Path to the crop image
    :return: JSON response with inferred classes
    """
    limit_per_class = int(request.args.get('top_k', 2))
    threshold = float(request.args.get('threshold', 0.8))
    class_name = request.args.get('class_name', None)
    return jsonify(await class_manager.classify_crop(crop_path, limit_per_class, threshold, class_name))


@app.route('/api/crops/<path:crop_path>/similar')
async def similar_crops_for_crop(crop_path):
    """Return similar crops for a given crop path."""
    top_k = int(request.args.get('top_k', 5))
    class_name = request.args.get('class_name', None)
    similar = await class_manager.get_similar_crops(crop_path, top_k=top_k, class_name=class_name)
    return jsonify({'similar_crops': similar})


@app.route('/api/clusters')
async def get_clusters():
    """Cluster embeddings and suggests classes."""
    min_cluster_size = int(request.args.get('n_clusters', 3))
    min_samples = int(request.args.get('min_samples', 3))
    cluster_page = int(request.args.get('cluster_page', 0))
    cluster_page_size = int(request.args.get('cluster_page_size', 1000))
    split = request.args.get('split', 'all')

    embeddings_data, total_crops = await get_crop_splits(cluster_page, cluster_page_size, split)

    if len(embeddings_data) < min_cluster_size:
        return jsonify({
            'clusters': [],
            'n_clusters': 0,
            'n_noise': len(embeddings_data),
            'total': total_crops,
            'plot_data': [],
            'message': f'Not enough data for clustering (need at least {min_cluster_size})'
        })

    clusters, clusterer = cluster_embeddings(
        embeddings_data,
        min_cluster_size,
        min_samples)

    cluster_list = suggest_classes_from_clusters(clusters, min_cluster_size)
    plot_data = get_cluster_plot_data(embeddings_data, clusterer)

    return jsonify({
        'clusters': cluster_list,
        'n_clusters': len([k for k in clusters.keys() if k != -1]),
        'n_noise': len(clusters.get(-1, [])),
        'plot_data': plot_data,
        'total': total_crops
    })


@app.route('/api/classes', methods=['GET', 'POST'])
async def manage_classes():
    """Create classes and returns a list of classes"""
    if request.method == 'POST':
        class_name = (await request.json).get('class_name')

        if await db.create_class(class_name):
            return jsonify({'success': True})
        return jsonify({'success': False, 'error': 'Class already exists'})

    elif request.method == 'GET':
        return jsonify({'classes': await db.get_all_classes()})

    return jsonify({'success': False, 'error': 'Method not allowed'}), 405

@app.route('/api/classes/<class_name>', methods=['GET', 'DELETE'])
async def manage_class(class_name):
    """Manage a specific class: Get crops, Create or Delete."""
    if request.method == 'GET':
        crops = await db.get_class_crops(class_name)
        return jsonify({'class_name': class_name, 'crops': crops})

    elif request.method == 'DELETE':
        if await db.delete_class(class_name):
            return jsonify({'success': True})
        return jsonify({'success': False, 'error': 'Class does not exist'})

    return jsonify({'success': False, 'error': 'Method not allowed'}), 405

@app.route('/api/classes/<class_name>/rename', methods=['PATCH'])
async def rename_class(class_name):
    """Rename an existing class."""
    new_class_name = (await request.json).get('new_class_name')
    if await db.rename_class(class_name, new_class_name):
        return jsonify({'success': True})
    return jsonify({'success': False, 'error': 'Rename failed'})

@app.route('/api/classes/assign')
async def get_assigned_status():
    """Get assigned status of crops."""
    return jsonify(await db.get_assigned_status())


@app.route('/api/classes/<class_name>/assign', methods=['POST'])
async def assign_crop_to_class(class_name):
    """Assigns a crop to a class."""
    crop_path = (await request.json).get('crop_path')
    full_path = OUTPUT_ROOT / crop_path

    if await class_manager.assign_crop_to_class(full_path, class_name, OUTPUT_ROOT):
        return jsonify({'success': True})
    return jsonify({'success': False})


@app.route('/api/embeddings/create-next', methods=['POST'])
async def create_next_embeddings():
    """Create embeddings for the next unprocessed origin image."""
    processed_origins = (await request.json).get('processed_origins', 1)

    # TODO: Return status of embedding creation(how many processed, how many left)
    result = await embedding_creator.embed_crops(
        OUTPUT_ROOT,
        256,
        processed_origins
    )

    return jsonify(result)


@app.route('/api/embeddings/status')
async def get_embeddings_status():
    """Get status of embeddings creation."""
    return jsonify(await db.get_embeddings_status())


@app.route('/api/dataset/create_objdet', methods=['POST'])
async def create_objdet_dataset():
    """Create a dataset from images with bboxes and classes"""
    data = await request.json
    output_path = data.get('output_path', ROOT / "backend/dataset_obj_det")
    original_splits = data.get('original_splits', True)

    await crop_manager.export_object_det_dataset(output_path, original_splits)
    return jsonify({'success': True})

@app.route('/api/dataset/create_img_class', methods=['POST'])
async def create_img_class_dataset():
    """Create a dataset from images with assigned classes"""
    data = await request.json
    output_path = data.get('output_path', ROOT / "backend/dataset_img_class")
    original_splits = data.get('original_splits', True)

    await crop_manager.export_crop_dataset(output_path, original_splits)
    return jsonify({'success': True})


@app.route('/api/database/export/class_embeddings', methods=['POST'])
async def export_class_embeddings():
    """Create a new database with only crops that have embeddings and classes assigned"""
    try:
        result = await db.export_db()
        return jsonify(result)
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


if __name__ == '__main__':
    # Initialize database and managers
    db = DatabaseManager(DB_PATH)
    class_manager = ClassManager(db)
    crop_manager = CropProcessor(OUTPUT_ROOT, DATASET_PATH, db)
    embedding_creator = EmbeddingCreator(db)

    app.run(debug=True, port=5000)
