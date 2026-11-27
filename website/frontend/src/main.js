import { createApp } from 'vue';
import { createPinia } from 'pinia';
import './assets/style.css';
import App from './App.vue';
import router from './router';
import PrimeVue from 'primevue/config';
import Aura from '@primeuix/themes/aura';
import ToastService from "primevue/toastservice";
import DialogService from 'primevue/dialogservice';

const app = createApp(App)
app.use(ToastService)
app.use(createPinia())
app.use(router)
app.use(PrimeVue,{
  theme: {
    preset: Aura,
  },
});


app.mount('#app')
