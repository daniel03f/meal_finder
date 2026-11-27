<script setup>
import { ref, watch, onMounted } from 'vue';
import { useCropStore } from '@/stores/crop';
import { useClassStore } from '@/stores/class';
import CropGrid from '@/components/CropGrid.vue';
import { useToast } from 'primevue/usetoast';

const props = defineProps({
  crop: {
    type: Object,
    required: true
  }
});

const emit = defineEmits(['crop-updated', 'close']);

const cropStore = useCropStore();
const classesStore = useClassStore();
const toast = useToast();

const similarCrops = ref([]);
const predictedClass = ref(null);
const compareClass = ref(null);

const confidence = ref(null);
const availableClasses = ref([]);
const selectedClass = ref('');
const isLoading = ref(false);
const errorMessage = ref('');

onMounted(async () => {
  await loadCropDetails();
  initializeSelectedClass();
});

watch(() => props.crop?.assigned_class, () => {
  initializeSelectedClass();
});

function initializeSelectedClass() {
  if (props.crop?.assigned_class) {
    selectedClass.value = props.crop.assigned_class;
  } else {
    selectedClass.value = '';
  }
}

async function loadCropDetails() {
  if (!props.crop) return;

  isLoading.value = true;
  errorMessage.value = '';

  similarCrops.value = [];
  predictedClass.value = null;
  confidence.value = null;

  try {
    availableClasses.value = await classesStore.fetchClasses();

    await loadSimilarCrops();
  } catch (err) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: `Error loading crop details: ${err.message}`,
      life: 5000
    });
  } finally {
    isLoading.value = false;
  }
}

async function loadSimilarCrops() {
  if (!props.crop) return;

  isLoading.value = true;
  errorMessage.value = '';

  try {
    const { inferResp, similarResp, inferData, similarData } = await cropStore.inferClass(props.crop.crop_path, 5, 0.8, compareClass.value);

    if (!inferResp.ok) {
      toast.add({
        severity: 'error',
        summary: 'Error',
        detail: `Failed to infer class: ${inferData.error || inferResp.statusText}`,
        life: 5000
      });
    } else {
      predictedClass.value = inferData.predicted_class;
      confidence.value = inferData.confidence;
    }

    if (!similarResp.ok) {
      toast.add({
        severity: 'warn',
        summary: 'Warning',
        detail: `Failed to load similar crops: ${similarData.error || similarResp.statusText}`,
        life: 3000
      });
      similarCrops.value = [];
    } else {
      similarCrops.value = Array.isArray(similarData.similar_crops) ? similarData.similar_crops : [];
    }
  } catch (err) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: `Error inferring similar crops: ${err.message}`,
      life: 5000
    });
  } finally {
    isLoading.value = false;
  }
}

async function  assignClass() {
  if (!selectedClass.value || !props.crop) return;

  isLoading.value = true;
  try {
    const result = await cropStore.assignCropToClass(props.crop.crop_path, selectedClass.value);

    if (result.success) {
      toast.add({
        severity: 'success',
        summary: 'Class Assigned',
        detail: `Crop ${props.crop.crop_file} assigned to class ${selectedClass.value}`,
        life: 3000
      });
      emit('crop-updated', { ...props.crop, assigned_class: selectedClass.value });
    } else {
      toast.add({
        severity: 'error',
        summary: 'Assignment Failed',
        detail: `Failed to assign crop ${props.crop.crop_file} to class ${selectedClass.value}`,
        life: 5000
      });
    }
  } finally {
    isLoading.value = false;
  }
}

async function acceptPrediction() {
  if (!predictedClass.value || !props.crop) return;

  selectedClass.value = predictedClass.value;
  await assignClass();
}

async function deleteCrop() {
  if (!props.crop) return;

  const confirmed = confirm(`Are you sure you want to delete crop ${props.crop.crop_file}? This action cannot be undone.`);
  if (!confirmed) return;

  try {
    const result = await cropStore.deleteCrop(props.crop.crop_path);

    if (result.success) {
      toast.add({
        severity: 'success',
        summary: 'Crop Deleted',
        detail: `Crop ${props.crop.crop_file} deleted successfully`,
        life: 3000
      });
      emit('close');
      emit('crop-updated', props.crop.crop_path);
    } else {
      toast.add({
        severity: 'error',
        summary: 'Delete Failed',
        detail: `Failed to delete crop ${props.crop.crop_file}`,
        life: 5000
      });
    }
  } catch (err) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: `Error deleting crop: ${err.message}`,
      life: 5000
    });
  }
}

function handleSimilarCropUpdated(updatedCrop) {
  const index = similarCrops.value.findIndex(c => c.crop_path === updatedCrop.crop_path);
  if (index !== -1) {
    similarCrops.value[index] = { ...similarCrops.value[index], assigned_class: updatedCrop.assigned_class };
  }
}
</script>

<template>
  <div>
    <div v-if="isLoading && !crop" class="p-40 text-center">
      <p>Loading...</p>
      <ProgressSpinner/>
    </div>

    <div v-else-if="crop">
      <div class="flex justify-center mb-5">
        <Image
          :src="`/api/crops/${crop.crop_path}`"
          :alt="crop.crop_file"
          width="150"
        />
      </div>

      <div class="flex justify-between items-left gap-5 mt-5">
        <Button @click="deleteCrop" severity="danger">
          Delete Crop
        </Button>

        <!-- TODO: This does not work when already assigned class -->
        <!-- TODO: Make option to create new class -->
        <Select
          v-model="selectedClass"
          @change="assignClass"
          :options="availableClasses"
          placeholder="Assign to Class"
          editable
        />
      </div>

      <h3 class="mt-8 mb-2 text-lg font-semibold">Similar Crops</h3>

      <div v-if="predictedClass" class="p-3 bg-gray-100 rounded mb-4 flex justify-between items-center">
        <div>
          <strong>Predicted Class:</strong> {{ predictedClass || 'None' }}<br>
          <strong>Confidence:</strong> {{ confidence !== null ? (confidence * 100).toFixed(2) + '%' : 'N/A' }}
        </div>
        <Button
          v-if="predictedClass && predictedClass !== 'No class' && !crop.assigned_class"
          @click="acceptPrediction"
          severity="success"
          :disabled="isLoading"
          label="Accept Prediction"
        />
      </div>

      <Select
        v-model="compareClass"
        @change="loadSimilarCrops"
        :options="availableClasses"
        placeholder="Compare with Class"
        class="mb-4 w-64"
      />

      <div v-if="isLoading" class="p-40 text-center">
        <p>Loading similar crops...</p>
        <ProgressSpinner/>
      </div>

      <Message v-else-if="similarCrops.length === 0" class="p-3 text-gray-600">
        No similar crops found.
      </Message>

      <CropGrid
        v-else
        :crops="similarCrops"
        :show-pagination="false"
        :show-similarity="true"
        @crop-updated="handleSimilarCropUpdated"
      />
    </div>
  </div>
</template>

<style scoped>

</style>
