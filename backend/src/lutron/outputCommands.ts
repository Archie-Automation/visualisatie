/**
 * Lutron Integration Protocol — #OUTPUT (Homeworks / Athena / QS via telnet).
 * Zie Lutron documentatie: action 1 = set level, 2 = raise, 3 = lower, 4 = stop, 6 = pulse.
 * Parameters voor actie 1: level (0–100), optioneel fade (s), delay (s).
 */

export function clampPercent(n: number): number {
  return Math.max(0, Math.min(100, Math.round(n)));
}

/** Set level/position 0–100. Fade en delay in seconden (geheel), conform voorbeeld #OUTPUT,2,1,70,4,2 */
export function buildOutputSetLevel(
  integrationId: number,
  percent: number,
  fadeSeconds?: number,
  delaySeconds = 0
): string {
  const id = Math.max(1, Math.round(integrationId));
  const lv = clampPercent(percent);
  const fade =
    fadeSeconds != null && fadeSeconds > 0 ? Math.min(14_400, Math.round(fadeSeconds)) : undefined;
  if (fade != null) {
    return `#OUTPUT,${id},1,${lv},${fade},${delaySeconds}`;
  }
  return `#OUTPUT,${id},1,${lv}`;
}

export function buildOutputRaise(integrationId: number): string {
  const id = Math.max(1, Math.round(integrationId));
  return `#OUTPUT,${id},2`;
}

export function buildOutputLower(integrationId: number): string {
  const id = Math.max(1, Math.round(integrationId));
  return `#OUTPUT,${id},3`;
}

export function buildOutputStop(integrationId: number): string {
  const id = Math.max(1, Math.round(integrationId));
  return `#OUTPUT,${id},4`;
}
