// Writes the small files the upload steps use: a valid PNG and a stub MP4.
// (The backend recognises media by its magic bytes; the MP4 is not playable, which the tests do not need.)
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const dir = process.env.FIXTURE_DIR || path.join(__dirname, 'fixtures');
fs.mkdirSync(dir, { recursive: true });

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
const w = 64, h = 64;
const rows = [];
for (let y = 0; y < h; y++) {
  const row = Buffer.alloc(1 + w * 3);
  for (let x = 0; x < w; x++) { row[1 + x * 3] = (x * 4) % 256; row[2 + x * 3] = (y * 4) % 256; row[3 + x * 3] = 160; }
  rows.push(row);
}
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 2;
const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0)),
]);
fs.writeFileSync(path.join(dir, 'test.png'), png);

const ftyp = Buffer.concat([Buffer.from([0, 0, 0, 24]), Buffer.from('ftypisom'), Buffer.from([0, 0, 2, 0]), Buffer.from('isomiso2')]);
const mdat = Buffer.concat([Buffer.from([0, 0, 8, 8]), Buffer.from('mdat'), Buffer.alloc(2048)]);
fs.writeFileSync(path.join(dir, 'test.mp4'), Buffer.concat([ftyp, mdat]));
console.log('fixtures written to', dir);
