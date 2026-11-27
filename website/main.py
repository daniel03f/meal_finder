from backend.scripts.crop_images import CropProcessor
from backend.scripts.database_manager import DatabaseManager
from pathlib import Path
import asyncio


async def main():

    # Paths:
    project_root = Path(__file__).parent
    dataset_root = r"C:\Users\2dani\Documents\Fh\Bachelorarbeit\ProductImages\SKU110K_fixed"   # Insert your dataset root path here
    output_root = project_root / "backend" / "crops"
    db_path  = project_root / "image_embeddings.sqlite"

    db1 = DatabaseManager(db_path)

    print("=== 1: Create CropsDialog ===")
    processor = CropProcessor(
        output_root,
        dataset_root,
        db1)

    sku_splits = {
        'train': 'annotations_train.csv',
        'test': 'annotations_test.csv',
        'val': 'annotations_val.csv'
    }

    await processor.crop_splits(sku_splits, 50)

    print("\n=== Completed ===")
    print(f"CropsDialog created and saved to database. Use the Web-UI to create embeddings incrementally.")
    print(f"Start Server with: python app.py")
    print(f"Then run the following command in another terminal:")
    print(f"cd frontend")
    print(f"npm install")
    print(f"npm run dev")
    print(f"Then open the URL displayed in the terminal.")


if __name__ == "__main__":
    asyncio.run(main())
