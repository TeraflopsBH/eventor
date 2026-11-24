import assert from "node:assert/strict";
import {chromium,firefox} from "playwright";
const base=process.env.EVENTOR_STAFF_SHELL_BROWSER_BASE_URL??"http://localhost:4173";
for(const engine of [chromium,firefox]) {
 const browser=await engine.launch();
 try {
  const context=await browser.newContext();const page=await context.newPage();page.setDefaultTimeout(10000);
  await page.goto(base);
  await page.locator('.locale-picker select').selectOption('bs-BA');
  await page.reload();
  assert.equal(await page.locator('html').getAttribute('lang'),'bs-BA','anonymous language was lost on refresh');
  await page.locator('input[autocomplete="username"]').fill('ci-b@example.invalid');
  await page.locator('input[autocomplete="organization"]').fill('ci-venue-b');
  await page.locator('input[autocomplete="current-password"]').fill('CI-only-password-2026');
  await page.locator('form button[type="submit"]').click();
  await page.locator('.tabs').waitFor();
  assert.equal(await page.locator('html').getAttribute('lang'),'bs-BA');
  await page.reload();await page.locator('.tabs').waitFor();
  assert.equal(await page.locator('html').getAttribute('lang'),'bs-BA','signed-in language was lost on refresh');
  const savedEnglish=page.waitForResponse(r=>r.request().method()==='PATCH'&&r.url().endsWith('/me/preferences'));
  await page.locator('.locale-picker select').selectOption('en');assert.equal((await savedEnglish).status(),200);
  const navigation=await context.request.get(base+'/api/me/workspaces');assert.equal(navigation.status(),200);
  const workspaces=(await navigation.json()).data.workspaces;
  assert.ok(workspaces.includes('settings'));assert.ok(!workspaces.includes('forms'));
  assert.equal(await page.getByRole('button',{name:'Booking forms',exact:true}).count(),0,'forbidden configuration tab was shown');
  await page.route('**/api/organization/locale',route=>route.fulfill({status:403,contentType:'application/problem+json',body:JSON.stringify({status:403,code:'FORBIDDEN',title:'Permission changed'})}));
  await page.getByRole('button',{name:'Settings',exact:true}).click();await page.locator('.message-error').waitFor();
  await page.getByRole('button',{name:'Email delivery',exact:true}).click();
  assert.equal(await page.locator('.message-error').count(),0,'another section inherited a stale permission warning');
  await page.unroute('**/api/organization/locale');
  // An interrupted preference request is retried during session restoration.
  await page.route('**/api/me/preferences',route=>route.abort('failed'));
  await page.locator('.locale-picker select').selectOption('bs-BA');
  await page.locator('.message-error').waitFor();
  await page.unroute('**/api/me/preferences');
  await page.reload();await page.locator('.tabs').waitFor();
  assert.equal(await page.locator('html').getAttribute('lang'),'bs-BA');
  const me=await context.request.get(base+'/api/me');assert.equal((await me.json()).data.userLocale,'bs-BA');
  const restored=page.waitForResponse(r=>r.request().method()==='PATCH'&&r.url().endsWith('/me/preferences'));
  await page.locator('.locale-picker select').selectOption('en');assert.equal((await restored).status(),200);
  await context.close();console.log(`PASS ${engine.name()} language refresh/retry and permission-aware navigation/error isolation`);
 } finally {await browser.close();}
}
