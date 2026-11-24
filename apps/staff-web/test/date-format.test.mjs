import assert from 'node:assert/strict';
import test from 'node:test';
import {formatDateTime} from '../src/i18n/format.ts';
test('Bosnian display uses day.month.year and a 24-hour clock in the supplied time zone',()=>{
 assert.equal(formatDateTime('2026-11-24T14:05:00Z','bs-BA',{timeZone:'Europe/Sarajevo'}),'24.11.2026 15:05');
 assert.equal(formatDateTime('2026-11-24T23:00:00Z','bs-BA',{timeZone:'Europe/Sarajevo'}),'25.11.2026 00:00');
 assert.equal(formatDateTime('2026-07-01T12:30:00Z','bs-BA',{timeZone:'Europe/Sarajevo'}),'01.07.2026 14:30');
});
test('date-only labels do not acquire a time and invalid dates are safe',()=>{
 assert.equal(formatDateTime('2026-11-24T14:05:00Z','bs-BA',{dateStyle:'medium',timeZone:'UTC'}),'24.11.2026');
 assert.equal(formatDateTime('invalid','bs-BA'),'—');
 assert.ok(!formatDateTime('2026-11-24T14:05:00Z','en',{dateStyle:'medium',timeZone:'UTC'}).includes(':'));
});
