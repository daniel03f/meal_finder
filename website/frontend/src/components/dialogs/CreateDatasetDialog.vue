<script setup>
import { computed, ref } from "vue";
import { useDatasetStore } from "@/stores/dataset";
import { useToast } from "primevue/usetoast";

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible', 'dataset-created']);

const datasetStore = useDatasetStore();
const toast = useToast();

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

const outputPath = ref('');
const datasetType = ref('crops'); // 'crops' or 'whole_images'
const originalSplits = ref(true);
const isCreating = ref(false);

const datasetTypeOptions = [
  { label: 'Crops (Image Classification)', value: 'crops' },
  { label: 'Whole Images (Object Detection)', value: 'whole_images' }
];

async function createDataset() {
  if (!outputPath.value) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: 'Please specify an output path',
      life: 3000
    });
    return;
  }

  isCreating.value = true;

  try {
    let result;
    if (datasetType.value === 'crops') {
      result = await datasetStore.createCropDataset(outputPath.value, originalSplits.value);
    } else {
      result = await datasetStore.createObjectDetectionDataset(outputPath.value, originalSplits.value);
    }

    toast.add({
      severity: 'success',
      summary: 'Success',
      detail: 'Dataset created successfully',
      life: 3000
    });

    emit('dataset-created', result);
  } catch (error) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: 'Failed to create dataset: ' + error.message,
      life: 5000
    });
  } finally {
    isCreating.value = false;
  }
}
</script>

<template>
  <Dialog v-model:visible="isOpen" modal header="Create Dataset" class="w-2/3 max-w-2xl">
    <div class="flex flex-col gap-4">
      <!-- Output Path -->
      <div class="flex flex-col gap-2">
        <label for="output-path" class="font-semibold">Output Path</label>
        <InputText
          id="output-path"
          v-model="outputPath"
          placeholder="C:\path\to\output\folder"
          class="w-full"
        />
        <small class="text-gray-500">Specify the directory where the dataset will be saved</small>
      </div>

      <div class="flex flex-col gap-2">
        <label class="font-semibold">Dataset Type</label>
        <div class="flex flex-col gap-2">
          <div v-for="option in datasetTypeOptions" :key="option.value" class="flex items-center">
            <RadioButton
              v-model="datasetType"
              :inputId="option.value"
              :value="option.value"
            />
            <label :for="option.value" class="ml-2">{{ option.label }}</label>
          </div>
        </div>
        <small class="text-gray-500">
          <span v-if="datasetType === 'crops'">
            Creates a dataset with individual crops for image classification
          </span>
          <span v-else>
            Creates a dataset with whole images and bounding boxes for object detection
          </span>
        </small>
      </div>

      <div class="flex flex-col gap-2">
        <label class="font-semibold">Data Splits</label>
        <div class="flex items-center gap-2">
          <Checkbox
            v-model="originalSplits"
            inputId="original-splits"
            :binary="true"
          />
          <label for="original-splits">Use original dataset splits</label>
        </div>
        <small class="text-gray-500">
          <span v-if="originalSplits">
            Keeps the original train/test/val splits from the source dataset
          </span>
          <span v-else>
            Redistributes data: 70% train, 20% test, 10% validation
          </span>
        </small>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-end gap-2">
        <Button
          label="Cancel"
          severity="secondary"
          @click="isOpen = false"
          :disabled="isCreating"
        />
        <Button
          label="Create Dataset"
          @click="createDataset"
          :loading="isCreating"
        />
      </div>
    </template>
  </Dialog>
</template>

<style scoped>
</style>
