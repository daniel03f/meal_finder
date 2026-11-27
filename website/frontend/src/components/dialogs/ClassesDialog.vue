<script setup>
import { ref, watch, computed } from 'vue';
import { useClassStore } from '@/stores/class';
import CropGrid from '@/components/CropGrid.vue';
import { useToast } from 'primevue/usetoast';

const props = defineProps({
  visible: Boolean
});

const emit = defineEmits(['update:visible']);

const toast = useToast();

const classesStore = useClassStore();

const classes = ref([]);
const newClassName = ref('');
const renameClassName = ref('');

const searchQuery = ref('');
const selectedClass = ref(null);
const activeAccordion = ref(null);
const classCropsMap = ref({});
const classCropsLoadingMap = ref({});
const classCropsPage = ref(0);
const classCropsPageSize = ref(120);
const isLoading = ref(false);

const isOpen = computed({
  get: () => props.visible,
  set: (value) => emit('update:visible', value)
});

const filteredClasses = computed(() => {
  if (!searchQuery.value.trim()) {
    return classes.value;
  }
  const query = searchQuery.value.toLowerCase();
  return classes.value.filter(className =>
    className.toLowerCase().includes(query)
  );
});

watch(() => props.visible, async (newVal) => {
  if (newVal) {
    await loadClasses();
    selectedClass.value = null;
    activeAccordion.value = null;
    classCropsMap.value = {};
    classCropsLoadingMap.value = {};
    newClassName.value = '';
    renameClassName.value = '';
    searchQuery.value = '';
  }
});

watch(() => activeAccordion.value, () => {
  renameClassName.value = "";
});

async function loadClasses() {
  isLoading.value = true;
  try {
    classes.value = await classesStore.fetchClasses();
  } finally {
    isLoading.value = false;
  }
}

async function onAccordionChange(value) {
  activeAccordion.value = value;

  if (value && !classCropsMap.value[value]) {
    await loadClassCrops(value);
  }
}

async function loadClassCrops(className) {
  classCropsLoadingMap.value[className] = true;
  try {
    const data = await classesStore.fetchCropsByClass(className);
    classCropsMap.value[className] = {
      crops: data.crops,
      total: data.total || data.crops.length || 0
    };
  } finally {
    classCropsLoadingMap.value[className] = false;
  }
}

function handlePageChange() {
  loadClassCrops();
}

function handleCropUpdated(updatedCrop, className) {
  if (classCropsMap.value[className]) {
    const index = classCropsMap.value[className].crops.findIndex(
      c => c.crop_path === updatedCrop.crop_path
    );
    if (index !== -1) {
      classCropsMap.value[className].crops[index] = updatedCrop;
    }
  }
}


async function createClass() {
  if (!newClassName.value.trim()) return;

  isLoading.value = true;
  try {
    await classesStore.createClass(newClassName.value.trim());
    newClassName.value = '';
    toast.add({
      severity: 'success',
      summary: 'Class Created',
      detail: 'New class created successfully',
      life: 3000
    });
    await loadClasses();
  } catch (e) {
    toast.add({
      severity: 'error',
      summary: 'Creation Failed',
      detail: `Failed to create class: ${e.message}`,
      life: 5000
    });
  } finally {
    isLoading.value = false;
  }
}

async function renameClass(oldName, newName) {
  if (!newName.trim() || oldName === newName.trim()) {
    return;
  }

  isLoading.value = true;
  try {
    await classesStore.renameClass(oldName, newName.trim());

    // Update cache
    classCropsMap.value[newName.trim()] = classCropsMap.value[oldName];
    delete classCropsMap.value[oldName];

    classCropsLoadingMap.value[newName.trim()] = classCropsLoadingMap.value[oldName];
    delete classCropsLoadingMap.value[oldName];

    toast.add({
      severity: 'success',
      summary: 'Class Renamed',
      detail: `Class renamed to "${newName.trim()}" successfully`,
      life: 3000
    });
    await loadClasses();
  } catch (error) {
    toast.add({
      severity: 'error',
      summary: 'Rename Failed',
      detail: `Failed to rename class "${oldName}": ${error.message}`,
      life: 5000
    });
  } finally {
    isLoading.value = false;
  }
}


