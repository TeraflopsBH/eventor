import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_LABEL_MERGE_BROWSER_BASE_URL??'http://localhost:4173';const org='10000000-0000-0000-0000-00000000000a';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();const login=await context.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'ci-extended-a@example.invalid',organizationSlug:'ci-tenant-a',password:'CI-only-password-2026'}});assert.equal(login.status(),200);const csrf=(await login.json()).data.csrfToken;
  const write=async(path,data,method='post')=>{const response=await context.request[method](base+'/api'+path,{headers:{origin:base,'x-csrf-token':csrf,'idempotency-key':randomUUID()},data});assert.ok(response.ok(),`${path}: ${response.status()} ${await response.text()}`);return(await response.json()).data;};
  const get=async path=>{const response=await context.request.get(base+'/api'+path);assert.equal(response.status(),200,await response.text());return(await response.json()).data;};
  await write('/me/preferences',{locale:'en'},'patch');const tag=`LabelMerge${randomUUID()}`;
  const source=await write(`/organizations/${org}/persons`,{firstName:'Synthetic',lastName:tag,displayName:`Source ${tag}`});
  const destination=await write(`/organizations/${org}/persons`,{firstName:'Synthetic',lastName:tag,displayName:`Destination ${tag}`});
  const vip=await write(`/organizations/${org}/persons/labels`,{label:`VIP ${tag}`});const retired=await write(`/organizations/${org}/persons/labels`,{label:`Retired ${tag}`});const keep=await write(`/organizations/${org}/persons/labels`,{label:`Destination ${tag}`});
  await write(`/persons/${source.personId}/labels`,{expectedRevision:1,labelIds:[vip.labelId,retired.labelId]},'patch');
  await write(`/persons/${destination.personId}/labels`,{expectedRevision:1,labelIds:[keep.labelId]},'patch');await write(`/organizations/${org}/persons/labels/${retired.labelId}/retire`);
  const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);await page.getByRole('button',{name:'Guest Registry',exact:true}).click();
  await page.getByLabel('Search by name',{exact:true}).fill(tag);await page.locator('form.registry-toolbar').getByRole('button',{name:'Search',exact:true}).click();
  await page.getByRole('row').filter({hasText:`Source ${tag}`}).getByRole('button',{name:'View profile',exact:true}).click();await page.getByRole('button',{name:'Review duplicate profile',exact:true}).click();
  await page.getByRole('button',{name:`Compare with Destination ${tag}`,exact:true}).click();const review=page.locator('.registry-merge');
  await review.getByRole('listitem').filter({hasText:vip.label}).waitFor();await review.getByRole('listitem').filter({hasText:retired.label}).locator('span').waitFor();
  const commit=review.getByRole('button',{name:'Merge as duplicate',exact:true});assert.equal(await commit.isDisabled(),true);
  await review.getByRole('checkbox',{name:'I reviewed these labels and agree to transfer the source assignments unchanged.',exact:true}).check();
  page.once('dialog',dialog=>dialog.dismiss());await commit.click();assert.equal((await get(`/persons/${source.personId}/labels`)).assignedLabelIds.length,2);
  const saved=page.waitForResponse(response=>response.request().method()==='POST'&&response.url().endsWith(`/persons/${source.personId}/merge`));page.once('dialog',dialog=>dialog.accept());await commit.click();const response=await saved;assert.equal(response.status(),201,await response.text());const merge=(await response.json()).data;assert.equal(response.request().postDataJSON().labelResolution,'move_to_destination');
  const target=await get(`/persons/${destination.personId}/labels`);assert.deepEqual([...target.assignedLabelIds].sort(),[vip.labelId,retired.labelId,keep.labelId].sort());assert.equal((await get(`/persons/${source.personId}/labels`)).assignedLabelIds.length,0);
  const replay=await context.request.post(response.url(),{headers:await response.request().allHeaders(),data:response.request().postDataJSON()});assert.equal(replay.status(),201);assert.deepEqual((await replay.json()).data,merge);
  const history=page.getByRole('row').filter({hasText:tag}).filter({has:page.getByRole('button',{name:'Restore source profile',exact:true})});await history.getByRole('button',{name:'Review current records',exact:true}).click();const correction=page.locator('.registry-restoration');await correction.getByRole('listitem').filter({hasText:vip.label}).waitFor();await correction.getByRole('button',{name:'Close',exact:true}).click();const restored=page.waitForResponse(item=>item.request().method()==='POST'&&item.url().endsWith(`/merges/${merge.mergeId}/restore`));page.once('dialog',dialog=>dialog.accept());await history.getByRole('button',{name:'Restore source profile',exact:true}).click();assert.equal((await restored).status(),200);
  assert.deepEqual((await get(`/persons/${source.personId}/labels`)).assignedLabelIds.sort(),[vip.labelId,retired.labelId].sort());assert.deepEqual((await get(`/persons/${destination.personId}/labels`)).assignedLabelIds,[keep.labelId]);
  await context.close();console.log(`PASS ${engine.name()} reviewed label transfer, retired classifications, cancellation, destination preservation, idempotent retry and restoration`);
 }finally{await browser.close();}
}
