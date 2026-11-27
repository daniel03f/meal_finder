<script setup>
import { ref, onMounted } from "vue";
import ClassesDialog from "@/components/dialogs/ClassesDialog.vue";
import ClustersDialog from "@/components/dialogs/ClustersDialog.vue";
import EmbeddingsDialog from "@/components/dialogs/EmbeddingsDialog.vue";
import CropGrid from "@/components/CropGrid.vue";
import UploadImagesDialog from "@/components/dialogs/UploadImagesDialog.vue";
import CreateDatasetDialog from "@/components/dialogs/CreateDatasetDialog.vue";
import ExportDatabaseDialog from "@/components/dialogs/ExportDatabaseDialog.vue";
import { useEmbeddingStore } from "@/stores/embedding";
import { useClassStore } from "@/stores/class";

const embeddingStore = useEmbeddingStore();
const classStore = useClassStore();

let showClasses = ref(false);
let showClusters = ref(false);
let showEmbeddings = ref(false);
let showUploadImages = ref(false);
let showCreateDataset = ref(false);
let showExportDatabase = ref(false);

let embeddingStatus = ref(null);
let assignedStatus = ref(null);

onMounted(async () => {
  await updateEmbeddingStatus();
  await updateAssignedStatus();
});

async function updateEmbeddingStatus() {
  try {
    embeddingStatus.value = await embeddingStore.fetchEmbeddingStatus();
  } catch (err) {
    console.error('Error loading embedding status:', err);
  }
}

async function updateAssignedStatus() {
  try {
    assignedStatus.value = await classStore.fetchAssignedStatus();
  } catch (err) {
    console.error('Error loading assigned status:', err);
  }
}

async function handleEmbeddingsCreated() {
  await updateEmbeddingStatus();
}

async function handleImagesUploaded() {
  await updateAssignedStatus();
}

</script>

<template>
  <div>
    <div class="pt-5 pl-5 ">
      <div class="gap-3 flex align-center flex-wrap">
        <Button @click="showClasses = true" severity="info" label="Show Classes"/>
        <Button @click="showClusters = true" severity="info" label="Show Clusters"/>
        <Button @click="showEmbeddings = true" label="Create Embeddings"/>
        <Button @click="showUploadImages = true" label="Upload Images"/>
        <Button @click="showCreateDataset = true" severity="contrast" label="Create Dataset"/>
        <Button @click="showExportDatabase = true" severity="contrast" label="Export Database"/>
      </div>

      <div  style="margin-left: auto; padding: 10px; background: #f8f9fa; border-radius: 4px; font-size: 14px;">
          <div v-if="embeddingStatus">
            <strong>Embedded:</strong> {{ embeddingStatus.total_embeddings }} crops ({{ (embeddingStatus.total_embeddings/embeddingStatus.total_crops).toFixed(1) }}%)
          </div>
        <div v-if="assignedStatus">
          <strong>Assigned:</strong> {{ assignedStatus.assigned_crops }} crops ({{  (assignedStatus.assigned_crops/assignedStatus.total_crops).toFixed(1) }}%)
        </div>
      </div>
    </div>

    <CropGrid
      :show-split-chooser="true"
    />

    <ClassesDialog
      :visible="showClasses"
      @update:visible="showClasses = $event"
    />
    <ClustersDialog
      :visible="showClusters"
      @update:visible="showClusters = $event"
    />
    <EmbeddingsDialog
      :visible="showEmbeddings"
      @update:visible="showEmbeddings = $event"
      @embeddings-created="handleEmbeddingsCreated"
    />
    <UploadImagesDialog
      :visible="showUploadImages"
      :images-uploaded="handleImagesUploaded"
      @update:visible="showUploadImages = $event"
    />
    <CreateDatasetDialog
      :visible="showCreateDataset"
      @update:visible="showCreateDataset = $event"
      />
    <ExportDatabaseDialog
      :visible="showExportDatabase"
      @update:visible="showExportDatabase = $event"
    />
  </div>
</template>

<style scoped>

</style>
