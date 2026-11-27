<script setup>
import { ref, watch, computed } from 'vue';
import { useEmbeddingStore } from '@/stores/embedding';
import { useToast } from 'primevue/usetoast';

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible', 'embeddings-created']);

const embeddingStore = useEmbeddingStore();

const toast = useToast();

const processedOrigins = ref(1);
const processAll = ref(false);
const embeddingStatus = ref(null);
const isLoading = ref(false);
const isCreating = ref(false);

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

watch(() => props.visible, async (newVal) => {
  if (newVal) {
    await loadEmbeddingStatus();
  }
});

async function loadEmbeddingStatus() {
  isLoading.value = true;
  try {
    embeddingStatus.value = await embeddingStore.fetchEmbeddingStatus();
  } finally {
    isLoading.value = false;
  }
}

async function createEmbeddings() {
  isCreating.value = true;
  try {
    const originsToProcess = processAll.value ?  Number.MAX_SAFE_INTEGER : parseInt(processedOrigins.value);
    const result = await embeddingStore.createNextEmbeddings(originsToProcess);

    if (result.status === 'complete') {
      toast.add({
        severity: 'success',
        summary: 'EmbeddingsDialog Created',
        detail: 'All embeddings have been successfully created.',
        life: 3000
      });
      isOpen.value = false;
      emit('embeddings-created', result);
    } else if (result.status === 'success') {
      // Reload status
      await loadEmbeddingStatus();
      emit('embeddings-created', result);
    } else {
      toast.add({
        severity: 'error',
        summary: 'Error',
        detail: 'An unknown error occurred while creating embeddings.',
        life: 5000
      });
    }
  } catch (err) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: 'An error occurred while creating embeddings.',
      life: 5000
    })
  } finally {
    isCreating.value = false;
  }
}

function cancel() {
  isOpen.value = false;
}
</script>

<template>
  <Dialog v-model:visible="isOpen" modal header="Create Embeddings" :style="{ width: '600px' }">
    <div v-if="isLoading" style="padding: 20px; text-align: center;">Loading status...</div>

    <div v-else-if="embeddingStatus">
      <div style="margin-bottom: 20px;">
        <h3>Current Status</h3>
        <div style="padding: 15px; background: #f8f9fa; border-radius: 4px; margin-top: 10px;">
          <div style="margin-bottom: 8px;">
            <!-- TODO: How does this relate to origin images? -->
            <strong>Embedded:</strong> {{ embeddingStatus.total_embeddings }} crops ({{ (embeddingStatus.total_embeddings/embeddingStatus.total_crops).toFixed(1) }}%)
          </div>
          <div style="margin-bottom: 8px;">
            <!-- TODO: What are origin images? -->
            <strong>Origin Images:</strong> {{ embeddingStatus.processed_origins }} / {{ embeddingStatus.total_origins }}
          </div>

          <ProgressBar
            :value="embeddingStatus.progress_percentage"
            :max="100"
            style="margin-top: 10px; height: 25px;"
            :showValue="true"
          />
        </div>
      </div>

      <div v-if="embeddingStatus.processed_origins < embeddingStatus.total_origins" style="margin: 20px 0; padding: 15px; background: #fff3cd; border-left: 4px solid #ffc107; border-radius: 4px;">
        <strong>⚠️ Confirmation Required</strong>
        <p style="margin: 10px 0 0 0;">
          This will create embeddings for the next origin image.
          The process may take some time depending on the number of crops.
        </p>
      </div>

      <div v-else style="margin: 20px 0; padding: 15px; background: #d4edda; border-left: 4px solid #28a745; border-radius: 4px;">
        <strong>✓ All Done!</strong>
        <p style="margin: 10px 0 0 0;">
          All embeddings have been created.
        </p>
      </div>

      <div v-if="embeddingStatus.processed_origins < embeddingStatus.total_origins" style="margin: 20px 0; padding: 15px; background: #e7f3ff; border: 1px solid #b3d9ff; border-radius: 4px;">
        <div style="display: flex; flex-direction: column; gap: 15px;">
          <div style="display: flex; align-items: center; gap: 10px;">
            <label for="processed_origins" style="font-weight: 500; min-width: 180px;">
              Amount of Images to Process:
            </label>
            <input
              type="number"
              id="processed_origins"
              v-model="processedOrigins"
              :disabled="processAll"
              min="1"
              style="padding: 8px 12px; border: 1px solid #ccc; border-radius: 4px; width: 100px; font-size: 14px;"
            />
          </div>

          <div style="display: flex; align-items: center; gap: 10px;">
            <input
              type="checkbox"
              id="process_all"
              v-model="processAll"
              style="width: 18px; height: 18px; cursor: pointer;"
            />
            <label for="process_all" style="font-weight: 500; cursor: pointer;">
               Create all remaining Embeddings ({{ embeddingStatus.total_origins - embeddingStatus.processed_origins }} Images)
            </label>
          </div>
        </div>
      </div>

      <div style="display: flex; justify-content: flex-end; gap: 10px; margin-top: 20px;">
        <Button
          @click="cancel"
          severity="secondary"
          :disabled="isCreating"
        >
          Cancel
        </Button>

        <Button
          v-if="embeddingStatus.processed_origins < embeddingStatus.total_origins"
          @click="createEmbeddings"
          :disabled="isCreating"
          :loading="isCreating"
        >
          {{ processAll ? 'Create All EmbeddingsDialog' : `${processedOrigins} Process Image(s)` }}
        </Button>
      </div>
    </div>
  </Dialog>
</template>

<style scoped>

</style>
