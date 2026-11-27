<script setup>
import {computed, nextTick, ref, watch} from 'vue';
import CropGrid from '@/components/CropGrid.vue';
import ScatterPlot from '@/components/ScatterPlot.vue';
import {useClusterStore} from '@/stores/cluster';
import {useClassStore} from '@/stores/class';
import { useToast } from 'primevue/usetoast';

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible']);

const clusterStore = useClusterStore();
const classesStore = useClassStore();

const toast = useToast();

const clusterData = ref(null);
const clusterAssignments = ref({});
const availableClasses = ref([]);
const newClassNames = ref({});
const isLoading = ref(false);
  const clusterPages = ref({});

const minClusterSize = ref(3);
const minSamples = ref(1);
const pageSize = ref(500);
const currentPage = ref(0);
const clusterPageSize = ref(20);

const diagramVisible = ref(false);

const selectedSplit = ref('all');

const splits = ref([
  { label: 'All Crops', value: 'all' },
  { label: 'Train', value: 'train' },
  { label: 'Validation', value: 'val' },
  { label: 'Test', value: 'test' },
  { label: 'Uploaded', value: 'uploaded' },
  { label: 'Unassigned', value: 'unassigned' },
  { label: 'Assigned', value: 'assigned' },
]);

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

const displayTotal = computed(() => {
  return clusterData.value ? clusterData.value.total : 0;
});

watch(() => props.visible, async (newVal) => {
  if (newVal) {
    await loadClusters(currentPage.value);
  } else {
    diagramVisible.value = false;
  }
});

watch([minClusterSize, minSamples, currentPage, pageSize, selectedSplit], async () => {
  if (isOpen.value) {
    await loadClusters(currentPage.value);
  }
});

async function loadClusters(page) {
  isLoading.value = true;
  try {
    currentPage.value = page;
    const data = await clusterStore.fetchClusters(
      minClusterSize.value,
      minSamples.value,
      currentPage.value,
      pageSize.value,
      selectedSplit.value
    );

    if (!data.clusters || data.clusters.length === 0) {
      toast.add({
        severity: 'warn',
        summary: 'No clusters found',
        detail: data.message || 'No clusters were found with the current parameters.',
        life: 5000
      });
      clusterData.value =  [];
      return;
    }

    clusterData.value = data;
    clusterAssignments.value = {};
    newClassNames.value = {};
    clusterPages.value = {};

    availableClasses.value = await classesStore.fetchClasses();

    preselectMajorityClasses();
  } finally {
    isLoading.value = false;
  }
}

function preselectMajorityClasses() {
  if (!clusterData.value) return;

  clusterData.value.clusters.forEach(cluster => {
    const classVotes = {};
    let unassignedCount = 0;

    // Count class assignments
    cluster.samples.forEach(sample => {
      if (sample.assigned_class) {
        classVotes[sample.assigned_class] = (classVotes[sample.assigned_class] || 0) + 1;
      } else {
        unassignedCount++;
      }
    });

    // Check if there's a clear majority
    const classes = Object.keys(classVotes);

    if (classes.length === 1) {
      if (classVotes[classes[0]] > unassignedCount) {
        clusterAssignments.value[cluster.cluster_id] = classes[0];
      }
    }
  });
}

async function createClassForCluster(clusterId) {
  const className = newClassNames.value[clusterId]?.trim();

  if (!className) {
    toast.add({
      severity: 'warn',
      summary: 'Class Name Required',
      detail: 'Please enter a class name',
      life: 3000
    });
    return;
  }

  try {
    const response = await classesStore.createClass(className);
    const result = await response.json();

    if (result.success) {
      toast.add({
        severity: 'success',
        summary: 'Class Created',
        detail: `Class "${className}" created successfully!`,
        life: 3000
      });
      newClassNames.value[clusterId] = '';

      // Update available classes
      availableClasses.value = await classesStore.fetchClasses();

      // Auto-select the new class
      clusterAssignments.value[clusterId] = className;
    } else {
      toast.add({
        severity: 'error',
        summary: 'Error',
        detail: result.error || 'Failed to create class',
        life: 5000
      });
    }
  } catch (error) {
    toast.add({
      severity: 'error',
      summary: 'Error',
      detail: 'Failed to create class',
      life: 5000
    });
  }
}

