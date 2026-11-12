import assert from "node:assert/strict";
import { describe, it } from "node:test";
import {
  buildGoToLevel,
  buildPairRequest,
  buildPingResponse,
  buildSpectrum,
  buildWhite,
  encodeLeap,
  isLeapTransportPort,
  leapErrorMessage,
  leapButtonAction,
  parseButtonEvents,
  collectDefinedButtons,
  deviceMayHaveButtons,
  parseButtonList,
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

  it("stuurt de CSR pas als commando CSR met rol Admin", () => {
    const msg = buildPairRequest("-----BEGIN CERTIFICATE REQUEST-----\nA\n-----END CERTIFICATE REQUEST-----\n") as {
      Body: { CommandType: string; Parameters: { Role: string; DeviceUID: string } };
    };
    assert.equal(msg.Body.CommandType, "CSR");
    assert.equal(msg.Body.Parameters.Role, "Admin");
    assert.equal(msg.Body.Parameters.DeviceUID, "000000000000");
  });

  it("zet kleur en tunable white op een QSX-zone", () => {
    const color = buildSpectrum(30, 80, 180, 75) as {
      Body: { Command: { CommandType: string; SpectrumTuningLevelParameters: { Level: number; ColorTuningStatus: { HSVTuningLevel: { Hue: number; Saturation: number } } } } };
    };
    assert.equal(color.Body.Command.CommandType, "GoToSpectrumTuningLevel");
    assert.equal(color.Body.Command.SpectrumTuningLevelParameters.Level, 80);
    assert.deepEqual(color.Body.Command.SpectrumTuningLevelParameters.ColorTuningStatus.HSVTuningLevel, {
      Hue: 180,
      Saturation: 75
    });
    const white = buildWhite(30, 40, 2700) as {
      Body: { Command: { CommandType: string; WhiteTuningLevelParameters: { Level: number; ColorTuningStatus: { WhiteTuningLevel: { Kelvin: number } } } } };
    };
    assert.equal(white.Body.Command.CommandType, "GoToWhiteTuningLevel");
    assert.equal(white.Body.Command.WhiteTuningLevelParameters.ColorTuningStatus.WhiteTuningLevel.Kelvin, 2700);
  });

  it("leest een keypad-druk als actie 3", () => {
    assert.equal(leapButtonAction("Press"), 3);
    assert.equal(leapButtonAction("Release"), 4);
    const presses = parseButtonEvents({
      Header: { Url: "/button/42/status" },
      Body: {
        ButtonStatus: {
          Button: { href: "/button/42" },
          ButtonEvent: { EventType: "Press" }
        }
      }
    });
    assert.deepEqual(presses, [{ id: 42, action: 3 }]);
    const listed = parseButtonList({
      Body: { Buttons: [{ href: "/button/42", Name: "Sfeer", ButtonNumber: 2 }] }
    });
    assert.deepEqual(listed, [{ id: 42, name: "Sfeer", buttonNumber: 2, deviceName: "" }]);
    const engraved = collectDefinedButtons(
      {
        Body: {
          ControlStation: { href: "/controlstation/4", Name: "Keuken" },
          Buttons: [
            {
              href: "/button/8",
              Name: "Button 1",
              ButtonNumber: 1,
              Engraving: { Text: "Eten" }
            }
          ]
        }
      },
      "Keuken"
    );
    assert.deepEqual(engraved, [{ id: 8, name: "Eten", buttonNumber: 1, deviceName: "Keuken" }]);
    assert.equal(deviceMayHaveButtons("SeeTouchKeypad"), true);
    assert.equal(deviceMayHaveButtons("WallDimmer"), false);
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
    assert.equal(waiting.kind, "ready");
    assert.equal(
      parsePairingMessage({
        Body: { Status: { SigningStatus: "WaitingForButtonPress", Permissions: ["Public"] } }
      }).kind,
      "waiting"
    );

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
