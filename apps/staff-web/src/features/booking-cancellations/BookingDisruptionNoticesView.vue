<script setup lang="ts">
import { formatDateTime } from "../../i18n/format";
import { onMounted, reactive, ref } from "vue";
import { useI18n } from "vue-i18n";
import { api, ApiError, type BookingDisruptionNotice, type DisruptionBooking } from "../../api";
import { formatApiError } from "../../i18n/api-errors";

const props = defineProps<{ organizationId: string }>();
const { t, locale } = useI18n();
const bookings = ref<DisruptionBooking[]>([]);
const bookingId = ref("");
const query = ref("");
const appliedQuery = ref("");
const offset = ref(0);
const nextOffset = ref<number | null>(null);
const notices = ref<BookingDisruptionNotice[]>([]);
const noticeOffset = ref(0);
const nextNoticeOffset = ref<number | null>(null);
const draft = reactive({reasonCategory:"",publicSummary:"",affectedFrom:"",affectedUntil:""});
const busy = ref(false);
const error = ref("");
const notice = ref("");

function formatDate(value: string | null): string {
  return value ? formatDateTime(value, locale.value) : "—";
}

async function run(operation: () => Promise<void>): Promise<void> {
  busy.value = true;
  error.value = "";
  notice.value = "";
  try { await operation(); }
  catch (failure) {
    if (failure instanceof ApiError && [401,403].includes(failure.status)) {
      notices.value = [];
      bookings.value = [];
      bookingId.value = "";
    }
    error.value = failure instanceof ApiError ? formatApiError(failure,t) : t("bookingDisruption.failed");
  } finally { busy.value = false; }
}

async function loadBookings(page: number): Promise<void> {
  const {data} = await api.searchDisruptionBookings(props.organizationId,appliedQuery.value,page);
  bookings.value = data.bookings;
  nextOffset.value = data.nextOffset;
  offset.value = page;
  bookingId.value = "";
  notices.value = [];
}

async function loadNotices(page: number): Promise<void> {
  const {data} = await api.getBookingDisruptionNotices(bookingId.value,page);
  notices.value = data.notices;
  nextNoticeOffset.value = data.nextOffset;
  noticeOffset.value = page;
}

function search(): void {
  appliedQuery.value = query.value.trim();
  void run(() => loadBookings(0));
}

function openBooking(): void {
  notices.value = [];
  Object.assign(draft,{reasonCategory:"",publicSummary:"",affectedFrom:"",affectedUntil:""});
  if (bookingId.value) void run(() => loadNotices(0));
}

function record(): void {
  if (!bookingId.value || !window.confirm(t("bookingDisruption.confirmRecord"))) return;
  void run(async () => {
    await api.recordBookingDisruptionNotice(bookingId.value,{
      reasonCategory:draft.reasonCategory.trim(),publicSummary:draft.publicSummary.trim(),
      affectedFrom:draft.affectedFrom ? new Date(draft.affectedFrom+"Z").toISOString() : null,
      affectedUntil:draft.affectedUntil ? new Date(draft.affectedUntil+"Z").toISOString() : null,
    });
    Object.assign(draft,{reasonCategory:"",publicSummary:"",affectedFrom:"",affectedUntil:""});
    await loadNotices(0);
    notice.value = t("bookingDisruption.recorded");
  });
}

onMounted(() => run(() => loadBookings(0)));
</script>

<template>
  <section class="panel" aria-labelledby="booking-disruption-heading" :aria-busy="busy">
    <h3 id="booking-disruption-heading">{{ t("bookingDisruption.title") }}</h3>
    <p>{{ t("bookingDisruption.recordingScope") }}</p>
    <p v-if="error" role="alert" class="form-error">{{ error }}</p>
    <p v-if="notice" role="status">{{ notice }}</p>
    <form class="toolbar" @submit.prevent="search">
      <label>{{ t("bookingDisruption.bookingSearch") }}<input v-model="query" type="search" maxlength="80" :disabled="busy"></label>
      <button class="button button-secondary" type="submit" :disabled="busy">{{ t("registry.search") }}</button>
    </form>
    <p v-if="!busy && !bookings.length">{{ t("bookingDisruption.noBookings") }}</p>
    <template v-if="bookings.length">
      <label for="disruption-booking">{{ t("bookingDisruption.booking") }}</label>
      <select id="disruption-booking" v-model="bookingId" :disabled="busy" @change="openBooking">
        <option value="">{{ t("bookingDisruption.chooseBooking") }}</option>
        <option v-for="booking in bookings" :key="booking.bookingId" :value="booking.bookingId">{{ booking.bookingCode }}</option>
      </select>
    </template>
    <div v-if="offset>0 || nextOffset!==null" class="toolbar">
      <button type="button" class="button button-secondary" :disabled="busy || offset===0" @click="run(() => loadBookings(offset-50))">{{ t("registry.previous") }}</button>
      <button type="button" class="button button-secondary" :disabled="busy || nextOffset===null" @click="run(() => loadBookings(nextOffset ?? 0))">{{ t("registry.next") }}</button>
    </div>
    <template v-if="bookingId">
      <h4>{{ t("bookingDisruption.record") }}</h4>
      <form class="form-grid" @submit.prevent="record">
        <label>{{ t("bookingDisruption.category") }}<input v-model="draft.reasonCategory" required pattern="[a-z][a-z0-9_.\-]{1,79}" maxlength="80" :disabled="busy"></label>
        <label>{{ t("bookingDisruption.summary") }}<textarea v-model="draft.publicSummary" required maxlength="2000" rows="3" :disabled="busy"></textarea></label>
        <label>{{ t("bookingDisruption.fromUtc") }}<input v-model="draft.affectedFrom" type="datetime-local" :disabled="busy"></label>
        <label>{{ t("bookingDisruption.untilUtc") }}<input v-model="draft.affectedUntil" type="datetime-local" :disabled="busy"></label>
        <button type="submit" class="button button-primary" :disabled="busy || !draft.reasonCategory.trim() || !draft.publicSummary.trim()">{{ t("bookingDisruption.record") }}</button>
      </form>
      <h4>{{ t("bookingDisruption.history") }}</h4>
      <p v-if="!notices.length">{{ t("bookingDisruption.empty") }}</p>
      <ol class="history-list">
        <li v-for="item in notices" :key="item.noticeId">
          <strong>{{ item.noticeCode }}</strong> · {{ item.reasonCategory }}
          <p class="disruption-summary">{{ item.publicSummary }}</p>
          <p>{{ formatDate(item.affectedFrom) }} – {{ formatDate(item.affectedUntil) }}</p>
          <time :datetime="item.issuedAt">{{ formatDate(item.issuedAt) }}</time>
        </li>
      </ol>
      <div v-if="noticeOffset>0 || nextNoticeOffset!==null" class="toolbar">
        <button type="button" class="button button-secondary" :disabled="busy || noticeOffset===0" @click="run(() => loadNotices(noticeOffset-50))">{{ t("registry.previous") }}</button>
        <button type="button" class="button button-secondary" :disabled="busy || nextNoticeOffset===null" @click="run(() => loadNotices(nextNoticeOffset ?? 0))">{{ t("registry.next") }}</button>
      </div>
    </template>
  </section>
</template>

<style scoped>
.disruption-summary { white-space: pre-wrap; overflow-wrap: anywhere; }
</style>