function selectClassForCluster(clusterId, className) {
  clusterAssignments.value[clusterId] = className;
}

async function assignSingleCrop(cropPath, clusterId) {
  const className = clusterAssignments.value[clusterId];

  if (!className) {
    toast.add({
      severity: 'warn',
      summary: 'Class Not Selected',
      detail: 'Please select a class first',
      life: 3000
    });
    return;
  }

  try {
    const result = await classesStore.assignCropToClass(cropPath, className);
    if (result.success) {
      // Update the crop in the cluster data
      const cluster = clusterData.value.clusters.find(c => c.cluster_id === clusterId);
      if (cluster) {
        const sample = cluster.samples.find(s => s.crop_path === cropPath);
        if (sample) {
          sample.assigned_class = className;
          toast.add({
            severity: 'success',
            summary: 'Crop Assigned',
            detail: `Crop assigned to class ${className} successfully!`,
            life: 2000
          });
        }
      }
    } else {
      toast.add({
        severity: 'error',
        summary: 'Assignment Failed',
        detail: `Failed to assign crop to class ${className}`,
        life: 5000
      });
    }
  } catch (error) {
    toast.add({
        severity: 'error',
        summary: 'Assignment Failed',
        detail: `Failed to assign crop to class ${className}`,
        life: 5000
      });
  }
}

function isAssigned(sample) {
  return !!sample.assigned_class;
}

function shouldShowAssignButton(sample, clusterId) {
  return !isAssigned(sample) && clusterAssignments.value[clusterId];
}

function handleAssignCrop(clusterId) {
  return async (crop) => {
    await assignSingleCrop(crop.crop_path, clusterId);
  };
}

function handleCropUpdated(updatedCrop, clusterId) {
  const cluster = clusterData.value.clusters.find(c => c.cluster_id === clusterId);
  if (cluster) {
    const sample = cluster.samples.find(s => s.crop_path === updatedCrop.crop_path);
    if (sample) {
      sample.assigned_class = updatedCrop.assigned_class;
    }
  }
}

function handleClusterPageChange(clusterId, page) {
  clusterPages.value[clusterId] = page;
}

function getClusterCrops(cluster) {
  const page = clusterPages.value[cluster.cluster_id] || 0;
  const offset = page * clusterPageSize.value;
  return cluster.samples.slice(offset, offset + clusterPageSize.value);
}

async function showDiagram() {
  diagramVisible.value = true;
}

function closeDiagram() {
  diagramVisible.value = false;
}
</script>

