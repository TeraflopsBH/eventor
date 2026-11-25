import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_BOOKING_LINK_BROWSER_BASE_URL??'http://localhost:4173',org='10000000-0000-0000-0000-00000000000a',booking='f0000000-0000-0000-0000-00000000000a';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-booking-link@example.invalid',password:'CI-only-password-2026'}});assert.equal(login.status(),200,await login.text());const csrf=(await login.json()).data.csrfToken;
  const write=async(path,data,method='post')=>{const response=await context.request[method](base+'/api'+path,{headers:{origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()},data});assert.ok(response.ok(),`${path}: ${response.status()} ${await response.text()}`);return(await response.json()).data;};
  const get=async path=>{const response=await context.request.get(base+'/api'+path);assert.equal(response.status(),200,await response.text());return(await response.json()).data;};
  await write('/me/preferences',{locale:'en'},'patch');
  const title=`Synthetic linked event ${randomUUID()}`;
  const event=await write(`/organizations/${org}/events`,{eventCode:`EVT-${randomUUID().replaceAll('-','').slice(0,16).toUpperCase()}`,title,startsAt:'2027-04-02T08:00:00Z',endsAt:'2027-04-02T09:00:00Z',timezoneName:'Europe/Sarajevo'});
  const before=(await get(`/organizations/${org}/events`)).find(item=>item.eventId===event.eventId);assert.ok(before);assert.equal(before.guestRegistryEnabled,false);
  const choices=await write(`/organizations/${org}/booking-references/search`,{query:'CI-EXTERNAL-CANCEL',offset:0});const target=choices.bookings.find(item=>item.bookingId===booking);assert.ok(target,'synthetic booking reference missing');
  const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);await page.getByRole('button',{name:'Events',exact:true}).click();
  await page.getByRole('button',{name:`Linked bookings for ${title}`,exact:true}).click();const panel=page.locator('.event-booking-links');
  await panel.getByLabel('Booking reference search',{exact:true}).fill(target.bookingCode);const searched=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/booking-references/search'));await panel.getByRole('button',{name:'Search',exact:true}).click();assert.equal((await searched).status(),200);
  await panel.getByLabel('Choose a booking',{exact:true}).selectOption(booking);await panel.getByLabel('Relationship',{exact:true}).selectOption('service_for_event');
  page.once('dialog',dialog=>dialog.dismiss());await panel.getByRole('button',{name:'Link booking',exact:true}).click();assert.equal((await get(`/events/${event.eventId}/booking-links`)).links.length,0);
  const saved=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith(`/events/${event.eventId}/booking-links`));page.once('dialog',dialog=>dialog.accept());await panel.getByRole('button',{name:'Link booking',exact:true}).click();const response=await saved;assert.equal(response.status(),201,await response.text());assert.equal(response.request().postDataJSON().bookingOwnerOrganizationId,org);assert.equal(response.request().postDataJSON().relationshipKind,'service_for_event');
  await panel.getByRole('cell',{name:target.bookingCode,exact:true}).waitFor();assert.equal((await get(`/events/${event.eventId}/booking-links`)).links[0].bookingCode,target.bookingCode);
  const after=(await get(`/organizations/${org}/events`)).find(item=>item.eventId===event.eventId);assert.equal(after.status,before.status);assert.equal(after.detailsRevision,before.detailsRevision);assert.equal(after.scheduleRevision,before.scheduleRevision);assert.equal(after.guestRegistryEnabled,before.guestRegistryEnabled);
  assert.equal(await panel.locator('#event-booking-select option:checked').getAttribute('value'),'');assert.equal(await panel.locator(`#event-booking-select option[value="${booking}"]`).isDisabled(),true);
  await page.setViewportSize({width:375,height:812});const box=await panel.boundingBox();assert.ok(box && box.x>=0 && box.x+box.width<=375);await page.setViewportSize({width:1280,height:720});
  await write('/me/preferences',{locale:'bs-BA'},'patch');await page.reload();await page.getByRole('button',{name:`Povezane rezervacije za ${title}`,exact:true}).click();await panel.getByRole('heading',{name:`Rezervacije za ${title}`,exact:true}).waitFor();
  await panel.getByRole('cell',{name:'Usluga za događaj',exact:true}).waitFor();await panel.getByRole('cell',{name:/^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}$/,exact:true}).waitFor();
  await page.setViewportSize({width:375,height:812});
  page.once('dialog',dialog=>dialog.dismiss());await panel.getByRole('button',{name:'Završi povezivanje',exact:true}).click();assert.equal((await get(`/events/${event.eventId}/booking-links`)).links[0].status,'active');
  const ended=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/end'));page.once('dialog',dialog=>dialog.accept());await panel.getByRole('button',{name:'Završi povezivanje',exact:true}).click();assert.equal((await ended).status(),200);await panel.getByRole('cell',{name:'Završena',exact:true}).waitFor();assert.equal(await panel.getByRole('button',{name:'Završi povezivanje',exact:true}).count(),0);
  const final=(await get(`/organizations/${org}/events`)).find(item=>item.eventId===event.eventId);for(const key of ['status','detailsRevision','scheduleRevision','guestRegistryEnabled'])assert.equal(final[key],before[key]);
  await page.route(`**/api/events/${event.eventId}/booking-links*`,route=>route.fulfill({status:403,contentType:'application/json',body:JSON.stringify({code:'FORBIDDEN',message:'Synthetic revoked event scope'})}));
  await panel.getByRole('button',{name:'Ponovo učitaj povezane rezervacije',exact:true}).click();await panel.getByRole('alert').waitFor();assert.equal(await panel.getByRole('cell',{name:target.bookingCode,exact:true}).count(),0);
  await context.close();console.log(`PASS ${engine.name()} permitted booking selection, cancelled confirmation, association creation, unchanged event capabilities, mobile layout, Bosnian labels/dates, cancelled/confirmed ending and denial cleanup`);
 }finally{await browser.close();}
}
