import assert from 'node:assert/strict';
import test from 'node:test';
import {storedStaffLocale,rememberStaffLocale,queueStaffLocale,pendingStaffLocale,acknowledgeStaffLocale} from '../src/i18n/staff-locale.ts';
function resetStorage() {
 const values=new Map();
 globalThis.localStorage={getItem:key=>values.get(key)??null,setItem:(key,value)=>values.set(key,value),removeItem:key=>values.delete(key)};
 return values;
}
test('language chosen before sign-in survives refresh and is queued for the signed-in account',()=>{
 resetStorage();const choice=queueStaffLocale('bs-BA',null);
 assert.equal(storedStaffLocale(),'bs-BA');assert.deepEqual(pendingStaffLocale('staff-a'),choice);
 acknowledgeStaffLocale(choice);assert.equal(pendingStaffLocale('staff-a'),null);assert.equal(storedStaffLocale(),'bs-BA');
});
test('an interrupted save cannot change another account and an older acknowledgement cannot discard the latest choice',()=>{
 resetStorage();const old=queueStaffLocale('bs-BA','staff-a');const latest=queueStaffLocale('en','staff-a');
 assert.equal(pendingStaffLocale('staff-b'),null);acknowledgeStaffLocale(old);
 assert.deepEqual(pendingStaffLocale('staff-a'),latest);assert.equal(storedStaffLocale(),'en');
});
test('malformed or unavailable browser storage leaves language selection usable',()=>{
 const values=resetStorage();values.set('eventor.staff.locale','invalid');values.set('eventor.staff.pendingLocale','bad json');
 assert.equal(storedStaffLocale(),null);assert.equal(pendingStaffLocale('staff-a'),null);
 Object.defineProperty(globalThis,'localStorage',{configurable:true,get(){throw new Error('storage unavailable');}});
 assert.doesNotThrow(()=>rememberStaffLocale('bs-BA'));assert.doesNotThrow(()=>queueStaffLocale('bs-BA',null));
 assert.equal(storedStaffLocale(),null);
 delete globalThis.localStorage;
});
