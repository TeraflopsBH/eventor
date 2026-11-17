import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const parser = new URL("../node_modules/picomatch/lib/parse.js", import.meta.url);
const upstreamHash = "4e1e05447668aa1e94366c5516a2bcd8f5fff800cc92b1d0cd7d77703b8618c4";
const patchedHash = "616f52e7c0b620cfe4e64f62a39843dc25594db368045695c7f9791704ba53b1";
const declaration = "const analyzeRepeatedExtglob = (body, options) => {";
const mitigation = `${declaration}
  // CVE-2026-112366: keep wildcard repetitions out of unbounded extglobs.
  if (/[+*?{(]/.test(body)) {
    return { risky: true };
  }
`;

const sha256 = (value) => createHash("sha256").update(value).digest("hex");
const source = readFileSync(parser, "utf8");
const sourceHash = sha256(source);
if (sourceHash !== patchedHash) {
  if (process.argv.includes("--verify") || sourceHash !== upstreamHash) {
    throw new Error("The installed Picomatch parser does not match the verified CVE-2026-112366 mitigation.");
  }
  const patched = source.replace(declaration, mitigation);
  if (sha256(patched) !== patchedHash) throw new Error("Picomatch mitigation checksum mismatch.");
  writeFileSync(parser, patched);
}
