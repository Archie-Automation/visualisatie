import fs from "node:fs";
import http from "node:http";
import { logger } from "../logger";

export type AsteriskContainerState = "started" | "running" | "absent" | "no-socket";

/**
 * Start de Asterisk-container als die bestaat maar niet draait.
 * De socket is alleen aanwezig in de NUC-image (docker-compose mount).
 */
export function ensureAsteriskContainer(): Promise<AsteriskContainerState> {
  const sock = process.env.DOCKER_SOCK?.trim() || "/var/run/docker.sock";
  if (!fs.existsSync(sock)) return Promise.resolve("no-socket");
  const name = process.env.ASTERISK_CONTAINER?.trim() || "archie-os-asterisk";
  return new Promise((resolve) => {
    const req = http.request(
      {
        socketPath: sock,
        path: `/containers/${encodeURIComponent(name)}/start`,
        method: "POST"
      },
      (res) => {
        res.resume();
        const code = res.statusCode ?? 0;
        if (code === 204) {
          logger.info({ name }, "Asterisk-container gestart");
          resolve("started");
          return;
        }
        if (code === 304) {
          resolve("running");
          return;
        }
        if (code === 404) {
          logger.warn(
            { name },
            "Asterisk-container bestaat niet. Op de NUC: docker compose up -d asterisk"
          );
          resolve("absent");
          return;
        }
        logger.warn({ name, code }, "Asterisk-container starten mislukt");
        resolve("absent");
      }
    );
    req.on("error", (err) => {
      logger.warn({ err, sock }, "Docker-socket niet bruikbaar");
      resolve("no-socket");
    });
    req.end();
  });
}
