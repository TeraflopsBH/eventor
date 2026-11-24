<script setup lang="ts">
import {computed,onMounted,ref} from "vue";
import {useI18n} from "vue-i18n";
import {api,ApiError,type RegistryPersonLabels,type RegistryLabel} from "../../api";
import {formatApiError} from "../../i18n/api-errors";
const props=defineProps<{organizationId:string;personId:string}>();
const emit=defineEmits<{changed:[]}>();
const {t}=useI18n();const directory=ref<RegistryPersonLabels|null>(null);const selected=ref<string[]>([]);
const name=ref("");const busy=ref(false);const error=ref("");const notice=ref("");
const changed=computed(()=>!!directory.value&&(selected.value.length!==directory.value.assignedLabelIds.length||selected.value.some(id=>!directory.value?.assignedLabelIds.includes(id))));
async function run(operation:()=>Promise<void>) {
 busy.value=true;error.value="";notice.value="";
 try {await operation();} catch(failure) {
  if(failure instanceof ApiError&&[401,403].includes(failure.status)){directory.value=null;selected.value=[];name.value="";}
  error.value=failure instanceof ApiError?formatApiError(failure,t):t("registry.failed");
 } finally{busy.value=false;}
}
async function load(){directory.value=(await api.getRegistryPersonLabels(props.personId)).data;selected.value=[...directory.value.assignedLabelIds];}
function create(){if(!name.value.trim())return;void run(async()=>{const label=(await api.createRegistryLabel(props.organizationId,name.value.trim())).data;directory.value?.labels.push(label);name.value="";});}
function save(){const current=directory.value;if(!current?.canManage||!changed.value)return;void run(async()=>{await api.setRegistryPersonLabels(props.personId,current.revision,selected.value);await load();notice.value=t("registry.labels.saved");emit("changed");});}
function retire(label:RegistryLabel){if(!window.confirm(t("registry.labels.confirmRetire",{label:label.label})))return;void run(async()=>{const retired=(await api.retireRegistryLabel(props.organizationId,label.labelId)).data;Object.assign(label,retired);});}
onMounted(()=>run(load));
</script>
<template>
<section aria-labelledby="registry-labels-heading">
 <h4 id="registry-labels-heading">{{t("registry.labels.title")}}</h4>
 <p class="fine-print">{{t("registry.labels.help")}}</p>
 <p v-if="error" role="alert" class="form-error">{{error}}</p><p v-if="notice" role="status">{{notice}}</p>
 <template v-if="directory">
  <p v-if="!directory.labels.length">{{t("registry.labels.empty")}}</p>
  <ul><li v-for="label in directory.labels" :key="label.labelId">
   <label><input v-model="selected" :value="label.labelId" type="checkbox" :disabled="busy||!directory.canManage||(label.retired&&!directory.assignedLabelIds.includes(label.labelId))">{{label.label}}<span v-if="label.retired"> ({{t("registry.labels.retired")}})</span></label>
   <button v-if="directory.canManage&&!label.retired" class="button button-quiet" type="button" :disabled="busy" :aria-label="t('registry.labels.retireNamed',{label:label.label})" @click="retire(label)">{{t("registry.labels.retire")}}</button>
  </li></ul>
  <button v-if="directory.canManage" class="button button-primary" type="button" :disabled="busy||!changed" @click="save">{{t("registry.labels.save")}}</button>
  <form v-if="directory.canManage" @submit.prevent="create">
   <label>{{t("registry.labels.newLabel")}}<input v-model="name" maxlength="80" required :disabled="busy"></label>
   <button class="button button-secondary" type="submit" :disabled="busy||!name.trim()">{{t("registry.labels.create")}}</button>
  </form>
 </template>
</section>
</template>
