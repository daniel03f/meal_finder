# meal_finder

This app aims to help people with visual impairment to find
retail products in supermarket shelves through object detection
and guidance through audio signals.

## Features

- **Real Time Camera Feed**
- **Ultralytics YOLO Integration**
- **Real time Object Detection**
- **Recognition of supermarket items**
- **Recognition of multiple items simultaneously**
- **Select objects to search for out of label list**

## Usage

1. **Start App**: The app opens on home screen
2. **Choose Model**: Choose from dropdown menu
3. **Choose Objects**: Search for/Choose objects to find in a shopping list
4. **Permissions**: Allow for camera usage
5. **Camera feed**: Detected Objects are displayed in camera feed
6. **Audio Guide**: Follow the directions given by the audio guide to the object


## Selected Solution for Object Detection
1. Use SKU110K Dataset with bounding boxes and only one class
2. Train pre-trained YOLO Model to detect object facings
3. Make a knowledge base und use image embeddings to cluster specific products and label them more effectively
4. Use similarity to embeddings with specific label to search for this label in the stream and minimize the similarity search
(https://github.com/albertferre/shelf-product-identifier)
(https://www.reddit.com/r/computervision/comments/1bov6ew/how_to_segment_and_track_products_on_a/)

## Platform Support

- ✅ Android