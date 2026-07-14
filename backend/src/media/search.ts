// Thin aggregator over the per-brand driver search. Each driver knows how to
// reach the services the customer linked on that device (Sonos: favourites /
// playlists / local library; Bluesound: the services linked in the BluOS app),
// and returns already-normalized `MediaSearchSection[]`. This module only caps
// the result set and drops empty sections so the UI stays tidy.

import type { MediaSearchSection } from "../types";
import type { BluesoundDriver } from "./bluesound";
import type { SonosDriver } from "./sonos";

const MAX_RESULTS_PER_SECTION = 20;

type SearchableDriver = SonosDriver | BluesoundDriver;

export async function searchMediaDevice(
  driver: SearchableDriver,
  query: string
): Promise<MediaSearchSection[]> {
  const q = query.trim();
  if (!q) return [];
  const sections = await driver.search(q);
  return sections
    .map((s) => ({
      title: s.title,
      results: s.results.slice(0, MAX_RESULTS_PER_SECTION)
    }))
    .filter((s) => s.results.length > 0);
}
