<script setup>

import {useToast} from "primevue/usetoast";
import {computed, ref} from "vue";
import { useExportDbStore } from '@/stores/export_db';

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible']);

const toast = useToast();

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

const isExporting = ref(false);
const exportStore = useExportDbStore();

async function exportDataset() {
  isExporting.value = true;
  try {
    const res = await exportStore.exportClassEmbeddings();
    if (res && res.success) {
      toast.add({
        severity: 'success',
        summary: 'Success',
        detail: 'Database exported successfully',
        life: 3000
      });
      isOpen.value = false;
    } else {
      const errMsg = (res && res.error) ? res.error : 'Export failed';
      toast.add({
        severity: 'error',
        summary: 'Error',
        detail: errMsg,
        life: 5000
      });
    }
  } catch (err) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: err.message || 'An error occurred while exporting database.',
      life: 5000
    })
  } finally {
    isExporting.value = false;
  }
}

</script>

<template>
  <Dialog  v-model:visible="isOpen" modal header="Export Database" :style="{ width: '600px' }">
     <div class="flex flex-col gap-4">
       <div class="flex flex-col gap-2">
         Exports only the annotated classes with embeddings in the database.
       </div>
     </div>
     <template #footer>
       <Button
         label="Export"
         @click="exportDataset"
         :loading="isExporting"
       />
      <ProgressSpinner v-if="isExporting"/>
     </template>
  </Dialog>
</template>

<style scoped>

</style>
