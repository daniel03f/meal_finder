## Image Classifier App

This is an image classifier app that allows users to create classes 
and assign images to them based on their similarity. 
The app uses the SKU110K dataset for images with coordinates for crops
and a pre-trained model to extract image embeddings 
and calculates cosine similarity to group similar images together.

Based on these results one can infer which images belong to the same class.
It can be used for 2-step object detection and classification tasks.
It can also be used to quickly label images for other tasks.

### Setups
[Setup Backend](backend/README.md)

[Setup Frontend](frontend/README.md)

Change the paths to your dataset in [main.py](main.py) and [app.py](app.py) before running the code.

### Usage
1.  Crop Images with python main.py
2. run in route folder: python app.py
3. Then run in frontend folder: npm run dev
4. Then open the displayed port in browser
5. Create Classes and assign images to them

### Next Steps
- Integrate product images from API to speed up classification
- Show uploaded images(makes it easier to delete)
- Show inferred classes based on class voting with embeddings for clusters

### Todos:
- Code:
  - Proper Code Documentation
- Testing:
  - Create unit tests for the different modules

Credits to Albert Ferré Vidal for inspiriting this project:
https://github.com/albertferre/shelf-product-identifier