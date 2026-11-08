/** Zet go2rtc-playlistregels om naar de backend-proxy.
 *  De master is relatief (`hls/playlist.m3u8?id=`), de segmenten ook
 *  (`segment.ts?id=&n=`). Zonder die query is het bestand weg. */

export function rewriteHlsPlaylist(
  body: string,
  camId: string,
  clientBase: string,
  playlistUrl: string
): string {
  const segBase = `${clientBase.replace(/\/+$/, "")}/api/cameras/${camId}/hls-seg`;
  let base: URL;
  try {
    base = new URL(playlistUrl);
  } catch {
    return body;
  }
  const apiPrefix = `${base.origin}/api/`;

  const mapRef = (ref: string): string => {
    let abs: URL;
    try {
      abs = new URL(ref, base);
    } catch {
      return ref;
    }
    const href = abs.toString();
    if (!href.startsWith(apiPrefix)) return ref;
    return `${segBase}/${href.slice(apiPrefix.length)}`;
  };

  return body
    .split("\n")
    .map((line) => {
      const t = line.trim();
      if (!t) return line;
      if (t.startsWith("#")) {
        return line.replace(
          /URI="([^"]+)"/g,
          (_m, uri: string) => `URI="${mapRef(uri)}"`
        );
      }
      return mapRef(t);
    })
    .join("\n");
}
