<script setup lang="ts">
import {onMounted,ref} from "vue";
import {useI18n} from "vue-i18n";
import {api,ApiError,type DisruptionBooking,type EventBookingLink} from "../../api";
import {formatApiError} from "../../i18n/api-errors";
import {formatDateTime} from "../../i18n/format";
const props=defineProps<{organizationId:string;eventId:string;eventTitle:string}>();
const {t,locale}=useI18n();
const links=ref<EventBookingLink[]|null>(null),bookings=ref<DisruptionBooking[]>([]);
const nextLinks=ref<number|null>(null),nextBookings=ref<number|null>(null),linksOffset=ref(0),bookingOffset=ref(0);
const query=ref(""),appliedQuery=ref(""),selected=ref("");
const kind=ref<EventBookingLink["relationshipKind"]>("venue_for_event");
const kinds:EventBookingLink["relationshipKind"][]=["venue_for_event","service_for_event","other"];
const busy=ref(false),error=ref(""),notice=ref("");
async function run(operation:()=>Promise<void>){
 if(busy.value)return;
 busy.value=true;error.value="";notice.value="";
 try{await operation();}
 catch(failure){
  if(failure instanceof ApiError && [401,403].includes(failure.status)){links.value=null;bookings.value=[];selected.value="";}
  error.value=failure instanceof ApiError?formatApiError(failure,t):t("eventBookingLinks.failed");
 }finally{busy.value=false;}
}
async function loadLinks(offset=0){const {data}=await api.listEventBookingLinks(props.eventId,offset);links.value=data.links;nextLinks.value=data.nextOffset;linksOffset.value=offset;}
async function findBookings(offset=0){const {data}=await api.searchBookingReferences(props.organizationId,appliedQuery.value,offset);bookings.value=data.bookings;nextBookings.value=data.nextOffset;bookingOffset.value=offset;selected.value="";}
function reload(){void run(async()=>{
 const [current,available]=await Promise.all([api.listEventBookingLinks(props.eventId,0),api.searchBookingReferences(props.organizationId,appliedQuery.value,0)]);
 links.value=current.data.links;nextLinks.value=current.data.nextOffset;linksOffset.value=0;
 bookings.value=available.data.bookings;nextBookings.value=available.data.nextOffset;bookingOffset.value=0;selected.value="";
});}
function search(){appliedQuery.value=query.value.trim();void run(()=>findBookings());}
const associated=(id:string)=>links.value?.some(link=>link.bookingOwnerOrganizationId===props.organizationId && link.bookingId===id)??false;
function save(){
 const booking=bookings.value.find(item=>item.bookingId===selected.value);
 if(!booking || busy.value || associated(booking.bookingId) || !window.confirm(t("eventBookingLinks.confirm",{booking:booking.bookingCode,event:props.eventTitle})))return;
 void run(async()=>{
  await api.createEventBookingLink(props.eventId,{bookingOwnerOrganizationId:props.organizationId,bookingId:booking.bookingId,relationshipKind:kind.value});
  selected.value="";await loadLinks();notice.value=t("eventBookingLinks.saved");
 });
}
const reference=(link:EventBookingLink)=>link.bookingCode??t(link.bookingOwnerOrganizationId===props.organizationId?"eventBookingLinks.restricted":"eventBookingLinks.external");
const bookingState=(status:string)=>t(`eventBookingLinks.bookingState.${["confirmed","completed","cancelled","closed"].includes(status)?status:"unknown"}`);
onMounted(reload);
</script>
<template>
 <section class="event-booking-links" aria-labelledby="event-booking-links-heading" :aria-busy="busy">
  <h3 id="event-booking-links-heading">{{t("eventBookingLinks.title",{event:eventTitle})}}</h3>
  <p>{{t("eventBookingLinks.help")}}</p>
  <p v-if="error" role="alert" class="form-error">{{error}}</p>
  <p v-if="notice" role="status">{{notice}}</p>
  <button type="button" class="button button-secondary" :disabled="busy" @click="reload">{{t("eventBookingLinks.reload")}}</button>
  <template v-if="links">
   <p v-if="!links.length">{{t("eventBookingLinks.empty")}}</p>
   <div v-else class="links-scroll" role="region" :aria-label="t('eventBookingLinks.existing')" tabindex="0">
    <table><caption>{{t("eventBookingLinks.existing")}}</caption><thead><tr><th scope="col">{{t("eventBookingLinks.booking")}}</th><th scope="col">{{t("eventBookingLinks.kind")}}</th><th scope="col">{{t("eventBookingLinks.status")}}</th><th scope="col">{{t("eventBookingLinks.created")}}</th></tr></thead>
     <tbody><tr v-for="link in links" :key="link.linkId"><td>{{reference(link)}}</td><td>{{t(`eventBookingLinks.kinds.${link.relationshipKind}`)}}</td><td>{{t(`eventBookingLinks.statuses.${link.status}`)}}</td><td>{{formatDateTime(link.createdAt,locale)}}</td></tr></tbody>
    </table>
   </div>
   <div v-if="linksOffset || nextLinks!==null" class="links-toolbar">
    <button type="button" class="button button-secondary" :disabled="busy || linksOffset===0" @click="run(()=>loadLinks(Math.max(0,linksOffset-50)))">{{t("registry.previous")}}</button>
    <button type="button" class="button button-secondary" :disabled="busy || nextLinks===null" @click="run(()=>loadLinks(nextLinks??0))">{{t("registry.next")}}</button>
   </div>
   <form class="links-toolbar" @submit.prevent="search">
    <label for="event-booking-query">{{t("eventBookingLinks.search")}}</label><input id="event-booking-query" v-model="query" maxlength="80" :disabled="busy">
    <button class="button button-secondary" type="submit" :disabled="busy">{{t("registry.search")}}</button>
   </form>
   <p v-if="!bookings.length">{{t("eventBookingLinks.noBookings")}}</p>
   <form v-else class="links-form" @submit.prevent="save">
    <label for="event-booking-select">{{t("eventBookingLinks.choose")}}</label>
    <select id="event-booking-select" v-model="selected" required :disabled="busy"><option value="" disabled>{{t("eventBookingLinks.choose")}}</option>
     <option v-for="booking in bookings" :key="booking.bookingId" :value="booking.bookingId" :disabled="associated(booking.bookingId)">{{booking.bookingCode}} · {{bookingState(booking.status)}}{{associated(booking.bookingId)?` · ${t("eventBookingLinks.associated")}`:""}}</option>
    </select>
    <label for="event-booking-kind">{{t("eventBookingLinks.kind")}}</label><select id="event-booking-kind" v-model="kind" :disabled="busy"><option v-for="item in kinds" :key="item" :value="item">{{t(`eventBookingLinks.kinds.${item}`)}}</option></select>
    <button type="submit" class="button button-primary" :disabled="busy || !selected">{{t("eventBookingLinks.link")}}</button>
   </form>
   <div v-if="bookingOffset || nextBookings!==null" class="links-toolbar">
    <button type="button" class="button button-secondary" :disabled="busy || bookingOffset===0" @click="run(()=>findBookings(Math.max(0,bookingOffset-50)))">{{t("registry.previous")}}</button>
    <button type="button" class="button button-secondary" :disabled="busy || nextBookings===null" @click="run(()=>findBookings(nextBookings??0))">{{t("registry.next")}}</button>
   </div>
  </template>
 </section>
</template>
<style scoped>
.event-booking-links {display:grid;grid-template-columns:minmax(0,1fr);gap:.75rem;min-width:0;border:1px solid var(--border);border-radius:11px;padding:1rem;}
.links-toolbar {display:flex;flex-wrap:wrap;align-items:end;gap:.6rem;min-width:0;}
.links-toolbar input {max-width:24rem;}
.links-form {display:grid;grid-template-columns:minmax(0,1fr);gap:.6rem;max-width:34rem;}
.links-scroll {overflow-x:auto;min-width:0;max-width:100%;}
table {width:100%;min-width:36rem;border-collapse:collapse;text-align:left;}
th,td {padding:.65rem;border-bottom:1px solid var(--border);vertical-align:top;}
</style>
