import { ref, computed } from 'vue'
import { defineStore } from 'pinia'


export const useClusterStore = defineStore('cluster', () => {
  async function fetchClusters(nClusters, minSamples, cluster_page = 0, cluster_page_size = 1000, split = 'all') {
    const params = new URLSearchParams({
      n_clusters: nClusters.toString(),
      min_samples: minSamples.toString(),
      cluster_page: cluster_page.toString(),
      cluster_page_size: cluster_page_size.toString(),
      split: split
    });

    const response = await fetch(`/api/clusters?${params}`);
    return await response.json();
  }


  return {
    fetchClusters
  }
})
