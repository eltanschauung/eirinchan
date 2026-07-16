import assert from "node:assert/strict";
import {execFile} from "node:child_process";
import path from "node:path";
import test from "node:test";
import {fileURLToPath} from "node:url";
import {promisify} from "node:util";

const execute = promisify(execFile);
const projectRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");

test("the JavaScript audit inventories the checkout without errors", async () => {
  const {stdout} = await execute(
    process.execPath,
    ["priv/scripts/audit_javascript.mjs", "--check", "--json"],
    {cwd: projectRoot, maxBuffer: 4 * 1024 * 1024}
  );
  const report = JSON.parse(stdout);

  assert.ok(report.summary.files >= 70);
  assert.equal(report.summary.errors, 0);
  assert.ok(report.summary.categories["maintained-source"] >= 11);
});
