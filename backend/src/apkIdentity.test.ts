import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import assert from "node:assert/strict";
import { apkVersionLabel, readApkIdentity } from "./apkIdentity";

test("lokale archie-os.apk: versie komt uit het bestand, niet uit een label", () => {
  const file = path.join(__dirname, "..", "..", "archie-os.apk");
  if (!fs.existsSync(file)) return;
  const id = readApkIdentity(fs.readFileSync(file));
  assert.ok(id);
  assert.equal(id.versionName, "0.2.0");
  assert.equal(id.versionCode, 212);
  assert.equal(apkVersionLabel(id), "0.2.0+212");
});
