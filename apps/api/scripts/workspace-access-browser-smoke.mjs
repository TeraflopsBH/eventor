import assert from 'node:assert/strict';import {chromium,firefox} from 'playwright';
const base=process.env.EVENTOR_WORKSPACE_BROWSER_BASE_URL??'http://localhost:4173';
const orgA='11111111-1111-4111-8111-111111111111',orgB='22222222-2222-4222-8222-222222222222';
for(const engine of [chromium,firefox]){
 const browser=await engine.launch();try{
  const context=await browser.newContext();const page=await context.newPage();page.setDefaultTimeout(12000);await page.goto(base);
  assert.equal(await page.locator('input[autocomplete="organization"]').count(),0,'technical slug remained in the login form');
  await page.getByLabel('Email address').fill('organizer@demo.eventor.invalid');await page.getByLabel('Password',{exact:true}).fill('CI-only-password-2026');
  const choicesResponse=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/auth/session'));
  await page.getByRole('button',{name:'Sign in securely'}).click();const first=await choicesResponse;assert.equal(first.status(),200);const choices=(await first.json()).data;
  assert.equal(choices.organizationSelectionRequired,true);assert.equal(choices.organizations.length,2);assert.equal((await context.cookies()).filter(c=>c.name==='__Host-eventor_session').length,0);
  const chosen=choices.organizations.find(o=>o.organizationId===orgB);await page.getByLabel('Choose your workspace',{exact:true}).selectOption(orgB);
  await page.getByRole('button',{name:'Sign in securely'}).click();await page.locator('.tabs').waitFor();assert.equal(await page.locator('.account strong').innerText(),chosen.organizationName);
  const cookies=await context.cookies();const oldExpiry=cookies.find(c=>c.name==='__Host-eventor_session').expires;const oldCookie=cookies.map(c=>`${c.name}=${c.value}`).join('; ');const csrf=cookies.find(c=>c.name==='__Host-eventor_csrf').value;
  const denied=await context.request.post(base+'/api/auth/session/organization',{headers:{origin:base,'x-csrf-token':csrf},data:{organizationId:'33333333-3333-4333-8333-333333333333'}});assert.equal(denied.status(),403);
  const noCsrf=await context.request.post(base+'/api/auth/session/organization',{headers:{origin:base},data:{organizationId:orgA}});assert.equal(noCsrf.status(),403);
  const switched=page.waitForResponse(r=>r.request().method()==='POST'&&r.url().endsWith('/auth/session/organization'));
  await page.getByLabel('Workspace',{exact:true}).selectOption(orgA);assert.equal((await switched).status(),200);
  await page.locator('.account strong').filter({hasText:choices.organizations.find(o=>o.organizationId===orgA).organizationName}).waitFor();
  const me=await context.request.get(base+'/api/me');assert.equal((await me.json()).data.organizationId,orgA);
  assert.ok((await context.cookies()).find(c=>c.name==='__Host-eventor_session').expires<=oldExpiry+1,'workspace switching extended session lifetime');
  const old=await browser.newContext();const revoked=await old.request.get(base+'/api/me',{headers:{cookie:oldCookie}});assert.equal(revoked.status(),401);await old.close();
  assert.equal((await context.request.get(`${base}/api/organizations/${orgA}/persons`)).status(),403,'ordinary organizer gained Registry authority');await context.close();
  const admin=await browser.newContext();const login=await admin.request.post(base+'/api/auth/session',{headers:{origin:base},data:{email:'admin@demo.eventor.invalid',password:'CI-only-password-2026',organizationId:orgB}});assert.equal(login.status(),200,await login.text());
  const adminMe=(await(await admin.request.get(base+'/api/me')).json()).data;assert.equal(adminMe.platformAdmin,true);assert.ok(adminMe.memberships.some(m=>m.organizationId===orgA));assert.ok(adminMe.memberships.some(m=>m.organizationId==='10000000-0000-0000-0000-00000000000a'));
  assert.equal((await admin.request.get(`${base}/api/organizations/${orgB}/persons`)).status(),200);assert.equal((await admin.request.get(`${base}/api/organizations/${orgA}/persons`)).status(),403,'platform role bypassed the selected tenant context');
  const adminPage=await admin.newPage();await adminPage.goto(base);await adminPage.getByText('Platform administrator',{exact:true}).waitFor();await adminPage.getByLabel('Workspace',{exact:true}).selectOption(orgA);
  await adminPage.locator('.account strong').filter({hasText:adminMe.memberships.find(item=>item.organizationId===orgA).organizationName}).waitFor();
  await adminPage.getByRole('button',{name:'Guest Registry',exact:true}).waitFor();
  assert.equal((await admin.request.get(`${base}/api/organizations/${orgA}/persons`)).status(),200);await admin.close();
  console.log(`PASS ${engine.name()} email-first selection, atomic context rotation, CSRF, tenant limits and explicit platform access`);
 }finally{await browser.close();}
}
