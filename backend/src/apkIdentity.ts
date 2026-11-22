/**
 * versionName + versionCode uit de APK zelf.
 * Het releaselabel en de serverversie liegen als CI achterloopt of een oud
 * bestand op dezelfde naam blijft staan. Android weigert dan terecht.
 */
import zlib from "node:zlib";

export interface ApkIdentity {
  versionName: string;
  versionCode: number;
}

const EOCD = 0x06054b50;
const CEN = 0x02014b50;
const LOC = 0x04034b50;

function findEocd(buf: Buffer): number {
  const min = Math.max(0, buf.length - 22 - 0xffff);
  for (let i = buf.length - 22; i >= min; i--) {
    if (buf.readUInt32LE(i) === EOCD) return i;
  }
  return -1;
}

function zipEntry(buf: Buffer, wanted: string): Buffer | null {
  const eocd = findEocd(buf);
  if (eocd < 0) return null;
  const count = buf.readUInt16LE(eocd + 10);
  let pos = buf.readUInt32LE(eocd + 16);
  for (let i = 0; i < count; i++) {
    if (pos + 46 > buf.length || buf.readUInt32LE(pos) !== CEN) return null;
    const method = buf.readUInt16LE(pos + 10);
    const compSize = buf.readUInt32LE(pos + 20);
    const nameLen = buf.readUInt16LE(pos + 28);
    const extraLen = buf.readUInt16LE(pos + 30);
    const commentLen = buf.readUInt16LE(pos + 32);
    const localOff = buf.readUInt32LE(pos + 42);
    const name = buf.toString("utf8", pos + 46, pos + 46 + nameLen);
    if (name === wanted) {
      if (localOff + 30 > buf.length || buf.readUInt32LE(localOff) !== LOC) return null;
      const localName = buf.readUInt16LE(localOff + 26);
      const localExtra = buf.readUInt16LE(localOff + 28);
      const start = localOff + 30 + localName + localExtra;
      const comp = buf.subarray(start, start + compSize);
      if (method === 0) return Buffer.from(comp);
      if (method === 8) return zlib.inflateRawSync(comp);
      return null;
    }
    pos += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}

function poolStrings(xml: Buffer, chunk: number): { strings: string[]; next: number } | null {
  if (xml.readUInt16LE(chunk) !== 0x0001) return null;
  const headerSize = xml.readUInt16LE(chunk + 2);
  const size = xml.readUInt32LE(chunk + 4);
  const count = xml.readUInt32LE(chunk + 8);
  const flags = xml.readUInt32LE(chunk + 16);
  const stringsStart = xml.readUInt32LE(chunk + 20);
  const utf8 = (flags & 0x100) !== 0;
  const strings: string[] = [];
  for (let i = 0; i < count; i++) {
    const rel = xml.readUInt32LE(chunk + headerSize + i * 4);
    let p = chunk + stringsStart + rel;
    if (utf8) {
      if ((xml[p] & 0x80) !== 0) p += 2;
      else p += 1;
      const n = xml[p];
      const bytes = (n & 0x80) !== 0 ? ((n & 0x7f) << 8) | xml[p + 1] : n;
      const from = (n & 0x80) !== 0 ? p + 2 : p + 1;
      strings.push(xml.toString("utf8", from, from + bytes));
    } else {
      const n = xml.readUInt16LE(p);
      strings.push(xml.toString("utf16le", p + 2, p + 2 + n * 2));
    }
  }
  return { strings, next: chunk + size };
}

function str(strings: string[], index: number): string {
  if (index < 0 || index >= strings.length) return "";
  return strings[index] ?? "";
}

/** Lees identity uit een complete APK-buffer. */
export function readApkIdentity(apk: Buffer): ApkIdentity | null {
  const xml = zipEntry(apk, "AndroidManifest.xml");
  if (!xml || xml.length < 8 || xml.readUInt16LE(0) !== 0x0003) return null;
  const fileHeader = xml.readUInt16LE(2);
  const pool = poolStrings(xml, fileHeader);
  if (!pool) return null;
  let pos = pool.next;
  while (pos + 8 <= xml.length) {
    const type = xml.readUInt16LE(pos);
    const size = xml.readUInt32LE(pos + 4);
    if (size < 8 || pos + size > xml.length) return null;
    if (type === 0x0102) {
      const ext = pos + 16;
      const name = str(pool.strings, xml.readInt32LE(ext + 4));
      const attrStart = xml.readUInt16LE(ext + 8);
      const attrSize = xml.readUInt16LE(ext + 10);
      const attrCount = xml.readUInt16LE(ext + 12);
      if (name === "manifest" && attrSize >= 20) {
        let versionName = "";
        let versionCode = -1;
        const base = ext + attrStart;
        for (let i = 0; i < attrCount; i++) {
          const off = base + i * attrSize;
          const attrName = str(pool.strings, xml.readInt32LE(off + 4));
          const dataType = xml.readUInt8(off + 15);
          const data = xml.readUInt32LE(off + 16);
          if (attrName === "versionCode" && (dataType === 0x10 || dataType === 0x11)) {
            versionCode = data;
          } else if (attrName === "versionName" && dataType === 0x03) {
            versionName = str(pool.strings, data);
          }
        }
        if (versionCode > 0 && versionName.trim()) {
          return { versionName: versionName.trim(), versionCode };
        }
        return null;
      }
    }
    pos += size;
  }
  return null;
}

/** Wat de tablet vergelijkt: `0.2.0+428`, nooit de serverversie. */
export function apkVersionLabel(id: ApkIdentity): string {
  if (id.versionName.includes("+")) return id.versionName;
  return `${id.versionName}+${id.versionCode}`;
}
