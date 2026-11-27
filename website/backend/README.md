# Setup

Execute the following commands in PowerShell:
1. cd backend (only when not already in backend folder)
2. Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
3. .venv\Scripts\Activate.ps1
4. python -m pip install --upgrade pip
5. pip install -r requirements.txt

### TODOs:
Database:
- [ ] Refactor queries to be less redundant

Embeddings:
- [ ] Increase accuracy of embeddings
- [ ] Understand image embedding
- [ ] Look into if the dimensions of the embeddings is optimal

Clustering:
- [ ] Experiment with approximate predict
- [ ] Experiment with all_points_membership_vectors
- [ ] Experiment with approximate_predict_scores
- [ ] Experiment with  membership_vector
- [ ] Experiment with Branch Detection


Similarity:
- [ ] Define a good threshold for similarity