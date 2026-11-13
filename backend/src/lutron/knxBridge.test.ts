import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { planLutronKnxWrite } from "./knxBridge";
import type { LutronKnxBinding } from "../types";

function knx(partial: Partial<LutronKnxBinding> & Pick<LutronKnxBinding, "role" | "value">): LutronKnxBinding {
  return { ga: "1/1/1", ...partial };
}

describe("Lutron-knop → KNX", () => {
  it("een bit zonder puls stuurt de waarde één keer", () => {
    const plan = planLutronKnxWrite(knx({ role: "bit", value: true, send: "value" }), false);
    assert.deepEqual(plan, { kind: "once", value: true });
  });

  it("een oude bit-koppeling met pulsduur gaat aan en weer uit", () => {
    const plan = planLutronKnxWrite(knx({ role: "switch", value: true, pulseMs: 250 }), undefined);
    assert.deepEqual(plan, { kind: "pulse", on: true, off: false, ms: 250 });
  });

  it("toggle stuurt de andere waarde als de status al aan is", () => {
    const plan = planLutronKnxWrite(
      knx({ role: "bit", value: true, valueOff: false, send: "toggle" }),
      1
    );
    assert.deepEqual(plan, { kind: "once", value: false });
  });

  it("toggle stuurt de aan-waarde als de status onbekend of uit is", () => {
    const off = planLutronKnxWrite(
      knx({ role: "percent", value: 80, valueOff: 0, send: "toggle" }),
      0
    );
    const unknown = planLutronKnxWrite(
      knx({ role: "percent", value: 80, valueOff: 0, send: "toggle" }),
      undefined
    );
    assert.deepEqual(off, { kind: "once", value: 80 });
    assert.deepEqual(unknown, { kind: "once", value: 80 });
  });

  it("een scene wordt DPT 18.001", () => {
    const plan = planLutronKnxWrite(knx({ role: "scene", value: 3, send: "value" }), undefined);
    assert.deepEqual(plan, { kind: "scene", byte: 2 });
  });
});
