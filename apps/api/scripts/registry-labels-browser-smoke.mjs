import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_REGISTRY_LABELS_BROWSER_BASE_URL??'http://localhost:4173';
const org='10000000-0000-0000-0000-00000000000a';
for(const engine of [chromium,firefox]) {
 const browser=await engine.launch();
 try {
  const context=await browser.newContext();const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-extended-a@example.invalid',password:'CI-only-password-2026',organizationSlug:'ci-tenant-a'}});assert.equal(login.status(),200);
  const csrf=(await login.json()).data.csrfToken;
  const headers={origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()};
  const name=`RegistryLabels${randomUUID()}`;
  const created=await context.request.post(`${base}/api/organizations/${org}/persons`,{headers,data:{firstName:'Synthetic',lastName:name,displayName:name,preferredName:null}});assert.equal(created.status(),201,await created.text());
  const person=(await created.json()).data;
  const page=await context.newPage();page.setDefaultTimeout(10000);await page.goto(base);await page.getByRole('button',{name:'Guest Registry',exact:true}).click();
  await page.getByLabel('Search by name',{exact:true}).fill(name);await page.locator('form.registry-toolbar').getByRole('button',{name:'Search',exact:true}).click();
  await page.getByRole('row').filter({has:page.getByRole('cell',{name,exact:true})}).getByRole('button',{name:'View profile',exact:true}).click();
  await page.getByRole('heading',{name:'Registry labels',exact:true}).waitFor();
  const label=`VIP ${randomUUID()}`;await page.getByLabel('New Registry label',{exact:true}).fill(label);
  const definition=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/persons/labels'));
  await page.getByRole('button',{name:'Create label',exact:true}).click();const labelResponse=await definition;assert.equal(labelResponse.status(),201);const entry=(await labelResponse.json()).data;
  await page.getByRole('checkbox',{name:label,exact:true}).check();
  const saved=page.waitForResponse(r=>r.request().method()==='PATCH'&&r.url().endsWith(`/persons/${person.personId}/labels`));
  await page.getByRole('button',{name:'Save profile labels',exact:true}).click();assert.equal((await saved).status(),200);
  await page.getByRole('status').filter({hasText:'Profile labels saved.'}).waitFor();
  page.once('dialog',dialog=>dialog.accept());const retired=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith(`/labels/${entry.labelId}/retire`));
  await page.getByRole('button',{name:`Retire label ${label}`,exact:true}).click();assert.equal((await retired).status(),200);
  const checkbox=page.getByRole('checkbox',{name:`${label} (retired)`,exact:true});assert.equal(await checkbox.isChecked(),true);
  await checkbox.uncheck();const removed=page.waitForResponse(r=>r.request().method()==='PATCH'&&r.url().endsWith(`/persons/${person.personId}/labels`));
  await page.getByRole('button',{name:'Save profile labels',exact:true}).click();const removal=await removed;assert.equal(removal.status(),200);const revision=(await removal.json()).data.revision;
  await page.getByRole('status').filter({hasText:'Profile labels saved.'}).waitFor();assert.equal(await checkbox.isDisabled(),true);
  const forbidden=await context.request.patch(`${base}/api/persons/${person.personId}/labels`,{headers:{...headers,'idempotency-key':randomUUID()},data:{expectedRevision:revision,labelIds:[entry.labelId]}});assert.equal(forbidden.status(),409);
  await context.close();console.log(`PASS ${engine.name()} persistent Registry classification, retirement and assignment guards`);
 } finally {await browser.close();}
}
