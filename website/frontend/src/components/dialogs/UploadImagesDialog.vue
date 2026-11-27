<script setup>
import {useCropStore} from "@/stores/crop.js";
import {computed, ref} from "vue";
import {useToast} from "primevue/usetoast";

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible', 'images-uploaded']);

const cropStore = useCropStore();
const toast = useToast();

const isUploading = ref(false);

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

async function onUpload(event) {
  isUploading.value = true;
  try {
    const results = await cropStore.uploadCrops(event.files);

    const successCount = results.filter(r => r.success).length;
    const failCount = results.filter(r => !r.success).length;

    if (successCount > 0) {
      toast.add({
        severity: 'success',
        summary: 'Upload successful',
        detail: `${successCount} Image(s) uploaded successfully`,
        life: 3000
      });
    }

    if (failCount > 0) {
      toast.add({
        severity: 'error',
        summary: 'Upload failed',
        detail: `${failCount} Image(s) failed to upload`,
        life: 5000
      });
    }

    emit('images-uploaded');
  } catch (error) {
    console.error("Error uploading images:", error);
    toast.add({
      severity: 'error',
      summary: 'Upload Error',
      detail: 'An error occurred while uploading images.',
      life: 5000
    });
  } finally {
    isUploading.value = false;
  }
}


</script>

<template>
  <Dialog v-model:visible="isOpen" modal header="Upload Crops" :style="{ width: '400px' }">
    <!-- TODO: Make it optional to use object detection model to crop images on upload -->
    <FileUpload
      mode="basic"
      name="image"
      accept="image/*"
      :maxFileSize="10000000"
      @select="onUpload"
      :multiple="true"
      :auto="true"
      chooseLabel="Browse"
      :disabled="isUploading"
    />
      <div v-if="isUploading" style="margin-top: 1rem;">
        Uploading images...
      </div>
  </Dialog>
</template>

<style scoped>

</style>
