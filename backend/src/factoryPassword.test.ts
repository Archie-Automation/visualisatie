import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { factoryPasswordActive, rejectedLoginPassword } from "./auth";

describe("factory password", () => {
  it("herkent het placeholder-hash", () => {
    assert.equal(factoryPasswordActive("$2b$10$REPLACE_ME_WITH_BCRYPT_HASH"), true);
    assert.equal(factoryPasswordActive("$2a$10$realesaltandhash"), false);
    assert.equal(factoryPasswordActive(undefined), false);
  });

  it("weigert fabrieks- en te korte wachtwoorden", () => {
    assert.equal(rejectedLoginPassword("admin", "admin"), "Kies minstens 8 tekens.");
    assert.equal(
      rejectedLoginPassword("admin", "admin   "),
      "Dit wachtwoord is niet toegestaan."
    );
    assert.equal(
      rejectedLoginPassword("pietpiet", "pietpiet"),
      "Het wachtwoord mag niet gelijk zijn aan de gebruikersnaam."
    );
    assert.equal(rejectedLoginPassword("admin", "koetjes12"), null);
  });
});
