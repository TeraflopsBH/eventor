import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_CONTACT_MERGE_BROWSER_BASE_URL ?? "http://localhost:4173";
const withReferences = process.env.EVENTOR_MERGE_REFERENCES === "1";
const reviewedRestoration = process.env.EVENTOR_REVIEWED_RESTORATION === "1";
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
    let originalReference;
    let destinationReference;
    let removableReference;
    if (withReferences) {
      await write(`/persons/${source.personId}/references`,{expectedRevision:source.revision,source:"BROWSER_MERGE",value:`SRC-${randomUUID()}`});
      await write(`/persons/${destination.personId}/references`,{expectedRevision:destination.revision,source:"BROWSER_MERGE",value:`DEST-${randomUUID()}`});
      originalReference = (await get(`/persons/${source.personId}/references`)).references[0];
      destinationReference = (await get(`/persons/${destination.personId}/references`)).references[0];
    }
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
    if (withReferences) {
      await page.getByRole("heading",{name:"Review source-reference transfer",exact:true}).waitFor();
      await page.getByRole("cell",{name:originalReference.value,exact:true}).waitFor();
      await page.getByRole("cell",{name:destinationReference.value,exact:true}).waitFor();
    }
    const commit = page.getByRole("button",{name:"Merge as duplicate",exact:true});
    assert.equal(await commit.isEnabled(),false,"contact transfer did not require explicit review confirmation");
    await page.getByRole("checkbox",{name:"Move every source contact to the profile kept, preserving consent, primary status and verification.",exact:true}).check();
    if (withReferences) {
      assert.equal(await commit.isEnabled(),false,"reference transfer did not require its own confirmation");
      await page.getByRole("checkbox",{name:"Move every source-system reference to the profile kept, preserving its identifier and value.",exact:true}).check();
    }
    const saved = page.waitForResponse(response=>response.request().method()==="POST" && new URL(response.url()).pathname.endsWith(`/persons/${source.personId}/merge`));
    page.once("dialog",dialog=>dialog.accept());
    await commit.click();
    const response = await saved;
    assert.equal(response.status(),201,await response.text());
    const merged = (await response.json()).data;
    if (withReferences) {
      assert.equal(response.request().postDataJSON().referenceResolution,"move_to_destination");
      const movedReferences = await get(`/persons/${destination.personId}/references`);
      assert.equal(movedReferences.profileRevision,3);
      assert.equal(movedReferences.references.length,2);
      assert.deepEqual(movedReferences.references.find(item=>item.referenceId===originalReference.referenceId),originalReference);
      assert.deepEqual(movedReferences.references.find(item=>item.referenceId===destinationReference.referenceId),destinationReference);
      assert.equal((await get(`/persons/${source.personId}/references`)).references.length,0);
    }
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
    if (withReferences) {
      const sourceReferences = await get(`/persons/${source.personId}/references`);
      const keptReferences = await get(`/persons/${destination.personId}/references`);
      assert.equal(sourceReferences.profileRevision,4);
      assert.equal(keptReferences.profileRevision,4);
      assert.deepEqual(sourceReferences.references,[originalReference]);
      assert.deepEqual(keptReferences.references,[destinationReference]);
    }
    if (reviewedRestoration) {
      const directory=await get(`/persons/${source.personId}/references`);
      const extra=await write(`/persons/${source.personId}/references`,{expectedRevision:directory.profileRevision,source:"BROWSER_REMOVABLE",value:`REMOVABLE-${randomUUID()}`});
      removableReference=(await get(`/persons/${source.personId}/references`)).references.find(item=>item.referenceId===extra.referenceId);
    }
    await write(`/persons/${destination.personId}/contacts/${existing.contactId}`,{expectedRevision:existing.revision,consent:"restricted",primary:true},"patch");
    await page.getByRole("button",{name:"Merge history",exact:true}).click();
    await openReview();
    await page.getByText("These contacts contain a duplicate value or competing primary contacts. Resolve the contact conflict before merging.",{exact:true}).waitFor();
    assert.equal(await page.getByRole("button",{name:"Merge as duplicate",exact:true}).count(),0);
    const conflictPanel = page.getByRole("region", { name: "Review conflicting contacts", exact: true });
    await conflictPanel.locator("td").filter({ hasText: sourceValue }).waitFor();
    await conflictPanel.locator("td").filter({ hasText: destinationValue }).waitFor();
    const clearDestination = page.getByRole("button", { name: `Clear primary flag for ${destinationValue} on Browser ${tag} and review again`, exact: true });
    const beforeCorrection = (await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===existing.contactId);
    page.once("dialog", dialog=>dialog.dismiss());
    await clearDestination.click();
    assert.deepEqual((await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===existing.contactId),beforeCorrection);
    // Another editor changes consent after the comparison. The stale correction must never overwrite it.
    await write(`/persons/${destination.personId}/contacts/${existing.contactId}`,{expectedRevision:beforeCorrection.revision,consent:"unknown",primary:true},"patch");
    page.once("dialog", dialog=>dialog.accept());
    const staleCorrection = page.waitForResponse(item=>item.request().method()==="PATCH" && new URL(item.url()).pathname.endsWith(`/contacts/${existing.contactId}`));
    await clearDestination.click();
    assert.equal((await staleCorrection).status(),412);
    await page.locator(".registry-merge").getByRole("alert").waitFor();
    assert.equal(await page.getByRole("button",{name:"Merge as duplicate",exact:true}).count(),0);
    const latestCorrection = (await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===existing.contactId);
    assert.equal(latestCorrection.consent,"unknown");
    assert.equal(latestCorrection.primary,true);
    await page.getByRole("button",{name:`Compare with Destination ${tag}`,exact:true}).click();
    await clearDestination.waitFor();
    page.once("dialog", dialog=>dialog.accept());
    const primaryCorrection = page.waitForResponse(item=>item.request().method()==="PATCH" && new URL(item.url()).pathname.endsWith(`/contacts/${existing.contactId}`));
    await clearDestination.click();
    assert.equal((await primaryCorrection).status(),200);
    await page.getByRole("heading",{name:"Review contact transfer",exact:true}).waitFor();
    assert.deepEqual((await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===existing.contactId),
      {...latestCorrection,primary:false,revision:latestCorrection.revision+1});
    assert.equal((await get(`/persons/${source.personId}`)).status,"active","primary correction silently merged the profiles");
    assert.equal(await commit.isEnabled(),false,"fresh review reused the prior transfer confirmation");
    await page.getByRole("checkbox",{name:"Move every source contact to the profile kept, preserving consent, primary status and verification.",exact:true}).check();
    if (withReferences) {
      await page.getByRole("checkbox",{name:"Move every source-system reference to the profile kept, preserving its identifier and value.",exact:true}).check();
    }
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
    if (withReferences) {
      const assertReferenceConflict = async () => {
        const deniedReferenceRestore = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith(`/merges/${secondMerge.mergeId}/restore`));
        page.once("dialog",dialog=>dialog.accept());
        await historyRow.getByRole("button",{name:"Restore source profile",exact:true}).click();
        const referenceConflict = await deniedReferenceRestore;
        assert.equal(referenceConflict.status(),409);
        assert.equal((await referenceConflict.json()).code,"MERGE_REFERENCES_CHANGED");
        await page.getByText("A transferred source reference changed or was removed after this merge. Review its correction before restoring the source profile.",{exact:true}).waitFor();
      };
      const currentReferences = await get(`/persons/${destination.personId}/references`);
      const editedValue = `EDITED-${randomUUID()}`;
      await write(`/persons/${destination.personId}/references/${originalReference.referenceId}`,{
        expectedRevision:currentReferences.profileRevision,source:originalReference.source,value:editedValue,
      },"patch");
      const editedReferences = await get(`/persons/${destination.personId}/references`);
      assert.equal(editedReferences.references.find(item=>item.referenceId===originalReference.referenceId).value,editedValue);
      await assertReferenceConflict();
      await write(`/persons/${destination.personId}/references/${reviewedRestoration ? removableReference.referenceId : originalReference.referenceId}/remove`,{expectedRevision:editedReferences.profileRevision});
      await assertReferenceConflict();
      const remainingReferences=(await get(`/persons/${destination.personId}/references`)).references;
      if (reviewedRestoration) {
        assert.equal(remainingReferences.length,2);
        assert.equal(remainingReferences.find(item=>item.referenceId===originalReference.referenceId).value,editedValue);
      } else assert.deepEqual(remainingReferences,[destinationReference]);
      assert.equal((await get(`/persons/${source.personId}/references`)).references.length,0);
      assert.equal((await get(`/persons/${source.personId}`)).status,"merged");
      assert.equal((await get(`/persons/${destination.personId}/contacts`)).contacts.find(item=>item.contactId===contact.contactId).revision,current.revision+1);
      if (reviewedRestoration) {
        await historyRow.getByRole("button",{name:"Review current records",exact:true}).click();
        const panel=page.getByRole("region",{name:"Review current records for restoration",exact:true});
        const returnContact=panel.getByRole("checkbox",{name:`Return contact ${sourceValue} to source`,exact:true});
        const returnReference=panel.getByRole("checkbox",{name:`Return reference ${editedValue} to source`,exact:true});
        await returnContact.check();await returnReference.check();
        assert.equal(await panel.getByText(removableReference.value,{exact:true}).count(),0,"removed private reference value reappeared in review");
        const acknowledgement=panel.getByRole("checkbox",{name:"I reviewed these choices and where the current records will remain.",exact:true});
        const apply=panel.getByRole("button",{name:"Apply reviewed restoration",exact:true});
        await acknowledgement.check();
        assert.equal(await apply.isEnabled(),false,"missing references were not explicitly acknowledged");
        await panel.getByRole("checkbox",{name:"Keep removed source references deleted",exact:true}).check();
        await acknowledgement.check();
        const applied=page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith(`/merges/${secondMerge.mergeId}/restore-reviewed`));
        page.once("dialog",dialog=>dialog.accept());await apply.click();
        const appliedResponse=await applied;
        assert.equal(appliedResponse.status(),200,await appliedResponse.text());
        const appliedData=(await appliedResponse.json()).data;
        const applyReplay=await context.request.post(appliedResponse.url(),{
          headers:{origin:baseUrl,"x-csrf-token":csrf,"idempotency-key":(await appliedResponse.request().allHeaders())["idempotency-key"]},
          data:appliedResponse.request().postDataJSON(),
        });
        assert.equal(applyReplay.status(),200);assert.deepEqual((await applyReplay.json()).data,appliedData);
        await panel.waitFor({state:"detached"});
        const correctedContact=(await get(`/persons/${source.personId}/contacts`)).contacts[0];
        assert.deepEqual({...correctedContact,revision:undefined},{...preserved,revision:undefined});
        assert.equal(correctedContact.revision,preserved.revision+1);
        assert.equal((await get(`/persons/${destination.personId}/contacts`)).contacts.length,1);
        assert.deepEqual((await get(`/persons/${source.personId}/references`)).references,[{...originalReference,value:editedValue}]);
        assert.deepEqual((await get(`/persons/${destination.personId}/references`)).references,[destinationReference]);
        assert.equal((await get(`/persons/${source.personId}`)).status,"active");
        const correctedHistory=(await get(`/organizations/${org}/persons/merges?offset=0`)).merges.find(item=>item.mergeId===secondMerge.mergeId);
        assert.equal(correctedHistory.restorationMode,"reviewed_current_state");
        await page.getByRole("row").filter({hasText:tag}).getByText("Reviewed current-state restoration",{exact:true}).waitFor();
      }
    }
    console.log(`PASS ${engine.name()} reviewed ${reviewedRestoration ? "current-state restoration and reference/contact" : withReferences ? "reference/contact" : "contact"} merge, unchanged values, replay, restoration and conflict/correction guards`);
  } finally { await browser.close(); }
}
