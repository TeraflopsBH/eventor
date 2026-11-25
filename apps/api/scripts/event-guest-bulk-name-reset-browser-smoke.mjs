import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_BULK_NAME_RESET_BROWSER_BASE_URL??'http://localhost:4173';
const org='10000000-0000-0000-0000-00000000000a';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-extended-a@example.invalid',organizationSlug:'ci-tenant-a',password:'CI-only-password-2026'}});assert.equal(login.status(),200,await login.text());const csrf=(await login.json()).data.csrfToken;
  const write=async(path,data,method='post')=>{const response=await context.request[method](base+'/api'+path,{headers:{origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()},data});assert.ok(response.ok(),await response.text());return(await response.json()).data;};
  const get=async path=>{const response=await context.request.get(base+'/api'+path);assert.equal(response.status(),200,await response.text());return(await response.json()).data;};
  await write('/me/preferences',{locale:'en'},'patch');
  const tag=randomUUID().slice(0,8);const event=await write(`/organizations/${org}/events`,{eventCode:`NAME-${tag}`,title:`Bulk name reset ${tag}`,startsAt:'2031-01-18T10:00:00Z',endsAt:'2031-01-18T12:00:00Z',timezoneName:'UTC'});const root=`/events/${event.eventId}`;
  await write(root+'/guest-registry/enable');const people=[];
  for(const name of ['First','Second']){
   const person=await write(`/organizations/${org}/persons`,{firstName:name,lastName:`Synthetic ${tag}`,displayName:`Recorded ${name} ${tag}`});people.push(person.personId);
   const guest=await write(root+'/participations',{personId:person.personId,status:'eligible'});
   await write(`${root}/participations/${guest.participationId}/roster-name`,{displayName:`Temporary ${name} ${tag}`,expectedRevision:1},'patch');
  }
  const before=await get(root+'/participations');const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);await page.getByRole('button',{name:'Event guests',exact:true}).click();await page.locator('#roster-event').selectOption(event.eventId);await page.getByRole('checkbox',{name:'Select all editable guests on this page'}).check();
  page.once('dialog',dialog=>dialog.dismiss());await page.getByRole('button',{name:'Restore recorded display names',exact:true}).click();assert.ok((await get(root+'/participations')).people.every(row=>row.displayNameOverride!==null));
  const changed=page.waitForResponse(response=>response.request().method()==='POST'&&response.url().endsWith('/bulk/roster-name-reset'));
  page.once('dialog',dialog=>{assert.ok(dialog.message().includes('2 selected guests'));return dialog.accept();});await page.getByRole('button',{name:'Restore recorded display names',exact:true}).click();const response=await changed;assert.equal(response.status(),200,await response.text());assert.deepEqual((await response.json()).data,{processedCount:2,updatedCount:2});
  await page.getByRole('status').filter({hasText:'Updated 2 of 2 selected guests.'}).waitFor();
  const request=response.request();const replay=await context.request.post(request.url(),{headers:await request.allHeaders(),data:request.postDataJSON()});assert.equal(replay.status(),200);assert.deepEqual(await replay.json(),await response.json());
  const after=await get(root+'/participations');for(const row of after.people){const previous=before.people.find(item=>item.participationId===row.participationId);assert.equal(row.displayNameOverride,null);assert.equal(row.recordedDisplayName,previous.recordedDisplayName);assert.equal(row.displayName,row.recordedDisplayName);assert.equal(row.revision,previous.revision+1);}
  for(const personId of people){const profile=await get(`/persons/${personId}`);assert.ok(profile.displayName.startsWith('Recorded '));}
  const stale=await context.request.post(request.url(),{headers:{origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()},data:request.postDataJSON()});assert.equal(stale.status(),412);
  const noCsrf=await context.request.post(request.url(),{headers:{origin:base,'idempotency-key':randomUUID()},data:request.postDataJSON()});assert.equal(noCsrf.status(),403);
  await context.close();console.log(`PASS ${engine.name()} confirmed bulk name reset, cancellation, pinned names, Registry isolation, idempotent retry and stale selection`);
 }finally{await browser.close();}
}
