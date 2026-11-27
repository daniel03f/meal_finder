import numpy as np
from pathlib import Path
import aiosqlite
import sqlite_vector


def convert_rows_to_dicts_with_numpy_embeddings(rows):
    """
    Helper function to convert DB rows to list of dicts with numpy embeddings.
    :param rows: List of database rows(aiosqlite.Row objects)
    :returns: List of dicts with numpy arrays for embeddings
    """
    result = []
    for row in rows:
        item = dict(row)
        if item.get('embedding'):
            # Convert bytes back to numpy array
            embedding = np.frombuffer(item['embedding'], dtype=np.float32)
            item['embedding'] = embedding.tolist()
        item['bounding_box'] = [item['bbox_x1'], item['bbox_y1'], item['bbox_x2'], item['bbox_y2']]
        result.append(item)

    return result


# noinspection SqlResolve
class DatabaseManager:
    """Manages the SQLite database for crops, embeddings, and classes."""

    def __init__(self, db_path=None):
        if db_path is None:
            project_root = Path(__file__).parent.parent.parent
            db_path = project_root / "image_embeddings.sqlite"

        self.db_path = Path(db_path)

        db_exists = self.db_path.exists()

        self.db_path.parent.mkdir(parents=True, exist_ok=True)

        self.conn = None

        if db_exists:
            print(f"Using existing database: {self.db_path}")
        else:
            print(f"Creating new database: {self.db_path}")

    async def connect(self):
        """Establish async database connection."""
        if self.conn is None:
            self.conn = await aiosqlite.connect(str(self.db_path))
            self.conn.row_factory = aiosqlite.Row
            await self.conn.execute('PRAGMA foreign_keys = ON')
            await self._init_tables()
            await self._load_vector_extension()
            await self._init_vector_index()


    async def _load_vector_extension(self):
        """Load the SQLite Vector extension (SIMD-accelerated cosine search)."""
        import os
        try:
            dll_path = os.path.join(sqlite_vector.__path__[0], 'binaries', 'vector')
            await self.conn.enable_load_extension(True)
            await self.conn.load_extension(dll_path)
            await self.conn.enable_load_extension(False)
            print(f"SQLite Vector extension loaded from {dll_path}")
        except Exception as e:
            print(f"Warning: Could not load SQLite Vector extension: {e}")


    async def _init_vector_index(self):
        """Initialize, quantize and preload the crops vector index."""
        await self.conn.execute(
            "SELECT vector_init('crops', 'embedding', 'type=FLOAT32,dimension=384,distance=COSINE')"
        )
        await self.conn.execute("SELECT vector_quantize('crops', 'embedding')")
        await self.conn.execute("SELECT vector_quantize_preload('crops', 'embedding')")
        await self.conn.commit()
        print("Vector index built and preloaded into memory (~30 MB)")

    async def refresh_vector_index(self):
        """
        Rebuild and preload the quantized vector index.
        Call this after adding new embeddings (e.g. after embed_crops()).
        """
        await self.conn.execute("SELECT vector_quantize('crops', 'embedding')")
        await self.conn.execute("SELECT vector_quantize_preload('crops', 'embedding')")
        await self.conn.commit()
        print("Vector index refreshed and preloaded")


    async def _init_tables(self):
        """Initialize database tables if they don't exist."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                CREATE TABLE IF NOT EXISTS original_images (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    image_name TEXT UNIQUE NOT NULL,
                    image_width INTEGER,
                    image_height INTEGER,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')

            await cursor.execute('''
                CREATE TABLE IF NOT EXISTS crops (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    crop_file TEXT NOT NULL,
                    crop_path TEXT NOT NULL UNIQUE,
                    original_image_id INTEGER,
                    bbox_x1 INTEGER,
                    bbox_y1 INTEGER,
                    bbox_x2 INTEGER,
                    bbox_y2 INTEGER,
                    embedding BLOB,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (original_image_id) REFERENCES original_images(id) ON DELETE CASCADE
                )
            ''')

            await cursor.execute('''
                CREATE TABLE IF NOT EXISTS classes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL,
                    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                )
            ''')

            await cursor.execute('''
                CREATE TABLE IF NOT EXISTS crop_class_assignments (
                    crop_id INTEGER,
                    class_id INTEGER,
                    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                    FOREIGN KEY (crop_id) REFERENCES crops(id) ON DELETE CASCADE,
                    FOREIGN KEY (class_id) REFERENCES classes(id) ON DELETE CASCADE,
                    PRIMARY KEY (crop_id, class_id)
                )
            ''')

            await cursor.execute('''
                CREATE VIEW IF NOT EXISTS picture_bboxes AS
                SELECT
                    org_img.image_name AS image_name,
                    c.bbox_x1 AS x1,
                    c.bbox_y1 AS y1,
                    c.bbox_x2 AS x2,
                    c.bbox_y2 AS y2,
                    cls.name AS class_name,
                    org_img.image_width AS image_width,
                    org_img.image_height AS image_height
                FROM
                    crops c
                LEFT JOIN
                    crop_class_assignments cca ON c.id = cca.crop_id
                LEFT JOIN
                    classes cls ON cca.class_id = cls.id
                LEFT JOIN
                    original_images org_img ON c.original_image_id = org_img.id
            ''')

            await cursor.execute('''
               CREATE VIEW IF NOT EXISTS crops_class_view AS
                SELECT
                    c.crop_file,
                    c.crop_path,
                    cls.name AS class,
                    (c.bbox_x2 - c.bbox_x1) AS image_width,
                    (c.bbox_y2 - c.bbox_y1) AS image_height
                FROM
                    crops c
                JOIN
                    crop_class_assignments cca ON c.id = cca.crop_id
                JOIN
                    classes cls ON cca.class_id = cls.id
            ''')

            await cursor.execute('''
                CREATE VIEW IF NOT EXISTS embedding_class_view AS
                SELECT crops.id AS id, crops.embedding AS embedding, classes.name AS class
                FROM crops
                JOIN crop_class_assignments cca ON crops.id = cca.crop_id
                JOIN classes ON cca.class_id = classes.id
                WHERE crops.embedding IS NOT NULL AND classes.name IS NOT NULL
            ''')

            await cursor.execute('CREATE INDEX IF NOT EXISTS idx_original_image_id ON crops(original_image_id)')
            await cursor.execute('CREATE INDEX IF NOT EXISTS idx_source_image ON original_images(image_name)')
            await cursor.execute('CREATE INDEX IF NOT EXISTS idx_crop_path ON crops(crop_path)')
            await cursor.execute('CREATE INDEX IF NOT EXISTS idx_class_name ON classes(name)')
            await cursor.execute('CREATE INDEX IF NOT EXISTS idx_crop_class_assignments_class_id ON crop_class_assignments(class_id)')

        await self.conn.commit()

    async def insert_or_get_original_image(self, image_name, image_width=None, image_height=None):
        """Insert or get an original image."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT id FROM original_images WHERE image_name = ?', (image_name,))
            row = await cursor.fetchone()

            if row:
                return row[0]

            await cursor.execute('''
                INSERT INTO original_images (image_name, image_width, image_height)
                VALUES (?, ?, ?)
            ''', (image_name, image_width, image_height))
            await self.conn.commit()
            return cursor.lastrowid

    async def insert_crop(self, crop_file, crop_path, source_image, bbox, image_width=None, image_height=None, embedding=None):
        """Insert a new crop into the database."""
        original_image_id = await self.insert_or_get_original_image(source_image, image_width, image_height)

        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                INSERT OR IGNORE INTO crops (crop_file, crop_path, original_image_id, bbox_x1, bbox_y1, bbox_x2, bbox_y2)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            ''', (crop_file, crop_path, original_image_id, bbox[0], bbox[1], bbox[2], bbox[3]))

            if embedding is not None:
                await self.update_embedding(crop_path, embedding)

            await self.conn.commit()
            return cursor.lastrowid

    async def delete_crop(self, crop_path):
        """Delete a crop from the database."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('DELETE FROM crops WHERE crop_path = ?', (crop_path,))
            await self.conn.commit()
            return cursor.rowcount > 0

    async def update_embedding(self, crop_path, embedding):
        """Update embedding for a crop."""
        embedding_bytes = embedding.astype(np.float32).tobytes()

        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                UPDATE crops 
                SET embedding = ?
                WHERE crop_path = ?''',
                (embedding_bytes, crop_path))
            await self.conn.commit()

    async def get_last_processed_image(self):
        """Get the name of the last processed original image."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT oi.image_name
                FROM original_images oi
               JOIN crops c ON c.original_image_id = oi.id
                ORDER BY oi.created_at DESC
                LIMIT 1
            ''')
            row = await cursor.fetchone()
            return row['image_name'] if row else None

    async def get_crops_without_embeddings(self):
        """Get all crops that don't have embeddings yet."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT * FROM crops WHERE embedding IS NULL')
            return await cursor.fetchall()

    async def get_crops_by_origin(self, source_image):
        """Get all crops from a specific source image."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.* FROM crops c
                JOIN original_images oi ON c.original_image_id = oi.id
                WHERE oi.image_name = ?
            ''', (source_image,))
            return await cursor.fetchall()

    async def get_unprocessed_origins(self):
        """Get list of source images that have crops without embeddings."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT DISTINCT oi.image_name 
                FROM original_images oi
                JOIN crops c ON c.original_image_id = oi.id
                WHERE c.embedding IS NULL
            ''')
            rows = await cursor.fetchall()
            return [row[0] for row in rows]

    async def get_all_crops_with_embeddings(self, page=0, page_size=10000):
        """
        Get subset of crops that have embeddings.
        :param page: Page number for pagination (0-indexed)
        :param page_size: Number of items per page
        :returns List of dicts with numpy arrays for embeddings
        """
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.*, cl.name as assigned_class
                FROM crops c
                LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                LEFT JOIN classes cl ON cca.class_id = cl.id
                WHERE c.embedding IS NOT NULL 
                LIMIT ? OFFSET ? 
            ''', (page_size, page * page_size,))
            rows = await cursor.fetchall()
            return convert_rows_to_dicts_with_numpy_embeddings(rows)

    async def get_crops_with_embeddings_by_split(self, split_name, page=0, page_size=120):
        """Get crops with embeddings filtered by split."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.*, cl.name as assigned_class
                FROM crops c
                LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                LEFT JOIN classes cl ON cca.class_id = cl.id
                WHERE c.embedding IS NOT NULL AND c.crop_path LIKE ?
                LIMIT ? OFFSET ?
            ''', ('%' + split_name + '%', page_size, page * page_size))
            rows = await cursor.fetchall()
            return convert_rows_to_dicts_with_numpy_embeddings(rows)

    async def get_crops_with_embeddings_class(self, page=0, page_size=1000):
        """Get crops with embeddings that are embedded and assigned."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.*, cl.name as assigned_class
                FROM crops c
                JOIN crop_class_assignments cca ON c.id = cca.crop_id
                JOIN classes cl ON cca.class_id = cl.id
                WHERE c.embedding IS NOT NULL
                LIMIT ? OFFSET ?
             ''', (page_size, page * page_size))

            rows = await cursor.fetchall()
            return convert_rows_to_dicts_with_numpy_embeddings(rows)

    async def get_crops_with_embeddings_without_class(self, page=0, page_size=1000):
        """Get crops that are embedded but not assigned to a class."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.*, NULL as assigned_class
                FROM crops c
                LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                WHERE c.embedding IS NOT NULL AND cca.crop_id IS NULL
                LIMIT ? OFFSET ?
             ''', (page_size, page * page_size))

            rows = await cursor.fetchall()
            return convert_rows_to_dicts_with_numpy_embeddings(rows)

    async def count_embedded_crops_by_split(self, split_name):
        """Count crops in a specific split."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT COUNT(*)
                FROM crops c
                WHERE c.embedding IS NOT NULL AND c.crop_path LIKE ?
            ''', ('%' + split_name + '%',))
            row = await cursor.fetchone()
            return row[0]

    async def count_embedded_assigned_crops(self):
        """Count crops that are embedded and assigned."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT COUNT(DISTINCT c.id) FROM crops c
                JOIN crop_class_assignments cca ON c.id = cca.crop_id
                WHERE  cca.crop_id IS NOT NULL AND  c.embedding IS NOT NULL
            ''')
            row = await cursor.fetchone()
            return row[0]

    async def count_embedded_unassigned_crops(self):
        """Count crops that are embedded and unassigned."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                    SELECT COUNT(*) FROM crops c
                    LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                    WHERE cca.crop_id IS NULL AND c.embedding IS NOT NULL
                ''')
            row = await cursor.fetchone()
            return row[0]

    async def create_class(self, class_name):
        """Create a new class."""
        async with self.conn.cursor() as cursor:
            try:
                await cursor.execute('INSERT INTO classes (name) VALUES (?)', (class_name,))
                await self.conn.commit()
                return True
            except aiosqlite.IntegrityError:
                return False

    async def delete_class(self, class_name):
        """Delete a class."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('DELETE FROM classes WHERE name = ?', (class_name,))
            await self.conn.commit()
            return cursor.rowcount > 0

    async def rename_class(self, old_name, new_name):
        """Update the name of an existing class."""
        async with self.conn.cursor() as cursor:
            try:
                await cursor.execute('UPDATE classes SET name = ? WHERE name = ?', (new_name, old_name))
                await self.conn.commit()
                return cursor.rowcount > 0
            except aiosqlite.IntegrityError:
                return False

    async def get_all_classes(self):
        """Get all classes."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT name FROM classes ORDER BY name')
            rows = await cursor.fetchall()
            return [row[0] for row in rows]

    async def assign_crop_to_class(self, crop_path, class_name):
        """Assign a crop to a class."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT id FROM crops WHERE crop_path = ?', (crop_path,))
            crop_row = await cursor.fetchone()
            if not crop_row:
                return False
            crop_id = crop_row[0]

            await cursor.execute('SELECT id FROM classes WHERE name = ?', (class_name,))
            class_row = await cursor.fetchone()
            if not class_row:
                return False
            class_id = class_row[0]

            await cursor.execute('''
            INSERT OR REPLACE INTO crop_class_assignments (crop_id, class_id)
                VALUES (?, ?)
            ''', (crop_id, class_id))
            await self.conn.commit()
            return True

    async def get_class_crops(self, class_name):
        """Get all crops assigned to a specific class."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT c.*, cl.name as assigned_class
                FROM crops c
                JOIN crop_class_assignments cca ON c.id = cca.crop_id
                JOIN classes cl ON cca.class_id = cl.id
                WHERE cl.name = ?
            ''', (class_name,))
            rows = await cursor.fetchall()
            return convert_rows_to_dicts_with_numpy_embeddings(rows)

    async def get_crop(self, crop_path):
        """Get a specific crop by its path."""
        async with self.conn.cursor() as cursor:
            crop_path = str(crop_path)
            await cursor.execute('SELECT * FROM crops WHERE crop_path = ?', (crop_path,))
            row = await cursor.fetchone()
            if row:
                return convert_rows_to_dicts_with_numpy_embeddings([row])[0]
            return None

    async def get_embeddings_status(self):
        """Get status of embeddings creation."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''SELECT COUNT(*) FROM crops''')
            row = await cursor.fetchone()
            total_crops = row[0]

            await cursor.execute('''
                SELECT COUNT(DISTINCT oi.id)
                FROM original_images oi
                JOIN crops c ON c.original_image_id = oi.id
            ''')
            row = await cursor.fetchone()
            total_origins = row[0]

            await cursor.execute('''
                SELECT COUNT(DISTINCT oi.id)
                FROM original_images oi
                JOIN crops c ON c.original_image_id = oi.id
                WHERE c.embedding IS NOT NULL
            ''')
            row = await cursor.fetchone()
            processed_origins = row[0]

            await cursor.execute('SELECT COUNT(*) FROM crops WHERE embedding IS NOT NULL')
            row = await cursor.fetchone()
            total_embeddings = row[0]

            return {
                'total_crops': total_crops,
                'total_origins': total_origins,
                'processed_origins': processed_origins,
                'total_embeddings': total_embeddings,
            }

    async def get_assigned_status(self):
        """Get status of crop-class assignments."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT COUNT(*) FROM crops')
            row = await cursor.fetchone()
            total_crops = row[0]

            await cursor.execute('''
                SELECT COUNT(DISTINCT c.id)
                FROM crops c
                JOIN crop_class_assignments cca ON c.id = cca.crop_id
            ''')
            row = await cursor.fetchone()
            assigned_crops = row[0]

            return {
                'total_crops': total_crops,
                'assigned_crops': assigned_crops
            }

    async def get_picture_bboxes(self):
        """Get all picture bounding boxes with class names."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT * FROM picture_bboxes')
            rows = await cursor.fetchall()
            result = []
            for row in rows:
                result.append(dict(row))
            return result

    async def get_picture_bboxes_for_image(self, image_name):
        """Get picture bounding boxes for a specific image."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT * FROM picture_bboxes WHERE image_name = ?', (image_name,))
            rows = await cursor.fetchall()
            result = []
            for row in rows:
                result.append(dict(row))
            return result

    async def get_picture_bbox_with_assigned_classes(self):
        """Get picture bounding boxes where ALL crops of an image have assigned classes."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('''
                SELECT pb.*
                FROM picture_bboxes pb
                WHERE pb.class_name IS NOT NULL
                AND pb.image_name IN (
                    SELECT oi.image_name
                    FROM original_images oi
                    WHERE NOT EXISTS (
                        SELECT 1
                        FROM crops c
                        LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                        WHERE c.original_image_id = oi.id
                        AND cca.crop_id IS NULL
                    )
                    AND EXISTS (
                        SELECT 1
                        FROM crops c
                        WHERE c.original_image_id = oi.id
                    )
                )
            ''')
            rows = await cursor.fetchall()
            result = []
            for row in rows:
                result.append(dict(row))
            return result

    async def get_crop_export_data(self):
        """Get all crops with assigned classes for export (with calculated dimensions)."""
        async with self.conn.cursor() as cursor:
            await cursor.execute('SELECT * FROM crops_class_view')
            rows = await cursor.fetchall()
            result = []
            for row in rows:
                result.append(dict(row))
            return result

    async def find_similar_crops(
        self,
        query_embedding,
        class_name: str,
        exclude_path: str,
        top_k: int = 5,
    ):
        """
        Find similar crops using SQLite Vector quantized scan.
        Streams results in cosine-distance order; SQL LIMIT provides early exit.

        :param query_embedding: Embedding as list/array of float32
        :param class_name: Optional – restrict search to crops of this class
        :param exclude_path: Optional – crop_path to exclude (the query crop itself)
        :param top_k: Number of results to return
        :returns: List of dicts with crop_file, crop_path, similarity, assigned_class
        """
        query_blob = np.array(query_embedding, dtype=np.float32).tobytes()
        exclude_path = exclude_path or ''

        async with self.conn.cursor() as cursor:
            if class_name:
                await cursor.execute(
                    '''
                    SELECT c.crop_file, c.crop_path, ecv.class AS assigned_class, v.distance
                    FROM   crops AS c
                    JOIN   vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                    JOIN   embedding_class_view ecv ON c.id = ecv.id
                    WHERE  ecv.class = ? AND c.crop_path != ?
                    ORDER BY v.distance
                    LIMIT ?
                    ''',
                    (query_blob, class_name, exclude_path, top_k),
                )
            else:
                await cursor.execute(
                    '''
                    SELECT c.crop_file, c.crop_path, cl.name AS assigned_class, v.distance
                    FROM   crops AS c
                    JOIN   vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                    LEFT JOIN crop_class_assignments cca ON c.id = cca.crop_id
                    LEFT JOIN classes cl ON cca.class_id = cl.id
                    WHERE  c.crop_path != ?
                    ORDER BY v.distance
                    LIMIT ?
                    ''',
                    (query_blob, exclude_path, top_k),
                )
            rows = await cursor.fetchall()

        return [
            {
                'crop_file': row['crop_file'],
                'crop_path': row['crop_path'],
                'similarity': float((2.0 - row['distance']) / 2.0),  # cosine dist -> similarity
                'assigned_class': row['assigned_class'],
            }
            for row in rows
        ]

    async def compute_class_similarities(
        self,
        query_embedding,
        class_names: list,
        exclude_path: str,
    ) -> dict:
        """
        Compute average cosine similarity to every (or specified) class using
        vector_quantize_scan.

        :param query_embedding: Embedding as list/array of float32
        :param class_names: Optional list – restrict to these classes
        :param exclude_path: Optional – crop_path to exclude (the query crop itself)
        :returns: {class_name: avg_similarity_score, ...} sorted best-first
        """
        query_blob = np.array(query_embedding, dtype=np.float32).tobytes()
        exclude_path = exclude_path or ''

        async with self.conn.cursor() as cursor:
            if class_names:
                placeholders = ','.join('?' * len(class_names))
                await cursor.execute(
                    f'''
                    SELECT ecv.class AS assigned_class, AVG(v.distance) AS avg_distance
                    FROM   crops AS c
                    JOIN   vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                    JOIN   embedding_class_view ecv ON c.id = ecv.id
                    WHERE  ecv.class IN ({placeholders})
                      AND  ecv.class != 'unassigned'
                      AND  c.crop_path != ?
                    GROUP BY ecv.class
                    ORDER BY avg_distance
                    ''',
                    [query_blob, *class_names, exclude_path],
                )
            else:
                await cursor.execute(
                    '''
                    SELECT ecv.class AS assigned_class, AVG(v.distance) AS avg_distance
                    FROM   crops AS c
                    JOIN   vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                    JOIN   embedding_class_view ecv ON c.id = ecv.id
                    WHERE  ecv.class != 'unassigned'
                      AND  c.crop_path != ?
                    GROUP BY ecv.class
                    ORDER BY avg_distance
                    ''',
                    (query_blob, exclude_path),
                )
            rows = await cursor.fetchall()

        # Convert cosine distance [0, 2] → similarity [0, 1]
        return {
            row['assigned_class']: float((2.0 - row['avg_distance']) / 2.0)
            for row in rows
        }

    async def find_best_class(
        self,
        query_embedding,
        exclude_path: str,
        class_names: list,
        limit_per_class: int = 10,
    ):
        """
        Find the single best matching class:
        For each class, take the top `limit_per_class` nearest vectors (by distance),
        average their distances and pick the class with the lowest average distance.

        :param query_embedding: Embedding as list/array of float32
        :param exclude_path: Optional – crop_path to exclude (the query crop itself)
        :param class_names: Optional list – restrict to these classes
        :param limit_per_class: Number of nearest neighbors to consider per class for averaging
        :returns A tuple of (best_class_name, confidence_score) where confidence is in [0, 1] based on distance.
        """
        query_blob = np.array(query_embedding, dtype=np.float32).tobytes()
        exclude_path = exclude_path or ''

        async with self.conn.cursor() as cursor:
            if class_names:
                placeholders = ','.join('?' * len(class_names))

                await cursor.execute(
                    f'''
                    SELECT assigned_class, AVG(distance) AS avg_distance
                    FROM (
                      SELECT ecv.class AS assigned_class, v.distance,
                        ROW_NUMBER() OVER (PARTITION BY ecv.class ORDER BY v.distance) AS rn
                      FROM crops AS c
                      JOIN vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                      JOIN embedding_class_view ecv ON c.id = ecv.id
                      WHERE ecv.class IN ({placeholders})
                        AND ecv.class != 'unassigned'
                        AND c.crop_path != ?
                    ) sub
                    WHERE rn <= ?
                    GROUP BY assigned_class
                    ORDER BY avg_distance
                    LIMIT 1
                    ''',
                    [query_blob, *class_names, exclude_path, limit_per_class],
                )
            else:
                await cursor.execute(
                    '''
                    SELECT assigned_class, AVG(distance) AS avg_distance
                    FROM (
                      SELECT ecv.class AS assigned_class, v.distance,
                        ROW_NUMBER() OVER (PARTITION BY ecv.class ORDER BY v.distance) AS rn
                      FROM crops AS c
                      JOIN vector_quantize_scan('crops', 'embedding', ?) AS v ON c.id = v.rowid
                      JOIN embedding_class_view ecv ON c.id = ecv.id
                      WHERE ecv.class != 'unassigned'
                        AND c.crop_path != ?
                    ) sub
                    WHERE rn <= ?
                    GROUP BY assigned_class
                    ORDER BY avg_distance
                    LIMIT 1
                    ''',
                    (query_blob, exclude_path, limit_per_class),
                )

            row = await cursor.fetchone()

        if not row:
            return None, 0.0

        best_class = row['assigned_class']
        avg_distance = float(row['avg_distance'])
        confidence = (2.0 - avg_distance) / 2.0

        return best_class, float(confidence)

    async def export_db(self, output_path=None):
        """
        Export a minimal database that contains the classes table and embedding_class_view
        If output_path is None, export into the same directory as the main DB with
        filename `class_embeddings.sqlite`.
        Returns a dict with success status and path.
        """
        if output_path is None:
            output_path = self.db_path.parent / 'class_embeddings.sqlite'
        else:
            output_path = Path(output_path)

        if output_path.exists() and output_path.is_dir():
            output_path = output_path / 'class_embeddings.sqlite'

        if output_path.suffix.lower() not in ('.sqlite', '.db'):
            output_path = output_path.with_suffix('.sqlite')

        output_path.parent.mkdir(parents=True, exist_ok=True)

        async with self.conn.cursor() as cursor:
            await cursor.execute("SELECT name FROM classes")
            classes_rows = await cursor.fetchall()

            await cursor.execute("SELECT embedding, class FROM embedding_class_view")
            embedding_class_rows = await cursor.fetchall()

        try:
            dst_conn = await aiosqlite.connect(str(output_path))
        except Exception as e:
            raise RuntimeError(f"Could not create destination DB file '{output_path}': {e}")

        try:
            await dst_conn.execute('''
                CREATE TABLE IF NOT EXISTS classes (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT UNIQUE NOT NULL
                )
            ''')

            await dst_conn.execute('''
                CREATE TABLE IF NOT EXISTS embedding_class (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    embedding BLOB NOT NULL,
                    class_name TEXT NOT NULL
                )
            ''')

            class_values = []
            for row in classes_rows:
                try:
                    name = row['name']
                except Exception:
                    name = row[0]
                class_values.append((name,))

            embed_values = []
            for row in embedding_class_rows:
                try:
                    emb = row['embedding']
                    cls = row['class']
                except Exception:
                    emb = row[0]
                    cls = row[1]
                embed_values.append((emb, cls))

            if class_values:
                await dst_conn.executemany('INSERT OR IGNORE INTO classes (name) VALUES (?)', class_values)

            if embed_values:
                await dst_conn.executemany('INSERT INTO embedding_class (embedding, class_name) VALUES (?, ?)', embed_values)

            await dst_conn.commit()
            return {'success': True, 'path': str(output_path)}
        finally:
            await dst_conn.close()


    async def close(self):
        """Close database connection."""
        if self.conn:
            await self.conn.close()
