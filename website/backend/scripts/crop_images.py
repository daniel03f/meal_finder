from pathlib import Path
import cv2
import pandas as pd
from tqdm import tqdm
from backend.scripts.image_embedding import EmbeddingCreator
import shutil
import random


class CropProcessor:
    """Handles cropping of images based on bounding box annotations."""

    def __init__(self, output_root, dataset_root, db_manager):
        """
        Initialize CropProcessor.
        :param output_root: Path to save cropped images
        :param dataset_root: Path to dataset root containing images and annotations
        :param db_manager: DatabaseManager instance for saving crop info
        """
        self.output_root = Path(output_root)
        self.dataset_root = Path(dataset_root)
        self.db = db_manager
        self.embedder = EmbeddingCreator(db_manager)


    async def create_crop(self, crop_idx, row, img, base_name, new_img_path, img_name, create_embedding=False):
        """
        Create a single crop from bounding box coordinates.
        :param crop_idx: Index of the crop for naming
        :param row: DataFrame row with bounding box coordinates
        :param img: Original image as a numpy array
        :param base_name: Base name for the crop image file
        :param new_img_path: Directory to save the crop
        :param img_name: Name of the original image file
        :param create_embedding: Whether to create embedding for the crop
        :return: True if crop was created, False otherwise
        """
        x1, y1, x2, y2, w, h = int(row['x1']), int(row['y1']), int(row['x2']), int(row['y2']), int(row['image_width']), int(row['image_height'])

        # Clip to image boundaries
        x1, y1 = max(0, x1), max(0, y1)
        x2, y2 = min(w, x2), min(h, y2)

        if x2 <= x1 or y2 <= y1:
            return False

        crop = img[y1:y2, x1:x2]
        crop_name = f"{base_name}_{crop_idx}.jpg"
        crop_path = new_img_path / crop_name

        cv2.imwrite(str(crop_path), crop)

        relative_crop_path = str(crop_path.relative_to(self.output_root)).replace('\\', '/')
        embedding = self.embedder.embed_image(crop_path) if create_embedding else None

        await self.db.insert_crop(
            crop_name,
            relative_crop_path,
            img_name,
            [x1, y1, x2, y2],
            w,
            h,
            embedding
        )

        return True

    async def create_crops_from_image(self, batch_idx, img_name, annotations, img_dir, split_name, create_embedding=False):
        """
        Create all crops for a single image.
        :param batch_idx: Index of the current batch
        :param img_name: Name of the image file
        :param annotations: DataFrame with bounding box annotations for the image
        :param img_dir: Directory containing the images
        :param split_name: Name of the data split (e.g., train, val, test, uploaded)
        :param create_embedding: Whether to create embeddings for the crops
        :return: True if at least one crop was created, False otherwise
        """
        img_path = img_dir / img_name

        if not img_path.exists():
            return False

        img = cv2.imread(str(img_path))
        if img is None:
            return False

        # Create output directory for this batch

        if split_name == 'uploaded':
           # img_name = 'uploaded' + img_name
            pass

        new_img_path = self.output_root / split_name / f"{batch_idx:01d}" / img_name.split('.')[0]
        new_img_path.mkdir(parents=True, exist_ok=True)

        base_name = Path(img_name).stem

        # Create all crops for this image
        image_created = False
        for crop_idx, (_, row) in enumerate(annotations.iterrows()):
            if await self.create_crop(crop_idx, row, img, base_name, new_img_path, img_name, create_embedding):
                image_created = True

        return image_created


    async def create_crops_from_csv(self, splits, max_images_per_batch=50, last_processed_row=None, create_embedding=False):
        """
         Create crops for given image folder
         Groups the images in batches
         :param splits: Dictionary with split names as keys and corresponding CSV filenames as values
        :param max_images_per_batch: Maximum number of input images per batch folder
        :param last_processed_row: Image name to resume from (if any)
        :param create_embedding:  Whether to create embeddings for the crops
        """

        # Process each split
        for split_name, csv_filename in splits.items():
            print(f"\n=== Processing {split_name} ===")

            csv_path = self.dataset_root / 'annotations' / csv_filename
            img_dir = self.dataset_root / 'images'

            if not csv_path.exists():
                print(f"Warning: {csv_path} not found, skipping...")
                continue

            # Format: image_name, x1, y1, x2, y2, class, image_width, image_height
            df = pd.read_csv(
                csv_path,
                header=None,
                names=['image_name', 'x1', 'y1', 'x2', 'y2', 'class', 'image_width', 'image_height']
            )
            print(f"Loaded {len(df)} annotations")

            print(f"CSV columns: {df.columns.tolist()}")
            print(f"First few rows:\n{df.head()}")

            grouped = df.groupby('image_name')
            image_names = list(grouped.groups.keys())

            # Skip already processed images
            if last_processed_row:
                grouped = [(img_name, annotations) for img_name, annotations in grouped if
                           img_name > last_processed_row]
                print(f"Resuming, {len(image_names) - len(grouped)} images already processed in {split_name}")
                print(f"Processing {len(grouped)} remaining images in {split_name}")
                print(f"Resuming from last processed image: {last_processed_row}")
            else:
                print(f"Found {len(image_names)} unique images")

            batch_idx = 0
            images_in_batch = 0

            # Create crops for each image
            for img_idx, (img_name, annotations) in enumerate(tqdm(grouped, desc=f"Cropping {split_name}")):
                if await self.create_crops_from_image(batch_idx, img_name, annotations, img_dir, split_name, create_embedding):
                    images_in_batch += 1

                #  Check if we need to start a new batch
                if images_in_batch >= max_images_per_batch:
                    images_in_batch = 0
                    batch_idx += 1

        print(f"\nCreated crops and saved to database")


    async def crop_splits(self, splits, max_images_per_batch=50, create_embedding=False):
        """
        Create crops for given splits with resume capability
        :param splits:  Dictionary with split names as keys and corresponding CSV filenames as values
        :param max_images_per_batch:  Maximum number of input images per batch folder
        :param create_embedding:  Whether to create embeddings for the crops
        """

        # Check for last processed image to resume
        last_processed_row = await self.db.get_last_processed_image()

        if last_processed_row:
            matched_split = next((s for s in splits.keys() if last_processed_row.startswith(s)), None)
            if not matched_split:
                last_processed_row = None
            elif matched_split == "test":
                print(f"Resuming from test split, skipping train split")
                splits = {k: v for k, v in splits.items() if k == "test"}

            elif matched_split == "val":
                print(f"Resuming from val split, skipping train and test splits")
                splits = {k: v for k, v in splits.items() if k == "val"}

        await self.create_crops_from_csv(splits, max_images_per_batch, last_processed_row, create_embedding)


    def copy_dataset_info(self, export_path):
        """
        Copy dataset information files to the export path.
        :param export_path: Path to save the exported dataset information
        """
        export_dir = Path(export_path)
        export_dir.mkdir(parents=True, exist_ok=True)

        license_src = self.dataset_root / "LICENSE.txt"
        license_dst = export_dir / "LICENSE.txt"
        if license_src.exists():
            shutil.copy2(license_src, license_dst)

        readme_src = self.dataset_root / "README.txt"
        readme_dst = export_dir / "annotations" / "README.txt"
        if readme_src.exists():
            shutil.copy2(readme_src, readme_dst)


    async def export_crop_dataset(self, export_path, original_splits=True):
        """
        Export cropped images and their annotations to a specified path.
        This Dataset is suitable for training image classification models.
        :param export_path: Path to save the exported dataset
        :param original_splits: Whether to use the original dataset splits
        """
        # Create directory structure
        export_dir = Path(export_path) / "SKU110K_crops_annotated"
        images_dir = export_dir / "images"
        annotations_dir = export_dir / "annotations"

        export_dir.mkdir(parents=True, exist_ok=True)
        images_dir.mkdir(parents=True, exist_ok=True)
        annotations_dir.mkdir(parents=True, exist_ok=True)

        # Get all crops with assigned classes using the new view
        assigned_crops = await self.db.get_crop_export_data()

        if not assigned_crops:
            print("No assigned crops found to export.")
            return

        df = pd.DataFrame(assigned_crops)

        splits = {'train': [], 'test': [], 'val': []}

        if original_splits:
            for _, row in df.iterrows():
                img_name = row['crop_file']

                if img_name.startswith('test_'):
                    splits['test'].append(row)
                elif img_name.startswith('val_'):
                    splits['val'].append(row)
                elif img_name.startswith('train_'):
                    splits['train'].append(row)
               # Ignore uploaded images(They have no bounding boxes assigned)
        else:
            # Create new splits: 70% train, 20% test, 10% val
            all_crops = df.to_dict('records')
            random.seed(42)  # For reproducibility
            random.shuffle(all_crops)

            total = len(all_crops)
            train_end = int(total * 0.7)
            test_end = train_end + int(total * 0.2)

            splits['train'] = all_crops[:train_end]
            splits['test'] = all_crops[train_end:test_end]
            splits['val'] = all_crops[test_end:]

        # Copy images and create CSV files for each split
        copied_images = set()

        for split_name, rows in splits.items():
            if not rows:
                continue

            split_df = pd.DataFrame(rows)

            # Copy images for this split
            for img_name, crop_path in tqdm(zip(split_df['crop_file'], split_df['crop_path']), desc=f"Copying {split_name} images", total=len(split_df)):
                if img_name not in copied_images:
                    src_img = self.output_root / crop_path
                    dst_img = images_dir / img_name

                    if src_img.exists():
                        shutil.copy2(src_img, dst_img)
                        copied_images.add(img_name)
                    else:
                        print(f"Warning: Source image not found: {src_img}")

            csv_path = annotations_dir / f"annotations_{split_name}.csv"

            export_df = split_df[['crop_file', 'class', 'image_width', 'image_height']]
            export_df.to_csv(csv_path, index=False, header=False)

            print(f"Exported {len(split_df)} crops to {split_name} split")

        license_src = self.dataset_root / "LICENSE.txt"
        license_dst = export_dir / "LICENSE.txt"
        if license_src.exists():
            shutil.copy2(license_src, license_dst)

        readme_dst = export_dir / "annotations" / "README.txt"
        readme_dst.parent.mkdir(parents=True, exist_ok=True)
        readme_dst.write_text("The CSV columns are:\nimage_name, class, image_width, image_height\n")

        print(f"\nDataset exported successfully")
        print(f"Total images copied: {len(copied_images)}")
        print(f"Total annotations: {len(assigned_crops)}")


    async def export_object_det_dataset(self, export_path, original_splits=True):
        """
        Export assigned images to a folder structure matching the original dataset.
        This Dataset is suitable for training object detection models with classification.
        :param export_path: Path to save the exported dataset
        :param original_splits: Whether to use the original dataset splits
        """
        # Create directory structure
        export_dir = Path(export_path) / "SKU110K_annotated"
        images_dir = export_dir / "images"
        annotations_dir = export_dir / "annotations"

        export_dir.mkdir(parents=True, exist_ok=True)
        images_dir.mkdir(parents=True, exist_ok=True)
        annotations_dir.mkdir(parents=True, exist_ok=True)

        # Get all images where all bounding boxes have assigned classes
        assigned_bboxes = await self.db.get_picture_bbox_with_assigned_classes()

        if not assigned_bboxes:
            print("No assigned bounding boxes found to export.")
            return

        df = pd.DataFrame(assigned_bboxes)

        splits = {'train': [], 'test': [], 'val': []}

        if original_splits:
            for _, row in df.iterrows():
                img_name = row['image_name']

                if img_name.startswith('test_'):
                    splits['test'].append(row)
                elif img_name.startswith('val_'):
                    splits['val'].append(row)
                elif img_name.startswith('train_'):
                    splits['train'].append(row)
            # Ignore uploaded images(They have no bounding boxes assigned)
        else:
            # Create new splits: 70% train, 20% test, 10% val
            # Group by image_name to ensure all bboxes of one image stay together
            grouped = df.groupby('image_name')
            image_groups = [(name, group) for name, group in grouped]

            random.seed(42)  # For reproducibility
            random.shuffle(image_groups)

            total_images = len(image_groups)
            train_end = int(total_images * 0.7)
            test_end = train_end + int(total_images * 0.2)

            train_images = image_groups[:train_end]
            test_images = image_groups[train_end:test_end]
            val_images = image_groups[test_end:]

            # Flatten groups back to rows
            for _, group in train_images:
                splits['train'].extend(group.to_dict('records'))
            for _, group in test_images:
                splits['test'].extend(group.to_dict('records'))
            for _, group in val_images:
                splits['val'].extend(group.to_dict('records'))

        copied_images = set()

        for split_name, rows in splits.items():
            if not rows:
                continue

            split_df = pd.DataFrame(rows)

            # Copy images for this split
            for img_name in tqdm(split_df['image_name'].unique(), desc=f"Copying {split_name} images"):
                if img_name not in copied_images:
                    src_img = self.dataset_root / 'images' / img_name
                    dst_img = images_dir / img_name

                    if src_img.exists():
                        shutil.copy2(src_img, dst_img)
                        copied_images.add(img_name)
                    else:
                        print(f"Warning: Source image not found: {src_img}")

            csv_path = annotations_dir / f"annotations_{split_name}.csv"

            export_df = split_df[['image_name', 'x1', 'y1', 'x2', 'y2', 'class_name', 'image_width', 'image_height']]
            export_df.to_csv(csv_path, index=False, header=False)

            print(f"Exported {len(split_df)} annotations from {len(split_df['image_name'].unique())} images to {split_name} split")

        self.copy_dataset_info(export_dir)

        print(f"\nDataset exported successfully")
        print(f"Total images copied: {len(copied_images)}")
        print(f"Total annotations: {len(assigned_bboxes)}")
