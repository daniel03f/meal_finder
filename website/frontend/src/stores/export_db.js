import { defineStore } from 'pinia'

export const useExportDbStore = defineStore('export_db', () => {
  async function exportClassEmbeddings() {
    try {
      const response = await fetch('/api/database/export/class_embeddings', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' }
      });

      const data = await response.json().catch(() => null);
      if (!response.ok) {
        return { success: false, error: (data && data.error) ? data.error : `HTTP ${response.status}` };
      }

      return data || { success: true };
    } catch (err) {
      console.error('Error exporting class embeddings:', err);
      return { success: false, error: err.message };
    }
  }

  return { exportClassEmbeddings }
})