async function deleteClass(className) {
  const confirmed = confirm(`Are you sure you want to delete the class "${className}"? This action cannot be undone.`);
  if (!confirmed) return;

  isLoading.value = true;
  try {
    await classesStore.deleteClass(className);

    // Remove from cache
    delete classCropsMap.value[className];
    delete classCropsLoadingMap.value[className];

    toast.add({
      severity: 'success',
      summary: 'Class Deleted',
      detail: `Class "${className}" deleted successfully`,
      life: 3000
    });
    await loadClasses();
  } catch (error) {
    toast.add({
      severity: 'error',
      summary: 'Delete Failed',
      detail: `Failed to delete class "${className}": ${error.message}`,
      life: 5000
    });
  } finally {
    isLoading.value = false;
  }
}
</script>

<template>
  <Dialog
    v-model:visible="isOpen"
    modal header="Classes"
    class="w-4/5"
  >
    <div v-if="!selectedClass">
      <h3 class="mb-8">Manage your crop classes here.</h3>

      <div class="flex align-center mt-8 mb-10">
        <FloatLabel class="mr-4">
          <InputText
            v-model="newClassName"
            id="new-class-name"
            @keyup.enter="createClass"
          />
          <label for="new-class-name">New Class Name</label>
        </FloatLabel>

        <Button
          @click="createClass"
          :disabled="!newClassName.trim()"
          label="Create Class"
        />
      </div>

      <Divider/>

      <div v-if="isLoading" class="text-center p-40">
        <ProgressSpinner/>
        <p>Load Classes...</p>
      </div>

      <template v-else>
        <Message>
          Total Classes: {{ classes.length }}
        </Message>

        <div class="mb-4">
          <IconField>
            <InputIcon>
              <i class="pi pi-search" />
            </InputIcon>
            <InputText
              v-model="searchQuery"
              placeholder="Search classes..."
              class="w-full"
            />
          </IconField>
        </div>

        <Message v-if="classes.length === 0" style="padding: 20px; color: #666;">
          No classes found.
        </Message>

        <Message v-else-if="filteredClasses.length === 0" severity="info">
          No classes match your search.
        </Message>

        <Accordion v-else v-model:value="activeAccordion" @update:value="onAccordionChange">
          <AccordionPanel
            v-for="className in filteredClasses"
            :key="className"
            :value="className"
          >
            <AccordionHeader>
              <div class="flex w-full pr-2 justify-between">
                <span class="font-semibold text-lg">{{ className }}</span>

                <Button
                  severity="danger"
                  @click.stop="deleteClass(className)"
                  icon="pi pi-trash"
                  class=""
                />
              </div>
            </AccordionHeader>
            <AccordionContent>
              <div v-if="classCropsLoadingMap[className]" class="text-center p-40">
                <ProgressSpinner/>
                <p>Loading Crops...</p>
              </div>

              <div v-else-if="classCropsMap[className]">
                <div class="flex justify-between">
                  <Message class="">
                    Total Crops: {{ classCropsMap[className].total }}
                  </Message>

                  <FloatLabel>
                    <label for="rename-class-name">Rename Class</label>
                    <InputText
                      v-model="renameClassName"
                    />
                    <Button
                      icon="pi pi-check"
                      class="w-full h-full"
                      @click="renameClass(className, renameClassName)"
                    />
                  </FloatLabel>
                </div>

                <CropGrid
                  v-if="classCropsMap[className].crops.length > 0"
                  :crops="classCropsMap[className].crops"
                  :total-crops="classCropsMap[className].total"
                  :current-page="classCropsPage"
                  :page-size="classCropsPageSize"
                  @page-change="handlePageChange"
                  @crop-updated="(crop) => handleCropUpdated(crop, className)"
                />
                <Message v-else severity="info">
                  No crops assigned to this class.
                </Message>
              </div>
            </AccordionContent>
          </AccordionPanel>
        </Accordion>
      </template>
    </div>
  </Dialog>
</template>

<style scoped>

</style>
