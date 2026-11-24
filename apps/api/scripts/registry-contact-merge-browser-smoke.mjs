import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_CONTACT_MERGE_BROWSER_BASE_URL ?? "http://localhost:4173";
const org = "10000000-0000-0000-0000-00000000000a";
for (const engine of [chromium,firefox]) {
  const browser = await engine.launch();
  try {
    const context = await browser.newContext();
    const login = await context.request.post(`${baseUrl}/api/auth/session`,{
      headers:{origin:baseUrl},data:{email:"ci-extended-a@example.invalid",organizationSlug:"ci-tenant-a",password:"CI-only-password-2026"},
    });
    assert.equal(login.status(),200);
    const csrf = (await login.json()).data.csrfToken;
    const write = async (path,data,method="post") => {
      const response = await context.request[method](`${baseUrl}/api${path}`,{
        headers:{origin:baseUrl,"x-csrf-token":csrf,"idempotency-key":randomUUID()},data,
      });
      assert.ok(response.ok(),`${path}: ${response.status()} ${await response.text()}`);
      return (await response.json()).data;
    };
    const get = async path => {
      const response = await context.request.get(`${baseUrl}/api${path}`);
      assert.equal(response.status(),200,await response.text());
      return (await response.json()).data;
    };
    const tag = `ContactMerge${randomUUID()}`;
    const source = await write(`/organizations/${org}/persons`,{firstName:"Browser",lastName:tag,displayName:`Source ${tag}`,preferredName:null});
    const destination = await write(`/organizations/${org}/persons`,{firstName:"Browser",lastName:tag,displayName:`Destination ${tag}`,preferredName:null});
    const sourceValue = `source-${randomUUID()}@example.invalid`;
    const destinationValue = `destination-${randomUUID()}@example.invalid`;
    const contact = await write(`/persons/${source.personId}/contacts`,{kind:"email",value:sourceValue,consent:"restricted",primary:true});
    await write(`/persons/${source.personId}/contacts/${contact.contactId}/verification`,{expectedRevision:contact.revision,method:"in_person"},"patch");
    const existing = await write(`/persons/${destination.personId}/contacts`,{kind:"email",value:destinationValue,consent:"withdrawn",primary:false});
    const original = (await get(`/persons/${source.personId}/contacts`)).contacts[0];
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    await page.goto(baseUrl);
    await page.getByRole("button",{name:"Guest Registry",exact:true}).click();
    const search = page.getByLabel("Search by name",{exact:true});
    await search.fill(tag);
    await page.locator("form.registry-toolbar").getByRole("button",{name:"Search",exact:true}).click();
    const openReview = async () => {
      await page.getByRole("row").filter({has:page.getByRole("cell",{name:`Source ${tag}`,exact:true})})
        .getByRole("button",{name:"View profile",exact:true}).click();
      await page.getByRole("button",{name:"Review duplicate profile",exact:true}).click();
      await page.getByRole("button",{name:`Compare with Destination ${tag}`,exact:true}).click();
    };
    await openReview();
    await page.getByRole("heading",{name:"Review contact transfer",exact:true}).waitFor();
    await page.getByRole("cell",{name:sourceValue,exact:false}).waitFor();
    await page.getByRole("cell",{name:destinationValue,exact:false}).waitFor();
    const commit = page.getByRole("button",{name:"Merge as duplicate",exact:true});
    assert.equal(await commit.isEnabled(),false,"contact transfer did not require explicit review confirmation");
    await page.getByRole("checkbox",{name:"Move every source contact to the profile kept, preserving consent, primary status and verification.",exact:true}).check();
    const saved = page.waitForResponse(response=>response.request().method()==="POST" && new URL(response.url()).pathname.endsWith(`/persons/${source.personId}/merge`));
    page.once("dialog",dialog=>dialog.accept());
    await commit.click();
    const response = await saved;
    assert.equal(response.status(),201,await response.text());
    const merged = (await response.json()).data;
    const transferred = (await get(`/persons/${destination.personId}/contacts`)).contacts;
    assert.equal(transferred.length,2);
    assert.deepEqual({...transferred.find(item=>item.contactId===contact.contactId),revision:undefined},{...original,revision:undefined});
    assert.equal(transferred.find(item=>item.contactId===contact.contactId).revision,original.revision+1);
    assert.equal((await get(`/persons/${source.personId}/contacts`)).contacts.length,0);
    const replay = await context.request.post(response.url(),{
      headers:{origin:baseUrl,"x-csrf-token":csrf,"idempotency-key":(await response.request().allHeaders())["idempotency-key"]},
      data:response.request().postDataJSON(),
    });
    assert.equal(replay.status(),201);
    assert.deepEqual((await replay.json()).data,merged);
    const historyRow = page.getByRole("row").filter({hasText:tag}).filter({has:page.getByRole("button",{name:"Restore source profile",exact:true})});
    const restored = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith(`/merges/${merged.mergeId}/restore`));
    page.once("dialog",dialog=>dialog.accept());
    await historyRow.getByRole("button",{name:"Restore source profile",exact:true}).click();
    assert.equal((await restored).status(),200);
    const returned = (await get(`/persons/${source.personId}/contacts`)).contacts[0];
    assert.deepEqual({...returned,revision:undefined},{...original,revision:undefined});
    assert.equal(returned.revision,original.revision+2);
    assert.equal((await get(`/persons/${destination.personId}/contacts`)).contacts.length,1);
    assert.equal((await get(`/persons/${source.personId}`)).status,"active");
    await write(`/persons/${destination.personId}/contacts/${existing.contactId}`,{expectedRevision:existing.revision,consent:"restricted",primary:true},"patch");
    await page.getByRole("button",{name:"Merge history",exact:true}).click();
    await openReview();
    await page.getByText("These contacts contain a duplicate value or competing primary contacts. Resolve the contact conflict before merging.",{exact:true}).waitFor();
    assert.equal(await page.getByRole("button",{name:"Merge as duplicate",exact:true}).count(),0);
    await write(`/persons/${destination.personId}/contacts/${existing.contactId}`,{expectedRevision:existing.revision+1,consent:"restricted",primary:false},"patch");
    await page.getByRole("button",{name:`Compare with Destination ${tag}`,exact:true}).click();
    await page.getByRole("heading",{name:"Review contact transfer",exact:true}).waitFor();
    await page.getByRole("checkbox",{name:"Move every source contact to the profile kept, preserving consent, primary status and verification.",exact:true}).check();
    const secondSave = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith(`/persons/${source.personId}/merge`));
    page.once("dialog",dialog=>dialog.accept());
    await commit.click();
    const secondResponse = await secondSave;
    assert.equal(secondResponse.status(),201);
    const secondMerge = (await secondResponse.json()).data;
    const current = (await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===contact.contactId);
    await write(`/persons/${destination.personId}/contacts/${contact.contactId}`,{expectedRevision:current.revision,consent:"restricted",primary:false},"patch");
    const refused = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith(`/merges/${secondMerge.mergeId}/restore`));
    page.once("dialog",dialog=>dialog.accept());
    await historyRow.getByRole("button",{name:"Restore source profile",exact:true}).click();
    const refusal = await refused;
    assert.equal(refusal.status(),409);
    assert.equal((await refusal.json()).code,"MERGE_CONTACTS_CHANGED");
    await page.getByText("A transferred contact changed after this merge. Review the contact correction before restoring the source profile.",{exact:true}).waitFor();
    assert.equal((await get(`/persons/${source.personId}`)).status,"merged");
    const preserved = (await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===contact.contactId);
    assert.equal(preserved.primary,false);
    assert.equal(preserved.verified,true);
    assert.equal(preserved.revision,current.revision+1);
    console.log(`PASS ${engine.name()} reviewed contact merge, unchanged consent/verification, replay, restoration and conflict/correction guards`);
  } finally { await browser.close(); }
}
