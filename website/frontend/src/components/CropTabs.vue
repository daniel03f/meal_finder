<script setup>
import { ref, watch } from 'vue';
import CropTabContent from './CropTabContent.vue';

// TODO: The open tabs should be managed in a store to persist across component unmounts
const props = defineProps({
  visible: Boolean,
  crops: {
    type: Array,
    default: () => []
  }
});

const emit = defineEmits(['update:visible', 'crop-updated']);

const activeTab = ref(0);
const localCrops = ref([]);

watch(() => props.crops, (newCrops) => {
  localCrops.value = newCrops.map(crop => ({
    ...crop,
    id: crop.crop_path
  }));

  if (localCrops.value.length > 0) {
    activeTab.value = localCrops.value.length - 1;
  }
}, { immediate: true, deep: true });

const isOpen = ref(false);

watch(() => props.visible, (newVal) => {
  isOpen.value = newVal;
});

watch(isOpen, (newVal) => {
  emit('update:visible', newVal);
  if (!newVal) {
    setTimeout(() => {
      localCrops.value = [];
    }, 300);
  }
});

function closeTab(index) {
  localCrops.value.splice(index, 1);

  if (activeTab.value >= localCrops.value.length) {
    activeTab.value = Math.max(0, localCrops.value.length - 1);
  }

  // Close dialog if no tabs left
  if (localCrops.value.length === 0) {
    isOpen.value = false;
  }
}

function handleCropUpdated(updatedCrop) {
  emit('crop-updated', updatedCrop);
}
</script>

<template>
  <Dialog
    v-model:visible="isOpen"
    modal
    header="Crop Details"
    class="w-5/6 max-w-7xl"
    :dismissable-mask="true"
  >
    <TabView v-if="localCrops.length > 0" v-model:active-index="activeTab">
      <TabPanel
        v-for="(crop, index) in localCrops"
        :key="crop.id"
      >
        <template #header>
          <div class="flex items-center gap-2">
            <span>{{ crop.crop_file }}</span>
            <Button
              icon="pi pi-times"
              text
              rounded
              severity="secondary"
              size="small"
              @click.stop="closeTab(index)"
              class="w-5 h-5"
            />
          </div>
        </template>

        <CropTabContent
          :crop="crop"
          @crop-updated="handleCropUpdated"
          @close="closeTab(index)"
        />
      </TabPanel>
    </TabView>
  </Dialog>
</template>

<style scoped>

</style>
