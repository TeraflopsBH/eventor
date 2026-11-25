import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_RSVP_SETTINGS_BROWSER_BASE_URL??'http://localhost:4173';
const org='22222222-2222-4222-8222-222222222222';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();
  const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-b@example.invalid',password:'CI-only-password-2026',organizationId:org}});assert.equal(login.status(),200,await login.text());
  const csrf=(await context.cookies()).find(cookie=>cookie.name==='__Host-eventor_csrf').value;
  const headers={origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()};
  assert.equal((await context.request.patch(base+'/api/me/preferences',{headers,data:{locale:'en'}})).status(),200);
  const title=`RSVP settings ${engine.name()} ${randomUUID()}`;
  const created=await context.request.post(`${base}/api/organizations/${org}/events`,{headers,data:{eventCode:'RSVP-'+randomUUID(),title,startsAt:'2031-01-18T10:00:00Z',endsAt:'2031-01-18T12:00:00Z',timezoneName:'Europe/Sarajevo'}});assert.equal(created.status(),201,await created.text());
  const eventId=(await created.json()).data.eventId;
  const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);await page.getByRole('button',{name:'Events',exact:true}).click();
  await page.getByRole('row').filter({hasText:title}).getByRole('button',{name:'RSVP settings',exact:true}).click();
  const region=page.getByRole('region',{name:'RSVP settings',exact:true});await region.getByText('No RSVP policy has been published.',{exact:true}).waitFor();
  await region.getByLabel('Tentative',{exact:true}).uncheck();
  await region.getByLabel('Response deadline (Europe/Sarajevo, optional)',{exact:true}).fill('2031-01-17T18:00');
  const firstSave=page.waitForResponse(response=>response.request().method()==='POST'&&new URL(response.url()).pathname.endsWith('/rsvp-settings'));
  page.once('dialog',dialog=>dialog.accept());await region.getByRole('button',{name:'Publish RSVP settings',exact:true}).click();
  const saved=await firstSave;assert.equal(saved.status(),200,await saved.text());const first=(await saved.json()).data.policy;
  assert.equal(new Date(first.responseDeadline).toISOString(),'2031-01-17T17:00:00.000Z');assert.deepEqual(first.allowedResponses,['accepted','declined']);
  const replayHeaders=await saved.request().allHeaders();
  const replay=await context.request.post(saved.url(),{headers:replayHeaders,data:saved.request().postDataJSON()});assert.equal(replay.status(),200,await replay.text());assert.deepEqual((await replay.json()).data.policy,first);
  const preciseDeadline='2031-01-17T17:00:23.456Z';
  const precise=await context.request.post(`${base}/api/events/${eventId}/rsvp-settings`,{headers:{...headers,'idempotency-key':randomUUID()},data:{expectedTimezoneName:'Europe/Sarajevo',expectedRevisionId:first.revisionId,allowedResponses:first.allowedResponses,responseDeadline:preciseDeadline,responseChangeAllowed:true}});assert.equal(precise.status(),200,await precise.text());
  const stale=await context.request.post(`${base}/api/events/${eventId}/rsvp-settings`,{headers:{...headers,'idempotency-key':randomUUID()},data:{expectedTimezoneName:'Europe/Sarajevo',expectedRevisionId:null,allowedResponses:['accepted'],responseDeadline:null,responseChangeAllowed:true}});assert.equal(stale.status(),412,await stale.text());
  const noCsrf=await context.request.post(`${base}/api/events/${eventId}/rsvp-settings`,{headers:{origin:base,'idempotency-key':randomUUID()},data:{expectedTimezoneName:'Europe/Sarajevo',expectedRevisionId:first.revisionId,allowedResponses:['accepted'],responseDeadline:null,responseChangeAllowed:true}});assert.equal(noCsrf.status(),403);
  const forbidden=await browser.newContext();assert.equal((await forbidden.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'organizer@demo.eventor.invalid',password:'CI-only-password-2026',organizationId:org}})).status(),200);
  assert.equal((await forbidden.request.get(`${base}/api/events/${eventId}/rsvp-settings`)).status(),403);
  const forbiddenCsrf=(await forbidden.cookies()).find(cookie=>cookie.name==='__Host-eventor_csrf').value;
  assert.equal((await forbidden.request.post(`${base}/api/events/${eventId}/rsvp-settings`,{headers:{origin:base,'x-csrf-token':forbiddenCsrf,'idempotency-key':randomUUID()},data:{expectedTimezoneName:'Europe/Sarajevo',expectedRevisionId:first.revisionId,allowedResponses:['accepted'],responseDeadline:null,responseChangeAllowed:true}})).status(),403);await forbidden.close();
  await page.reload();await page.getByRole('button',{name:'Events',exact:true}).click();await page.getByRole('row').filter({hasText:title}).getByRole('button',{name:'RSVP settings',exact:true}).click();
  await region.getByText('Published revision 2',{exact:true}).waitFor();assert.equal(await region.getByLabel('Response deadline (Europe/Sarajevo, optional)',{exact:true}).inputValue(),'2031-01-17T18:00');
  await region.getByLabel('Tentative',{exact:true}).check();await region.getByLabel('Allow guests to change their answer before the deadline',{exact:true}).uncheck();
  const secondSave=page.waitForResponse(response=>response.request().method()==='POST'&&new URL(response.url()).pathname.endsWith('/rsvp-settings'));
  page.once('dialog',dialog=>dialog.accept());await region.getByRole('button',{name:'Publish RSVP settings',exact:true}).click();const second=await secondSave;assert.equal(second.status(),200,await second.text());const finalPolicy=(await second.json()).data.policy;assert.equal(finalPolicy.revisionNumber,3);assert.equal(new Date(finalPolicy.responseDeadline).toISOString(),preciseDeadline);
  await region.getByText('Published revision 3',{exact:true}).waitFor();
  await context.close();console.log(`PASS ${engine.name()} RSVP policy publication, local deadline, refresh, revision conflict, CSRF and permission boundaries`);
 }finally{await browser.close();}
}
