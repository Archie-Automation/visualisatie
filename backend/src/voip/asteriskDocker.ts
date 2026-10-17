import fs from "node:fs";
import http from "node:http";
import { logger } from "../logger";

/**
 * Oude losse Asterisk-container (archie-os-asterisk) weghalen. Asterisk draait
 * nu in de app-container; een achtergebleven container met restart-policy
 * zou poort 5060 kunnen bezetten.
 */
export function removeLegacyAsteriskContainer(): Promise<void> {
  const sock = process.env.DOCKER_SOCK?.trim() || "/var/run/docker.sock";
  if (!fs.existsSync(sock)) return Promise.resolve();
  const name = process.env.ASTERISK_CONTAINER?.trim() || "archie-os-asterisk";
  return new Promise((resolve) => {
    const req = http.request(
      {
        socketPath: sock,
        path: `/containers/${encodeURIComponent(name)}?force=true`,
        method: "DELETE"
      },
      (res) => {
        res.resume();
        if (res.statusCode === 204) {
          logger.info({ name }, "Oude Asterisk-container verwijderd");
        }
        resolve();
      }
    );
    req.on("error", () => resolve());
    req.end();
  });
}
