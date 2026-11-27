<script setup>
import { ref, onMounted, computed, watch } from "vue";
import { useCropStore } from "@/stores/crop";
import CropTabs from "@/components/CropTabs.vue";
import {useClassStore} from "@/stores/class.js"
import { useToast } from 'primevue/usetoast';

const cropStore = useCropStore();
const classStore = useClassStore();

const props = defineProps({
  crops: {
    type: Array,
    default: null
  },
  totalCrops: {
    type: Number,
    default: 0
  },
  currentPage: {
    type: Number,
    default: 0
  },
  pageSize: {
    type: Number,
    default: 120
  },
  showPagination: {
    type: Boolean,
    default: true
  },
  showSplitChooser: {
    type: Boolean,
    default: false
  },
  showAssignButton: {
    type: Function,
    default: null
  },
  onAssignCrop: {
    type: Function,
    default: null
  },
  showSimilarity: {
    type: Boolean,
    default: false
  },
  className: {
    type: String,
    default: null
  },
});

const emit = defineEmits(['crop-updated', 'page-change', 'show-crop-details']);

const toast = useToast();

const internalCrops = ref([]);
const internalCurrentPage = ref(0);
const selectedSplit = ref('all');

const internalPageSize = ref(120);
const internalTotalCrops = ref(0);
const isLoading = ref(false);
const showCropTabs = ref(false);
const openCrops = ref([]);

const splits = ref([
  { label: 'All Crops', value: 'all' },
  { label: 'Train', value: 'train' },
  { label: 'Validation', value: 'val' },
  { label: 'Test', value: 'test' },
  { label: 'Uploaded', value: 'uploaded' },
  { label: 'Unassigned', value: 'unassigned' },
  { label: 'Assigned', value: 'assigned' },
]);

const displayCrops = computed(() => {
  return props.crops !== null ? props.crops : internalCrops.value;
});

const displayTotal = computed(() => {
  return props.crops !== null ? props.totalCrops : internalTotalCrops.value;
});

const displayPageSize = computed(() => {
  return props.crops !== null ? props.pageSize : internalPageSize.value;
});

const displayCurrentPage = computed(() => {
  return props.crops !== null ? props.currentPage : internalCurrentPage.value;
});

onMounted(() => {
  if (props.crops === null) {
    loadCrops(0);
  }
});

watch(() => props.crops, (newCrops) => {
  if (newCrops !== null) {
    internalCrops.value = [];
  }
});

watch(selectedSplit, () => {
  if (props.crops === null) {
    loadCrops(0);
  }
});

async function loadCrops(page) {

  isLoading.value = true;
  try {
    let data;

    //  TODO This isn't necessary for clusters and classes views
    if (props.crops !== null) {
      return;
    }
    if (props.className) {
      data = await classStore.fetchCropsByClass(props.className);
    } else {
      data = await cropStore.fetchCrops(page, internalPageSize.value, selectedSplit.value);
    }

    internalCrops.value = data.crops || [];
    internalTotalCrops.value = data.total || 0;
    internalCurrentPage.value = data.page || page;
    internalPageSize.value = data.page_size || internalPageSize.value;
  } finally {
    isLoading.value = false;
  }
}

function showCropDetails(crop) {
  // Add to open tabs if not already opened
  const exists = openCrops.value.find(c => c.crop_path === crop.crop_path);
  if (!exists) {
    console.log('Pushing:', crop.crop_path, openCrops.value);
    openCrops.value.push(crop);
  } else {
    console.log('Crop already opened:', crop.crop_path);
  }
  showCropTabs.value = true;
}

function handleCropUpdated(updatedCrop) {
  // Update internal crops if using internal state
  if (props.crops === null) {
    const index = internalCrops.value.findIndex(c => c.crop_path === updatedCrop.crop_path);
    if (index !== -1) {
      internalCrops.value[index] = updatedCrop;
    }
  }

  // Update open Tabs
  const tabIndex = openCrops.value.findIndex(c => c.crop_path === updatedCrop.crop_path);
  if (tabIndex !== -1) {
    openCrops.value[tabIndex] = updatedCrop;
  }

  emit('crop-updated', updatedCrop);
}

