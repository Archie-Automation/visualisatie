import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { lutronMappingHandles, planLutronHold, planLutronKnxWrite } from "./knxBridge";
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

  it("4-bit dimmen start bij indrukken en stopt bij loslaten", () => {
    const held = planLutronHold(knx({ role: "dim_control", value: true, send: "hold" }));
    assert.deepEqual(held.start, { kind: "dim", increase: true, step: 1 });
    assert.deepEqual(held.stop, { kind: "dim", increase: false, step: 0 });
    const darker = planLutronHold(knx({ role: "dim_control", value: false, send: "hold" }));
    assert.deepEqual(darker.start, { kind: "dim", increase: false, step: 1 });
  });

  it("zonwering loopt bij indrukken en stopt op het stop-adres", () => {
    const held = planLutronHold(
      knx({ role: "up_down", value: false, send: "hold", stopGa: "2/1/2" })
    );
    assert.deepEqual(held.start, { kind: "once", value: false });
    assert.deepEqual(held.stop, { kind: "shadeStop", ga: "2/1/2" });
    const down = planLutronHold(
      knx({ role: "up_down", value: true, send: "hold", stopGa: "2/1/2" })
    );
    assert.deepEqual(down.start, { kind: "once", value: true });
  });

  it("vasthouden luistert naar indrukken en loslaten, niet naar een losse actie", () => {
    const map = {
      actionNumber: 3,
      knx: knx({ role: "dim_control", value: true, send: "hold" })
    };
    assert.equal(lutronMappingHandles(map, 3), true);
    assert.equal(lutronMappingHandles(map, 4), true);
    assert.equal(lutronMappingHandles(map, 5), false);
    const pressOnly = { actionNumber: 3, knx: knx({ role: "bit", value: true, send: "value" }) };
    assert.equal(lutronMappingHandles(pressOnly, 3), true);
    assert.equal(lutronMappingHandles(pressOnly, 4), false);
  });
});
