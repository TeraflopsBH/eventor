import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import test from "node:test";

test("staff tooling keeps ordinary globs and neutralizes CVE-2026-112366 extglobs", () => {
  execFileSync(process.execPath, ["--input-type=module", "--eval", `
    import assert from "node:assert/strict";
    import picomatch from "picomatch";
    assert.equal(picomatch("src/**/*.vue")("src/feature/Panel.vue"), true);
    assert.equal(picomatch("+(a|b)")("abab"), true);
    for (const pattern of ["+(*)", "+(*a)", "*(*a)"]) {
      const regex = picomatch.makeRe(pattern);
      assert.equal(regex.test("a".repeat(100) + "!"), false);
      assert.equal(regex.test(pattern), true);
    }
    assert.equal(picomatch.makeRe("+(?*a)").test("a".repeat(100) + "!"), false);
  `], { cwd: new URL("../", import.meta.url), timeout: 3000 });
});
