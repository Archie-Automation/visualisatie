import assert from "node:assert/strict";
import net from "node:net";
import { describe, it } from "node:test";
import { AmiClient } from "./ami";

function fakeAsterisk(secret: string): Promise<{ port: number; close: () => void }> {
  return new Promise((resolve) => {
    const server = net.createServer((sock) => {
      sock.write("Asterisk Call Manager/9.0.0\r\n");
      let buf = "";
      sock.on("data", (d) => {
        buf += d.toString();
        const idx = buf.indexOf("\r\n\r\n");
        if (idx < 0) return;
        const block = buf.slice(0, idx);
        buf = buf.slice(idx + 4);
        const id = /ActionID: (\S+)/.exec(block)?.[1] ?? "";
        const ok = block.includes(`Secret: ${secret}`);
        sock.write(
          ok
            ? `Response: Success\r\nActionID: ${id}\r\nMessage: Authentication accepted\r\n\r\n`
            : `Response: Error\r\nActionID: ${id}\r\nMessage: Authentication failed\r\n\r\n`
        );
      });
    });
    server.listen(0, "127.0.0.1", () => {
      const port = (server.address() as net.AddressInfo).port;
      resolve({ port, close: () => server.close() });
    });
  });
}

describe("AmiClient", () => {
  it("logs in after the single-line Asterisk greeting", async () => {
    const srv = await fakeAsterisk("geheim");
    const c = new AmiClient("127.0.0.1", srv.port);
    try {
      await c.connect("archie", "geheim", 2000);
      assert.equal(c.connected, true);
    } finally {
      c.close();
      srv.close();
    }
  });

  it("rejects a wrong secret", async () => {
    const srv = await fakeAsterisk("geheim");
    const c = new AmiClient("127.0.0.1", srv.port);
    try {
      await assert.rejects(c.connect("archie", "fout", 2000), /Authentication failed/);
    } finally {
      c.close();
      srv.close();
    }
  });
});
