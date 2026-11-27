<script setup>
import {nextTick, ref, watch} from 'vue';

const props = defineProps({
  plotData: {
    type: Object,
    default: null
  },
  loading: {
    type: Boolean,
    default: false
  }
});

const chartData = ref(null);
const chartOptions = ref(null);

watch(() => props.plotData, async (newData) => {
  if (newData) {
    await nextTick();
    prepareChartData();
  }
}, { immediate: true });

function prepareChartData() {
  if (!props.plotData) return;

  const data = props.plotData.plot_data;
  const uniqueClusters = [...new Set(data.map(d => d.cluster_id))];
  const colors = generateColors(uniqueClusters.length);

  // Group data by cluster
  const datasets = uniqueClusters.map(clusterId => {
    const clusterPoints = data.filter(d => d.cluster_id === clusterId);

    return {
      label: clusterId === -1 ? 'Noise' : `Cluster ${clusterId}`,
      data: clusterPoints.map(p => ({
        x: p.x,
        y: p.y,
        crop_path: p.crop_path,
        assigned_class: p.assigned_class,
        cluster_id: p.cluster_id
      })),
      backgroundColor: colors[uniqueClusters.indexOf(clusterId)],
      borderColor: colors[uniqueClusters.indexOf(clusterId)],
      pointRadius: 5,
      pointHoverRadius: 8,
    };
  });

  chartData.value = { datasets };

  chartOptions.value = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      title: {
        display: true,
        text: `Cluster Visualization (${props.plotData.n_clusters} Clusters, ${props.plotData.n_noise} Noise Points)`,
        font: { size: 16 }
      },
      legend: {
        display: true,
        position: 'right'
      },
      tooltip: {
        callbacks: {
          label: function(context) {
            const point = context.raw;
            return [
              `Cluster: ${point.cluster_id}`,
              `Position: (${point.x.toFixed(2)}, ${point.y.toFixed(2)})`,
              point.assigned_class ? `Class: ${point.assigned_class}` : 'No class assigned',
              `Crop Path: ${point.crop_path}`
            ];
          }
        }
      }
    },
    scales: {
      x: {
        type: 'linear',
        position: 'bottom',
        title: {
          display: true,
          text: 'UMAP Dimension 1'
        }
      },
      y: {
        type: 'linear',
        title: {
          display: true,
          text: 'UMAP Dimension 2'
        }
      }
    }
  };
}

function generateColors(count) {
  const colors = [];
  const baseColors = [
    'rgba(255, 99, 132, 0.6)',
    'rgba(54, 162, 235, 0.6)',
    'rgba(255, 206, 86, 0.6)',
    'rgba(75, 192, 192, 0.6)',
    'rgba(153, 102, 255, 0.6)',
    'rgba(255, 159, 64, 0.6)',
    'rgba(199, 199, 199, 0.6)',
    'rgba(83, 102, 255, 0.6)',
    'rgba(255, 99, 255, 0.6)',
    'rgba(99, 255, 132, 0.6)',
  ];


  for (let i = 1; i < count; i++) {
    if (i < baseColors.length) {
      colors.push(baseColors[i]);
    } else {
      // Generate random colors for additional clusters
      const hue = (i * 137.5) % 360;
      colors.push(`hsla(${hue}, 70%, 60%, 0.6)`);
    }
  }

  return colors;
}
</script>

<template>
  <div class="scatter-plot-container">
    <div v-if="loading" class="loading-container">
      <ProgressSpinner />
      <p>Loading plot data...</p>
    </div>

    <!-- TODO: Prevent overflow of cluster legend -->
    <div v-else-if="chartData" class="w-full h-full overflow-auto">
      <Chart
        type="scatter"
        :data="chartData"
        :options="chartOptions"
        class="w-full h-full overflow-auto"
      />
    </div>

    <div v-else class="items-center justify-center h-full">
      <Message>No plot data available</Message>
    </div>
  </div>
</template>

<style scoped>
.scatter-plot-container {
  height: 600px;
  position: relative;
}

.loading-container {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  height: 100%;
  padding: 20px;
}
</style>
