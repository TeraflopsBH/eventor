<script setup lang="ts">
import {computed,onMounted,ref} from "vue";
import {useI18n} from "vue-i18n";
import {api,ApiError,type BookingDisruptionNotice,type EventBookingLink,type EventDisruptionNotice} from "../../api";
import {formatApiError} from "../../i18n/api-errors";
import {formatDateTime} from "../../i18n/format";
const props=defineProps<{organizationId:string;eventId:string;eventTitle:string}>();
const {t,locale}=useI18n();
const heading=ref<HTMLElement|null>(null),busy=ref(false),error=ref(""),notice=ref("");
const receipts=ref<EventDisruptionNotice[]|null>(null),links=ref<EventBookingLink[]>([]),sources=ref<BookingDisruptionNotice[]>([]);
const receiptOffset=ref(0),nextReceipts=ref<number|null>(null),linkOffset=ref(0),nextLinks=ref<number|null>(null),sourceOffset=ref(0),nextSources=ref<number|null>(null);
const selectedBooking=ref(""),selectedSource=ref("");
const choices=computed(()=>links.value.filter(link=>link.bookingOwnerOrganizationId===props.organizationId && link.status==="active" && link.bookingCode));
const preview=computed(()=>sources.value.find(source=>source.noticeId===selectedSource.value));
function clearSource(){selectedSource.value="";sources.value=[];sourceOffset.value=0;nextSources.value=null;}
async function run(operation:()=>Promise<void>){
 if(busy.value)return;
 busy.value=true;error.value="";notice.value="";
 try{await operation();}catch(failure){
  if(failure instanceof ApiError && [401,403].includes(failure.status)){receipts.value=null;links.value=[];selectedBooking.value="";clearSource();}
  error.value=failure instanceof ApiError?formatApiError(failure,t):t("eventDisruptionInbox.failed");
 }finally{busy.value=false;}
}
async function loadReceipts(offset=0){const {data}=await api.listEventDisruptionNotices(props.eventId,offset);receipts.value=data.notices;receiptOffset.value=offset;nextReceipts.value=data.nextOffset;}
async function loadLinks(offset=0){const {data}=await api.listEventBookingLinks(props.eventId,offset);links.value=data.links;linkOffset.value=offset;nextLinks.value=data.nextOffset;selectedBooking.value="";clearSource();}
async function loadSources(offset=0){
 clearSource();if(!selectedBooking.value)return;
 const {data}=await api.getBookingDisruptionNotices(selectedBooking.value,offset);sources.value=data.notices;sourceOffset.value=offset;nextSources.value=data.nextOffset;
}
function reload(){void run(async()=>{
 const [inbox,associations]=await Promise.all([api.listEventDisruptionNotices(props.eventId,0),api.listEventBookingLinks(props.eventId,0)]);
 receipts.value=inbox.data.notices;receiptOffset.value=0;nextReceipts.value=inbox.data.nextOffset;
 links.value=associations.data.links;linkOffset.value=0;nextLinks.value=associations.data.nextOffset;selectedBooking.value="";clearSource();
});}
function publish(){
 const source=preview.value;
 if(!source || busy.value || !window.confirm(t("eventDisruptionInbox.confirm",{event:props.eventTitle})))return;
 void run(async()=>{
  await api.publishLocalEventDisruption(props.eventId,{bookingId:selectedBooking.value,sourceBookingNoticeId:source.noticeId});
  await loadReceipts();notice.value=t("eventDisruptionInbox.published");
 });
}
function acknowledge(receipt:EventDisruptionNotice){void run(async()=>{
 await api.acknowledgeEventDisruption(receipt.noticeId);await loadReceipts(receiptOffset.value);notice.value=t("eventDisruptionInbox.acknowledged");
});}
onMounted(()=>{heading.value?.focus();reload();});
</script>
<template>
 <section class="event-disruption-inbox" aria-labelledby="event-disruption-heading" :aria-busy="busy">
  <h3 id="event-disruption-heading" ref="heading" tabindex="-1">{{t("eventDisruptionInbox.title",{event:eventTitle})}}</h3>
  <p>{{t("eventDisruptionInbox.help")}}</p>
  <p v-if="error" role="alert" class="form-error">{{error}}</p><p v-if="notice" role="status">{{notice}}</p>
  <button type="button" class="button button-secondary" :disabled="busy" @click="reload">{{t("eventDisruptionInbox.reload")}}</button>
  <template v-if="receipts">
   <p v-if="!receipts.length">{{t("eventDisruptionInbox.empty")}}</p>
   <ul v-else class="receipt-list" :aria-label="t('eventDisruptionInbox.receipts')">
    <li v-for="receipt in receipts" :key="receipt.noticeId" class="receipt">
     <h4>{{receipt.sourceNotice?.noticeCode??t("eventDisruptionInbox.legacy")}}</h4>
     <p>{{t(`eventDisruptionInbox.statuses.${receipt.status}`)}}</p>
     <p v-if="receipt.sourceNotice" class="public-summary">{{receipt.sourceNotice.publicSummary}}</p>
     <p v-if="receipt.sourceNotice?.affectedFrom">{{t("eventDisruptionInbox.from")}}: {{formatDateTime(receipt.sourceNotice.affectedFrom,locale)}}</p>
     <p v-if="receipt.sourceNotice?.affectedUntil">{{t("eventDisruptionInbox.until")}}: {{formatDateTime(receipt.sourceNotice.affectedUntil,locale)}}</p>
     <p>{{t("eventDisruptionInbox.receivedAt")}}: {{formatDateTime(receipt.createdAt,locale)}}</p>
     <p v-if="receipt.acknowledgedAt">{{t("eventDisruptionInbox.acknowledgedAt")}}: {{formatDateTime(receipt.acknowledgedAt,locale)}}</p>
     <button v-if="receipt.status==='received'" type="button" class="button button-secondary" :disabled="busy" @click="acknowledge(receipt)">{{t("eventDisruptionInbox.acknowledge")}}</button>
    </li>
   </ul>
   <div v-if="receiptOffset || nextReceipts!==null" class="toolbar">
    <button type="button" class="button button-secondary" :disabled="busy || receiptOffset===0" @click="run(()=>loadReceipts(Math.max(0,receiptOffset-50)))">{{t("registry.previous")}}</button>
    <button type="button" class="button button-secondary" :disabled="busy || nextReceipts===null" @click="run(()=>loadReceipts(nextReceipts??0))">{{t("registry.next")}}</button>
   </div>
   <h4>{{t("eventDisruptionInbox.publishTitle")}}</h4><p>{{t("eventDisruptionInbox.publishHelp")}}</p>
   <p v-if="!choices.length">{{t("eventDisruptionInbox.noBookings")}}</p>
   <template v-else>
    <label for="notice-booking">{{t("eventDisruptionInbox.booking")}}</label>
    <select id="notice-booking" v-model="selectedBooking" :disabled="busy" @change="run(()=>loadSources())"><option value="">{{t("eventDisruptionInbox.chooseBooking")}}</option><option v-for="link in choices" :key="link.linkId" :value="link.bookingId">{{link.bookingCode}}</option></select>
   </template>
   <div v-if="linkOffset || nextLinks!==null" class="toolbar">
    <button type="button" class="button button-secondary" :disabled="busy || linkOffset===0" @click="run(()=>loadLinks(Math.max(0,linkOffset-50)))">{{t("eventDisruptionInbox.previousBookings")}}</button>
    <button type="button" class="button button-secondary" :disabled="busy || nextLinks===null" @click="run(()=>loadLinks(nextLinks??0))">{{t("eventDisruptionInbox.nextBookings")}}</button>
   </div>
   <template v-if="selectedBooking">
    <p v-if="!sources.length && !busy">{{t("eventDisruptionInbox.noNotices")}}</p>
    <form v-if="sources.length" @submit.prevent="publish">
     <label for="notice-source">{{t("eventDisruptionInbox.source")}}</label><select id="notice-source" v-model="selectedSource" :disabled="busy" required><option value="" disabled>{{t("eventDisruptionInbox.chooseSource")}}</option><option v-for="source in sources" :key="source.noticeId" :value="source.noticeId">{{formatDateTime(source.issuedAt,locale)}} · {{source.publicSummary.length>100?`${source.publicSummary.slice(0,100)}…`:source.publicSummary}}</option></select>
     <div v-if="preview" class="source-preview"><h4>{{t("eventDisruptionInbox.preview")}}</h4><p class="public-summary">{{preview.publicSummary}}</p><p>{{t("eventDisruptionInbox.issuedAt")}}: {{formatDateTime(preview.issuedAt,locale)}}</p><p v-if="preview.affectedFrom">{{t("eventDisruptionInbox.from")}}: {{formatDateTime(preview.affectedFrom,locale)}}</p><p v-if="preview.affectedUntil">{{t("eventDisruptionInbox.until")}}: {{formatDateTime(preview.affectedUntil,locale)}}</p></div>
     <button type="submit" class="button button-primary" :disabled="busy || !preview">{{t("eventDisruptionInbox.publish")}}</button>
    </form>
    <div v-if="sourceOffset || nextSources!==null" class="toolbar">
     <button type="button" class="button button-secondary" :disabled="busy || sourceOffset===0" @click="run(()=>loadSources(Math.max(0,sourceOffset-50)))">{{t("eventDisruptionInbox.previousNotices")}}</button>
     <button type="button" class="button button-secondary" :disabled="busy || nextSources===null" @click="run(()=>loadSources(nextSources??0))">{{t("eventDisruptionInbox.nextNotices")}}</button>
    </div>
   </template>
  </template>
 </section>
</template>
<style scoped>
.event-disruption-inbox {display:grid;grid-template-columns:minmax(0,1fr);gap:.75rem;min-width:0;border:1px solid var(--border);border-radius:11px;padding:1rem;overflow-wrap:anywhere;}
.receipt-list {list-style:none;margin:0;padding:0;display:grid;gap:.75rem;}
.receipt,.source-preview {padding:1rem;border:1px solid var(--border);border-radius:9px;min-width:0;}
.public-summary {white-space:pre-wrap;}
form {display:grid;gap:.75rem;min-width:0;}
select {max-width:100%;min-width:0;}
.toolbar {display:flex;flex-wrap:wrap;gap:.6rem;}
h3:focus {outline:2px solid var(--accent);outline-offset:3px;}
</style>
