import { fileURLToPath } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";

const report = spawnSync("npm", ["audit", "--audit-level=high", "--json"], {
  encoding: "utf8",
  maxBuffer: 10 * 1024 * 1024,
});
if (report.error || ![0, 1].includes(report.status)) {
  throw report.error ?? new Error(report.stderr || "npm audit failed.");
}
const result = JSON.parse(report.stdout);
if (result.error || !result.vulnerabilities || !result.metadata) {
  throw new Error(result.error?.summary ?? "npm audit returned an invalid report.");
}

const findings = result.vulnerabilities;
const advisory = "https://github.com/advisories/GHSA-fc5q-39xc-vjpf";

function coveredByMitigation(name, ancestors = new Set()) {
  const finding = findings[name];
  if (!finding?.via.length || ancestors.has(name)) return false;
  const visited = new Set([...ancestors, name]);
  return finding.via.every((cause) => typeof cause === "string"
    ? coveredByMitigation(cause, visited)
    : name === "picomatch" && cause.url === advisory &&
      finding.nodes.length === 1 && finding.nodes[0] === "node_modules/picomatch");
}

const highFindings = Object.keys(findings).filter((name) =>
  ["high", "critical"].includes(findings[name].severity));
if (report.status === 0 && highFindings.length === 0) {
  console.log("npm audit found no high or critical vulnerabilities.");
} else if (highFindings.length > 0 && highFindings.every((name) => coveredByMitigation(name))) {
  execFileSync(process.execPath, [fileURLToPath(new URL("./harden-picomatch.mjs", import.meta.url)), "--verify"], { stdio: "inherit" });
  console.log(`npm audit reported ${advisory}. The installed Picomatch parser matches the verified local mitigation.`);
} else {
  console.error(report.stdout);
  process.exitCode = 1;
}
