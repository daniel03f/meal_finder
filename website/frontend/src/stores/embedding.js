import { defineStore } from 'pinia'

export const useEmbeddingStore = defineStore('embedding', () => {
  async function fetchEmbeddingStatus() {
    const response = await fetch('/api/embeddings/status');
    return await response.json();
  }

  async function createNextEmbeddings(processedOrigins = 1) {
    const response = await fetch('/api/embeddings/create-next', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ processed_origins: processedOrigins })
    });
    return await response.json();
  }

  return {
    fetchEmbeddingStatus,
    createNextEmbeddings
  }
})

