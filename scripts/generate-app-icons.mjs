// Rebuild the home-screen icons from the same vector used by the in-app brand.
// Run: node scripts/generate-app-icons.mjs
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { deflateSync } from 'node:zlib';

const publicDir = new URL('../public/', import.meta.url);
const mark = await readFile(new URL('ritm-mark.svg', publicDir), 'utf8');
const coordinates = mark
  .match(/d="([^"]+)"/)[1]
  .match(/\d+(?:\.\d+)?/g)
  .map(Number);
const points = [[coordinates[0], coordinates[1]]];
let start = points[0];
for (let offset = 2; offset < coordinates.length; offset += 6) {
  const [cx1, cy1, cx2, cy2, ex, ey] = coordinates.slice(offset, offset + 6);
  for (let step = 1; step <= 32; step++) {
    const t = step / 32;
    const u = 1 - t;
    points.push([
      u ** 3 * start[0] + 3 * u ** 2 * t * cx1 + 3 * u * t ** 2 * cx2 + t ** 3 * ex,
      u ** 3 * start[1] + 3 * u ** 2 * t * cy1 + 3 * u * t ** 2 * cy2 + t ** 3 * ey,
    ]);
  }
  start = [ex, ey];
}

const crcTable = Array.from({ length: 256 }, (_, value) => {
  for (let bit = 0; bit < 8; bit++) value = value & 1 ? 0xedb88320 ^ (value >>> 1) : value >>> 1;
  return value >>> 0;
});
function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  let crc = 0xffffffff;
  for (const byte of body) crc = crcTable[(crc ^ byte) & 255] ^ (crc >>> 8);
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE((crc ^ 0xffffffff) >>> 0);
  return Buffer.concat([length, body, checksum]);
}
function render(size) {
  const samples = 4;
  const width = size * samples;
  const accumulation = new Float64Array(size * size * 3);
  const light = [229, 215, 255];
  const lavender = [196, 171, 235];
  const ink = [52, 35, 76];
  for (let y = 0; y < width; y++) {
    const vectorY = ((y + 0.5) / width) * 64;
    const intersections = [];
    for (let i = 0; i < points.length - 1; i++) {
      const [x1, y1] = points[i];
      const [x2, y2] = points[i + 1];
      if ((y1 <= vectorY && y2 > vectorY) || (y2 <= vectorY && y1 > vectorY)) {
        intersections.push(x1 + ((vectorY - y1) * (x2 - x1)) / (y2 - y1));
      }
    }
    intersections.sort((a, b) => a - b);
    let segment = 0;
    for (let x = 0; x < width; x++) {
      const vectorX = ((x + 0.5) / width) * 64;
      while (segment < intersections.length && vectorX > intersections[segment]) segment++;
      const inside = segment % 2 === 1;
      const fade = (x + y + 1) / (width * 2);
      const offset = (Math.floor(y / samples) * size + Math.floor(x / samples)) * 3;
      for (let c = 0; c < 3; c++) {
        accumulation[offset + c] += inside ? ink[c] : light[c] + (lavender[c] - light[c]) * fade;
      }
    }
  }
  const pixels = Buffer.alloc(size * (1 + size * 3));
  for (let y = 0; y < size; y++) {
    const offset = y * (1 + size * 3);
    for (let x = 0; x < size * 3; x++) {
      pixels[offset + 1 + x] = Math.round(accumulation[y * size * 3 + x] / samples ** 2);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header[8] = 8;
  header[9] = 2; // RGB, fully opaque: the launcher applies its own icon mask.
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT', deflateSync(pixels)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}
await mkdir(new URL('icons/', publicDir), { recursive: true });
for (const size of [180, 192, 512]) {
  await writeFile(new URL(`icons/ritm-${size}.png`, publicDir), render(size));
  process.stdout.write(`Ritm icon: ${size} × ${size}\n`);
}
