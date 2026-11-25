import assert from 'node:assert/strict';
import test from 'node:test';
import { sessionLocalTime, zonedLocalDateTimeToIso } from '../src/local-date-time.ts';
test('event-local date input converts winter and summer offsets and rejects nonexistent local times',()=>{
 assert.equal(zonedLocalDateTimeToIso('2031-01-18T12:30','Europe/Sarajevo'),'2031-01-18T11:30:00.000Z');
 assert.equal(zonedLocalDateTimeToIso('2031-07-18T12:30','Europe/Sarajevo'),'2031-07-18T10:30:00.000Z');
 assert.equal(sessionLocalTime('2031-07-18T10:30:15Z','Europe/Sarajevo'),'2031-07-18T12:30');
 assert.throws(()=>zonedLocalDateTimeToIso('2026-03-29T02:30','Europe/Sarajevo'));
 assert.throws(()=>zonedLocalDateTimeToIso('2031-02-31T12:30','Europe/Sarajevo'));
});
