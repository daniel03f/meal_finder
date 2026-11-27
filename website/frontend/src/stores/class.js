import { ref, computed } from 'vue'
import { defineStore } from 'pinia'

export const useClassStore = defineStore('classes', () => {
  async function fetchClasses() {
    const response = await fetch('/api/classes');
    const data = await response.json();
    return data.classes || [];
  }

  async function fetchCropsByClass(className) {
    const response = await fetch(`/api/classes/${encodeURIComponent(className)}`);
    return await response.json();
  }

  async function fetchAssignedStatus() {
    const response = await fetch('/api/classes/assign');
    return await response.json();
  }

  async function createClass(className) {
      return await fetch('/api/classes', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ class_name: className })
      });
  }

  async function deleteClass(className) {
      return await fetch(`/api/classes/${className}`, {
          method: 'DELETE',
      });
  }

  async function renameClass(oldName, newName) {
      return await fetch(`/api/classes/${oldName}/rename`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ new_class_name: newName })
      });
  }

  async function assignCropToClass(cropPath, className) {
    const response = await fetch(`/api/classes/${className}/assign`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        crop_path: cropPath
      })
    });
    return await response.json();
  }




  return {
    fetchClasses,
    fetchCropsByClass,
    fetchAssignedStatus,
    createClass,
    deleteClass,
    renameClass,
    assignCropToClass
  }
})
