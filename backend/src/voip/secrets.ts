import { randomBytes } from "node:crypto";

export function randomSipPassword(): string {
  return randomBytes(12).toString("base64url");
}

export function randomAmiSecret(): string {
  return randomBytes(18).toString("base64url");
}

/** Asterisk conf: no newlines, semicolons, or closing brackets. */
export function astSafe(value: string): string {
  return value.replace(/[\r\n;[\]]/g, "").trim();
}
