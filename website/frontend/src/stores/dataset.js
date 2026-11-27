import { defineStore } from 'pinia';

export const useDatasetStore = defineStore('dataset', () => {
    async function createCropDataset(outputPath, originalSplits) {
      try {
        const response = await fetch(`/api/dataset/create_img_class`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            output_path: outputPath,
            original_splits: originalSplits
          }),
        });
        return await response.json();
      } catch (error) {
        console.error('Error creating crop dataset:', error);
        throw error;
      }
    }

    async function createObjectDetectionDataset(outputPath, originalSplits) {
      try {
        const response = await fetch(`/api/dataset/create_objdet`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            output_path: outputPath,
            original_splits: originalSplits
          }),
        });
        return await response.json();
      } catch (error) {
        console.error('Error creating object detection dataset:', error);
        throw error;
      }
    }
    return {
      createCropDataset,
      createObjectDetectionDataset
    }
})