function goToPage(page) {
  if (props.crops !== null) {
    emit('page-change', page);
  } else {
    loadCrops(page);
  }
}

function isAssigned(crop) {
  return !!crop.assigned_class;
}

function shouldShowAssign(crop) {
  return props.showAssignButton ? props.showAssignButton(crop) : false;
}

async function handleAssign(crop) {
  if (props.onAssignCrop) {
    await props.onAssignCrop(crop);
  }
}
</script>

<template>
  <div class="p-5">
    <div v-if="showSplitChooser" class="mb-4">
      <Select
        :options="splits"
        optionLabel="label"
        optionValue="value"
        v-model="selectedSplit"
        placeholder="Filter by split"
        class="w-64"
      />
    </div>

    <Paginator
      v-if="showPagination && displayTotal > displayPageSize"
      :template="'FirstPageLink PrevPageLink PageLinks NextPageLink LastPageLink JumpToPageDropdown'"
      :rows="displayPageSize"
      :total-records="displayTotal"
      :first="displayCurrentPage * displayPageSize"
      @page="(e) => goToPage(e.page)"
    />


     <div v-if="isLoading" class="p-20 text-center">
      <ProgressSpinner />
      <p>Loading crops....</p>
    </div>

    <div v-else-if="displayCrops.length === 0" class="p-20 text-center">
      No crops found.
    </div>

    <div v-else class="crop-grid grid">
      <div
        v-for="crop in displayCrops"
        :key="crop.crop_path"
        class="crop-item flex flex-col relative cursor-pointer"
        :class="{ assigned: isAssigned(crop) }"
        @click="showCropDetails(crop)"
      >
        <img
          :src="`/api/crops/${crop.crop_path}`"
          :alt="crop.crop_file"
          class="w-full h-44 object-cover rounded"
        />

        <div v-if="showSimilarity && crop.similarity !== undefined" class="sim-score">
          {{ (crop.similarity * 100).toFixed(1) }}%
        </div>

        <div class="mt-2 shrink-0">
          <div class="crop-filename">{{ crop.crop_file }}</div>
          <div v-if="crop.assigned_class" class="crop-class">{{ crop.assigned_class }}</div>
        </div>
        <!--TODO: Show Delete Button on the left-->

        <!-- TODO: This could also be a deselect button if already assigned -->
        <Button
          v-if="shouldShowAssign(crop)"
          @click.stop="handleAssign(crop)"
          class="assign-btn"
          icon="pi pi-check"
        />
      </div>
    </div>

    <CropTabs
      :visible="showCropTabs"
      :crops="openCrops"
      @update:visible="showCropTabs = $event"
      @crop-updated="handleCropUpdated"
    />
  </div>
</template>

<style scoped>
.crop-grid {
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 20px;
  padding: 20px 0;
}

.crop-item {
  border: 2px solid #e0e0e0;
  border-radius: 8px;
  padding: 10px;
  transition: all 0.2s;
  background: white;
}

.crop-item:hover {
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
  transform: translateY(-4px);
  border-color: #007bff;
}

.crop-filename {
  font-size: 11px;
  color: #666;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.crop-class {
  margin-top: 4px;
  padding: 4px 8px;
  background: #28a745;
  color: white;
  border-radius: 4px;
  font-size: 10px;
  font-weight: bold;
  text-align: center;
}

.crop-item.assigned {
  border-color: #28a745;
  background-color: #f0fff4;
}

.assign-btn {
  position: absolute;
  bottom: 12px;
  right: 12px;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: #007bff;
  color: white;
  border: none;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  transition: all 0.2s;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  z-index: 1;
}

.assign-btn:hover {
  background: #0056b3;
  transform: scale(1.1);
}

.sim-score {
  position: absolute;
  top: 12px;
  right: 12px;
  background: rgba(0, 123, 255, 0.9);
  color: white;
  padding: 4px 8px;
  border-radius: 4px;
  font-size: 11px;
  font-weight: bold;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
  z-index: 1;
}
</style>