<template>
  <Dialog
    v-model:visible="isOpen"
    modal header="Clustering Results"
    class="w-4/5"
  >
    <!-- TODO: Do this in pairs of two per row -->
    <div class="param-group w-full flex flex-wrap items-start  gap-5 mb-5 ">
      <div class="w-full flex flex-col">
        <label for="minClusters">Minimal Amount of Crops per Cluster</label>
        <InputNumber
          id="minClusters"
          class="w-full"
          v-model="minClusterSize"
          :min="2"
          :max="50"
          showButtons
          placeholder="Recommended is 2-10"
        />
      </div>

      <div class="w-full flex flex-col">
        <label for="minSamples">Cluster Conservativeness</label>
        <InputNumber
          id="minSamples"
          class="w-full"
          v-model="minSamples"
          :min="1"
          :max="20"
          showButtons
          placeholder="Recommended is 1-3"
        />
      </div>

       <div class="w-full flex flex-col">
        <label for="pageSize">Amount of points to cluster</label>
        <InputNumber
          class="w-full"
          id="pageSize"
          v-model="pageSize"
          :min="100"
          :max="1000"
          :step="100"
          showButtons
        />
      </div>

      <div class="w-full flex flex-col mb-5">
        <label for="splitSelect">Filter by Split</label>
        <Select
          id="splitSelect"
          :options="splits"
          optionLabel="label"
          optionValue="value"
          v-model="selectedSplit"
          placeholder="Select split"
          class="w-full"
        />
      </div>

      <!-- TODO: Do this below-->
      <div class="flex w-full align-center gap-3 p-3" v-if="clusterData && !isLoading">
        <Paginator
          v-if="displayTotal > pageSize"
          class="w-full"
          :template="'FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink JumpToPageDropdown'"
          :rows="pageSize"
          :total-records="displayTotal"
          :disabled="isLoading"
          :first="currentPage * pageSize"
          @page="(e) => loadClusters(e.page)"
      />
        <div class="items-end ml-auto">
          <Button
            v-if="!diagramVisible"
            @click="showDiagram"
            severity="info"
            label="Show Cluster Diagram"
          />
          <Button
            v-else
            @click="closeDiagram"
            severity="info"
            label="Show Cluster Grid"
          />
        </div>
      </div>
    </div>

    <Divider/>

    <div v-if="isLoading" class="text-center p-40">
      <ProgressSpinner/>
      <p>Load Clusters...</p>
    </div>

    <div v-else-if="clusterData && !diagramVisible">
      <div class="mb-5 flex justify-between align-center">
        <Message v-if="clusterData.clusters.length === 0" severity="warn">
          {{ clusterData.message || 'No cluster found.' }}
        </Message>
      </div>

      <div
        v-for="cluster in clusterData.clusters"
        :key="cluster.cluster_id"
        class="mb-5 pb-5"
      >
        <div class="flex flex-wrap justify-between items-center gap-5 mb-5">
          <h3>
            Cluster {{ cluster.cluster_id }}:
            <span v-if="cluster.cluster_id===-1"> Noise,</span>
            {{ cluster.size }} items
          </h3>
          <div class="flex flex-wrap gap-5 align-center">
            <FloatLabel>
              <InputText
                v-model="newClassNames[cluster.cluster_id]"
                @keyup.enter="createClassForCluster(cluster.cluster_id)"
              />
              <label>New Class Name</label>
            </FloatLabel>

            <Button
              @click="createClassForCluster(cluster.cluster_id)"
              :disabled="!newClassNames[cluster.cluster_id]?.trim()"
              label="Create Class"
            />
            <!-- TODO: Combine the input and select into one with option to create new class -->
            <!-- TODO: There needs to auto completion for existing class names -->

            <Select
              v-model="clusterAssignments[cluster.cluster_id]"
              @change="selectClassForCluster(cluster.cluster_id, $event.target.value)"
              placeholder="Select existing class..."
              :options="availableClasses"
              editable
            />
          </div>
        </div>

        <Divider/>

        <CropGrid
          :crops="getClusterCrops(cluster)"
          :show-pagination="true"
          :total-crops="cluster.samples.length"
          :page-size="clusterPageSize"
          :current-page="clusterPages[cluster.cluster_id] || 0"
          :show-assign-button="(crop) => shouldShowAssignButton(crop, cluster.cluster_id)"
          :on-assign-crop="handleAssignCrop(cluster.cluster_id)"
          @crop-updated="(crop) => handleCropUpdated(crop, cluster.cluster_id)"
          @page-change="(page) => handleClusterPageChange(cluster.cluster_id, page)"
        />
      </div>
    </div>

    <div v-else-if="diagramVisible">
      <div class="flex items-center mb-4 justify-between">
        <h3>Cluster Visualization</h3>
      </div>

      <ScatterPlot
        class="h-3/4 relative"
        :plot-data="clusterData"
        :loading="isLoading"
      />
    </div>
  </Dialog>
</template>

<style scoped>
</style>

