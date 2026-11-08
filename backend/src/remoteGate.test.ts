import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import { describe, it } from "node:test";
import type { NextFunction, Request, Response } from "express";

process.env.SESSIONS_STORE_PATH = path.join(
  os.tmpdir(),
  `archie-sessions-test-${process.pid}.json`
);

import { remoteLoginBlocked } from "./auth";
import {
  isLanAddress,
  isLoopbackAddress,
  isRemoteFacingPeer,
  remoteApiAllowed,
  remoteGate,
  signGate,
  verifyGate
} from "./remoteGate";
import { claimPairCode, createPairCode, forgetGate, gateTicketValid, rememberGate } from "./sessions";

process.env.REMOTE_URL = "https://huis.example";
process.env.JWT_SECRET = "test-gate-secret";

function run(
  peer: string,
  url: string,
  extra?: { cookie?: string; authorization?: string; method?: string }
) {
  let status = 0;
  let body: unknown;
  let nexted = false;
  const headers: Record<string, string> = {};
  const q = new URL(url, "http://n").searchParams;
  const query: Record<string, string> = {};
  q.forEach((v, k) => {
    query[k] = v;
  });
  const req = {
    socket: { remoteAddress: peer },
    originalUrl: url,
    url,
    method: extra?.method ?? "GET",
    query,
    headers: {
      cookie: extra?.cookie,
      authorization: extra?.authorization
    }
  };
  const res = {
    status(n: number) {
      status = n;
      return this;
    },
    setHeader(k: string, v: string) {
      headers[k.toLowerCase()] = v;
    },
    append(k: string, v: string) {
      headers[k.toLowerCase()] = v;
    },
    json(b: unknown) {
      body = b;
    },
    send(b: unknown) {
      body = b;
    }
  };
  remoteGate(req as unknown as Request, res as unknown as Response, (() => {
    nexted = true;
  }) as NextFunction);
  return { status, body, nexted, headers };
}

describe("remote gate classification", () => {
  it("treats the house LAN as local and the tunnel as remote", () => {
    assert.equal(isLanAddress("192.168.1.20"), true);
    assert.equal(isLanAddress("::ffff:192.168.1.20"), true);
    assert.equal(isLanAddress("10.80.0.4"), false);
    assert.equal(isLanAddress("10.1.0.4"), true);
    assert.equal(isRemoteFacingPeer("192.168.1.20", true), false);
    assert.equal(isRemoteFacingPeer("::ffff:10.80.0.1", true), true);
    assert.equal(isRemoteFacingPeer("1.2.3.4", true), true);
    assert.equal(isRemoteFacingPeer("1.2.3.4", false), false);
  });

  it("keeps probes and pair-claim open, and closes password login", () => {
    assert.equal(remoteApiAllowed("GET", "/api/health"), true);
    assert.equal(remoteApiAllowed("POST", "/api/auth/pair/claim"), true);
    assert.equal(remoteApiAllowed("POST", "/api/auth/login"), false);
    assert.equal(remoteApiAllowed("GET", "/api/webhooks/ring/deur"), true);
  });
});

describe("remote gate middleware", () => {
  it("serves the app on the LAN and hides it on the tunnel", () => {
    assert.equal(run("192.168.1.20", "/").nexted, true);
    const closed = run("10.80.0.1", "/");
    assert.equal(closed.nexted, false);
    assert.equal(closed.status, 404);
    assert.match(String(closed.body), /Deze pagina is niet openbaar/);
  });

  it("blocks password login from the tunnel unless the browser was invited", () => {
    const denied = run("10.80.0.1", "/api/auth/login", { method: "POST" });
    assert.equal(denied.nexted, false);
    assert.equal(denied.status, 403);
    assert.deepEqual(denied.body, { error: "remote_closed" });

    const forged = run("10.80.0.1", "/api/auth/login", {
      method: "POST",
      authorization: "Bearer aaaaaaaaaaaaaaaaaaaa"
    });
    assert.equal(forged.nexted, false);

    const exp = Math.floor(Date.now() / 1000) + 60;
    rememberGate("invite-browser");
    const cookie = `archie_gate=${encodeURIComponent(signGate("test-gate-secret", exp, "invite-browser"))}`;
    assert.equal(run("10.80.0.1", "/api/auth/login", { method: "POST", cookie }).nexted, true);
  });

  it("lets an already paired app through on its token, and health without one", () => {
    assert.equal(run("10.80.0.1", "/api/health").nexted, true);
    assert.equal(run("10.80.0.1", "/api/config").nexted, false);
    assert.equal(
      run("10.80.0.1", "/api/config", { authorization: "Bearer aaaaaaaaaaaaaaaaaaaa" }).nexted,
      true
    );
  });

  it("sets a cookie when the invite link is opened", () => {
    const { gateTicket } = createPairCode("user-1", "admin");
    const opened = run("10.80.0.1", `/pair?ticket=${encodeURIComponent(gateTicket)}`);
    assert.equal(opened.nexted, true);
    assert.match(opened.headers["set-cookie"] ?? "", /archie_gate=/);
    assert.equal(run("10.80.0.1", "/pair?ticket=nope").nexted, false);
  });
});

describe("gate cookie and factory password", () => {
  it("rejects a tampered or expired cookie", () => {
    const now = 1_700_000_000;
    rememberGate("g1");
    const token = signGate("s", now + 10, "g1");
    assert.equal(verifyGate("s", token, now), true);
    assert.equal(verifyGate("s", token, now + 11), false);
    assert.equal(verifyGate("other", token, now), false);
    const flipped = `${token.slice(0, -2)}aa`;
    assert.equal(verifyGate("s", flipped, now), false);
  });

  it("closes the cloud page when that invite is withdrawn", () => {
    const exp = Math.floor(Date.now() / 1000) + 60;
    rememberGate("phone-gate");
    const cookie = `archie_gate=${encodeURIComponent(signGate("test-gate-secret", exp, "phone-gate"))}`;
    assert.equal(run("10.80.0.1", "/", { cookie }).nexted, true);
    forgetGate("phone-gate");
    const closed = run("10.80.0.1", "/", { cookie });
    assert.equal(closed.nexted, false);
    assert.match(String(closed.body), /Deze pagina is niet openbaar/);
  });

  it("drops the invite ticket once the code is claimed", () => {
    const { code, gateTicket } = createPairCode("missing-user", "admin");
    assert.equal(gateTicketValid(gateTicket), true);
    assert.equal(claimPairCode(code, "telefoon"), null);
    assert.equal(gateTicketValid(gateTicket), false);
  });

  it("treats only this machine as loopback", () => {
    assert.equal(isLoopbackAddress("127.0.0.1"), true);
    assert.equal(isLoopbackAddress("::1"), true);
    assert.equal(isLoopbackAddress("::ffff:127.0.0.1"), true);
    assert.equal(isLoopbackAddress("192.168.1.20"), false);
    assert.equal(isLoopbackAddress("10.80.0.2"), false);
  });

  it("refuses admin/admin and placeholder hashes from remote", () => {
    assert.equal(remoteLoginBlocked("admin", "admin", "$2a$realhash"), true);
    assert.equal(remoteLoginBlocked("Admin", "admin", "$2a$realhash"), true);
    assert.equal(remoteLoginBlocked("gast", "geheim", "REPLACE_ME"), true);
    assert.equal(remoteLoginBlocked("admin", "ander-wachtwoord", "$2a$realhash"), false);
  });
});
