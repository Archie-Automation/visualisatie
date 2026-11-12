import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildGoToLevel,
  buildPingResponse,
  encodeLeap,
  isLeapTransportPort,
  leapErrorMessage,
  parsePairingMessage,
  parseZoneList
} from "./leapMessages";

describe("LEAP-berichten", () => {
  it("herkent de Designer-poort en laat telnet-poort 23 met rust", () => {
    assert.equal(isLeapTransportPort(8902), true);
    assert.equal(isLeapTransportPort(8081), true);
    assert.equal(isLeapTransportPort(23), false);
    assert.equal(isLeapTransportPort(undefined), false);
  });

  it("beantwoordt de ping van de processor", () => {
    const pong = buildPingResponse({
      CommuniqueType: "ReadRequest",
      Header: { ClientTag: "ping-1", Url: "/server/1/status/ping" }
    }) as { Header: { StatusCode: string; Url: string; ClientTag: string } };
    assert.equal(pong.Header.StatusCode, "200 OK");
    assert.equal(pong.Header.Url, "/server/1/status/ping");
    assert.equal(pong.Header.ClientTag, "ping-1");
    assert.equal(buildPingResponse({ CommuniqueType: "ReadResponse", Header: { Url: "/zone/1" } }), null);
  });

  it("zet een dimmer-commando op de LEAP-zone", () => {
    const msg = buildGoToLevel(12, 40, 2) as {
      Header: { Url: string };
      Body: { Command: { CommandType: string; Parameter: { Type: string; Value: number | string }[] } };
    };
    assert.equal(msg.Header.Url, "/zone/12/commandprocessor");
    assert.equal(msg.Body.Command.CommandType, "GoToLevel");
    assert.deepEqual(msg.Body.Command.Parameter, [
      { Type: "Level", Value: 40 },
      { Type: "FadeTime", Value: "00:00:02" }
    ]);
    assert.ok(encodeLeap(msg).endsWith("\r\n"));
  });

  it("leest het certificaat uit het koppel-antwoord", () => {
    const waiting = parsePairingMessage({
      Header: { StatusCode: "202 Accepted" },
      Body: { Status: { SigningStatus: "WaitingForButtonPress", Permissions: ["PhysicalAccess"] } }
    });
    assert.equal(waiting.kind, "button");

    const done = parsePairingMessage({
      Header: { StatusCode: "200 OK" },
      Body: {
        SigningResult: {
          Certificate: "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n",
          RootCertificate: "-----BEGIN CERTIFICATE-----\nROOT\n-----END CERTIFICATE-----\n"
        }
      }
    });
    assert.equal(done.kind, "cert");
    if (done.kind === "cert") {
      assert.match(done.certificate, /BEGIN CERTIFICATE/);
    }
  });

  it("koppelt zone-ids aan de ruimtenaam", () => {
    const zones = parseZoneList(
      {
        Body: {
          Zones: [
            {
              href: "/zone/7",
              Name: "Eettafel",
              ControlType: "Dimmed",
              AssociatedArea: { href: "/area/3" }
            }
          ]
        }
      },
      { Body: { Areas: [{ href: "/area/3", Name: "Keuken" }] } }
    );
    assert.deepEqual(zones, [
      { id: 7, name: "Eettafel", controlType: "Dimmed", area: "Keuken" }
    ]);
  });

  it("geeft de processorfout door", () => {
    assert.equal(
      leapErrorMessage({
        CommuniqueType: "ExceptionResponse",
        Header: { StatusCode: "400 BadRequest", Message: "Unknown zone", Url: "/zone/1/commandprocessor" }
      }),
      "Unknown zone"
    );
    assert.equal(leapErrorMessage({ CommuniqueType: "CreateResponse", Header: { StatusCode: "201 Created" } }), null);
  });
});
