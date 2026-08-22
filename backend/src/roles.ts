/** Canonical app roles. Stored `admin` is treated as installer. */
export type AppRole = "installer" | "superuser" | "user";

export function normalizeRole(role: string | undefined | null): AppRole {
  const r = (role ?? "").trim().toLowerCase();
  if (r === "admin" || r === "installer") return "installer";
  if (r === "superuser" || r === "super_user" || r === "super-user") {
    return "superuser";
  }
  return "user";
}

export function isInstallerRole(role: string | undefined | null): boolean {
  return normalizeRole(role) === "installer";
}

export function isSuperUserRole(role: string | undefined | null): boolean {
  return normalizeRole(role) === "superuser";
}

export function isStaffRole(role: string | undefined | null): boolean {
  const n = normalizeRole(role);
  return n === "installer" || n === "superuser";
}

export function isUserEnabled(user: { enabled?: boolean } | undefined): boolean {
  return user?.enabled !== false;
}
