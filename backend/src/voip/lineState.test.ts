import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { IntercomLineBook } from "./lineState";

describe("intercom line", () => {
  it("laat tijdens rinkelen elk paneel nog opnemen", () => {
    const book = new IntercomLineBook();
    assert.equal(book.onRing("door"), "ringing");
    assert.equal(book.claim("door", "paneel-a"), false);
    assert.equal(book.phase("door"), "ringing");
  });

  it("blokkeert een tweede paneel zodra iemand belt of praat", () => {
    const book = new IntercomLineBook();
    assert.equal(book.claim("door", "paneel-a"), true);
    assert.equal(book.claim("door", "paneel-b"), false);
    book.onBusy("door");
    assert.equal(book.phase("door"), "busy");
    assert.equal(book.claim("door", "paneel-b"), false);
    assert.equal(book.release("door", "paneel-a"), false);
  });

  it("geeft de lijn vrij na ophangen, en een verlopen reservering ook", () => {
    const book = new IntercomLineBook();
    book.claim("door", "paneel-a", 0);
    assert.equal(book.phase("door", 25_001), "idle");
    book.claim("door", "paneel-a", 30_000);
    book.onBusy("door");
    book.onIdle("door");
    assert.equal(book.phase("door"), "idle");
    assert.equal(book.claim("door", "paneel-b"), true);
  });

  it("houdt een lopend gesprek bezet als de deur opnieuw belt", () => {
    const book = new IntercomLineBook();
    book.onBusy("door");
    assert.equal(book.onRing("door"), "busy");
  });
});
