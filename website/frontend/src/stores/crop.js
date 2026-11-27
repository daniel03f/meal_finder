import { ref, computed } from 'vue'
import { defineStore } from 'pinia'

export const useCropStore = defineStore('crop', () => {
    async function fetchCrops(page, pageSize, selectedSplit = 'all') {
        const response = await fetch(`/api/crops?page=${page}&page_size=${pageSize}&split=${selectedSplit}`);
        return await response.json();
  }

  async function inferClass(cropPath, topK = 5, threshold = 0.8, class_name=null) {
    const inferResp = await fetch(`/api/crops/${encodeURIComponent(cropPath)}/infer?top_k=${topK}&threshold=${threshold}&class_name=${class_name || ''}`);
    const inferData = await inferResp.json().catch(() => ({}));

    const similarResp = await fetch(`/api/crops/${encodeURIComponent(cropPath)}/similar?top_k=${topK}&class_name=${class_name || ''}`);
    const similarData = await similarResp.json().catch(() => ({}));

    return { inferResp, similarResp, inferData, similarData };
  }

  async function assignCropToClass(cropPath, className) {
    const response = await fetch(`/api/classes/${encodeURIComponent(className)}/assign`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ crop_path: cropPath })
    });
    return await response.json();
  }

  async function deleteCrop(cropPath) {
    const response = await fetch(`/api/crops/${encodeURIComponent(cropPath)}`, {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
    });
    return await response.json();
  }

  async function uploadCrops(files) {
    const results = [];

    for (const file of files) {
      const formData = new FormData();
      formData.append('image', file);

      const response = await fetch(`/api/crops/upload`, {
        method: 'POST',
        body: formData
      });

      const result = await response.json();
      results.push(result);
    }

    return results;
  }

  return {
    fetchCrops,
    inferClass,
    assignCropToClass,
    deleteCrop,
    uploadCrops
  }
})
