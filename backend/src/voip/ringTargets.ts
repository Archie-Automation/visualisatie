import type { HouseConfig, IntercomDevice } from "../types";

export interface IntercomRingTarget {
  /** 1-based physical button on the door station. */
  button: number;
  ringGroupId: string;
}

/** Knop 1 = `ringGroupId`; knop 2+ = `ringButtons`. Duplicates dropped. */
export function intercomRingTargets(ic: IntercomDevice): IntercomRingTarget[] {
  const out: IntercomRingTarget[] = [];
  const seen = new Set<string>();
  const add = (raw: string | undefined) => {
    const id = raw?.trim() ?? "";
    if (!id || seen.has(id)) return;
    seen.add(id);
    out.push({ button: out.length + 1, ringGroupId: id });
  };
  add(ic.intercom.ringGroupId);
  for (const b of ic.intercom.ringButtons ?? []) add(b.ringGroupId);
  return out;
}

export function userIdsInVoipGroup(
  cfg: HouseConfig,
  groupId: string
): Set<string> {
  const gid = groupId.trim();
  const users = new Set<string>();
  if (!gid) return users;
  const g = (cfg.voip?.groups ?? []).find((x) => x.id === gid);
  if (!g) return users;
  const byId = new Map((cfg.voip?.endpoints ?? []).map((e) => [e.id, e]));
  for (const mid of g.memberIds) {
    const uid = byId.get(mid)?.userId?.trim();
    if (uid) users.add(uid);
  }
  return users;
}
