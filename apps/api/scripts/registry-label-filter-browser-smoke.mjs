import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_LABEL_FILTER_BROWSER_BASE_URL??'http://localhost:4173',org='10000000-0000-0000-0000-00000000000a';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-extended-a@example.invalid',password:'CI-only-password-2026',organizationSlug:'ci-tenant-a'}});assert.equal(login.status(),200);const csrf=(await login.json()).data.csrfToken;
  const write=async(path,data,method='post')=>{const response=await context.request[method](base+'/api'+path,{headers:{origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()},data});assert.ok(response.ok(),`${path}: ${response.status()} ${await response.text()}`);return(await response.json()).data;};
  await write('/me/preferences',{locale:'en'},'patch');const tag=`LabelFilter${randomUUID()}`;
  const create=displayName=>write(`/organizations/${org}/persons`,{firstName:'Synthetic',lastName:tag,displayName});
  const vip=await create(`VIP person ${tag}`),other=await create(`Unclassified ${tag}`),archived=await create(`Archived VIP ${tag}`);
  const label=await write(`/organizations/${org}/persons/labels`,{label:`VIP filter ${tag}`});
  for(const person of [vip,archived])await write(`/persons/${person.personId}/labels`,{expectedRevision:1,labelIds:[label.labelId]},'patch');
  await write(`/persons/${archived.personId}/archive`,{expectedRevision:2});await write(`/organizations/${org}/persons/labels/${label.labelId}/retire`);
  const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);await page.getByRole('button',{name:'Guest Registry',exact:true}).click();
  const form=page.locator('form.registry-toolbar');await form.getByRole('option',{name:`${label.label} (retired)`,exact:true}).waitFor({state:'attached'});
  await form.getByLabel('Search by name',{exact:true}).fill(tag);await form.getByLabel('Registry classification',{exact:true}).selectOption(label.labelId);
  const searched=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/persons/search'));
  await form.getByRole('button',{name:'Search',exact:true}).click();const response=await searched;assert.equal(response.status(),200);assert.equal(response.request().postDataJSON().labelId,label.labelId);assert.deepEqual((await response.json()).data.people.map(person=>person.personId),[vip.personId]);
  await page.getByRole('row').filter({hasText:`VIP person ${tag}`}).getByRole('button',{name:'View profile',exact:true}).waitFor();
  assert.equal(await page.getByRole('row').filter({hasText:`Unclassified ${tag}`}).count(),0);
  await page.setViewportSize({width:375,height:812});const box=await form.getByLabel('Registry classification',{exact:true}).boundingBox();assert.ok(box && box.x>=0 && box.x+box.width<=375,'classification control overflowed the mobile viewport');assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth)<=375,'Registry results overflowed the mobile page');await page.setViewportSize({width:1280,height:720});
  for(const format of ['CSV','XLSX']){
   const exported=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/persons/export'));const download=page.waitForEvent('download');
   await form.getByRole('button',{name:`Export Registry as ${format}`,exact:true}).click();const result=await exported;assert.equal(result.status(),200);assert.equal(result.request().postDataJSON().labelId,label.labelId);assert.deepEqual((await result.json()).data.people.map(person=>person.displayName),[`VIP person ${tag}`]);
   assert.ok((await download).suggestedFilename().endsWith('.'+format.toLowerCase()));
  }
  await form.getByRole('checkbox').check();const archivedSearch=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/persons/search'));await form.getByRole('button',{name:'Search',exact:true}).click();assert.deepEqual((await(await archivedSearch).json()).data.people.map(person=>person.personId),[archived.personId]);
  await form.getByRole('checkbox').uncheck();await form.getByLabel('Registry classification',{exact:true}).selectOption('');const all=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/persons/search'));await form.getByRole('button',{name:'Search',exact:true}).click();assert.deepEqual((await(await all).json()).data.people.map(person=>person.personId).sort(),[vip.personId,other.personId].sort());
  // Exercise client cleanup with out-of-order responses; SQL tests separately revoke real grants.
  const delayedLabel=`Delayed classification ${tag}`;
  await page.route(`**/api/organizations/${org}/persons/search`,route=>route.fulfill({status:403,contentType:'application/json',body:JSON.stringify({code:'FORBIDDEN',message:'Synthetic permission denial'})}));
  await page.route(`**/api/organizations/${org}/persons/labels`,async route=>{await new Promise(resolve=>setTimeout(resolve,200));await route.fulfill({status:200,contentType:'application/json',body:JSON.stringify({data:[{labelId:label.labelId,label:delayedLabel,retired:false}]})});});
  const late=page.waitForResponse(r=>r.request().method()==='GET'&&r.url().endsWith('/persons/labels'));
  await form.getByRole('button',{name:'Search',exact:true}).click();await page.getByRole('alert').waitFor();await(await late).finished();
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
  assert.equal(await form.getByRole('option',{name:delayedLabel,exact:true}).count(),0);assert.equal(await page.getByRole('region',{name:'Registry search results',exact:true}).count(),0);
  await context.close();console.log(`PASS ${engine.name()} Registry classification filter, retired options, active/archived intersection matching CSV/XLSX exports and denied-read cleanup`);
 }finally{await browser.close();}
}
