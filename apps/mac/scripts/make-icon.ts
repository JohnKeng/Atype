#!/usr/bin/env bun
// Turn a square illustration into a macOS app icon: cover-crop to the
// rounded tile (824px on a 1024px canvas, Apple's icon grid), cut the corners,
// and add the soft drop shadow macOS icons carry.
//
//   bun scripts/make-icon.ts <input image> <output.png>

import sharp from "sharp";

const [input, output] = process.argv.slice(2);
if (!input || !output) {
  console.error("用法：bun scripts/make-icon.ts <輸入圖片> <輸出.png>");
  process.exit(2);
}

const SIZE = 1024;
const INSET = 100;
const BODY = SIZE - INSET * 2; // 824
const RADIUS = 185;

const tileMask = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${BODY}" height="${BODY}">` +
    `<rect width="${BODY}" height="${BODY}" rx="${RADIUS}" ry="${RADIUS}" fill="#fff"/></svg>`,
);

const shadowSvg = Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" width="${SIZE}" height="${SIZE}">` +
    `<rect x="${INSET}" y="${INSET + 12}" width="${BODY}" height="${BODY}" rx="${RADIUS}" ` +
    `fill="#000" fill-opacity="0.28"/></svg>`,
);

const body = await sharp(input)
  .resize(BODY, BODY, { fit: "cover", position: "centre" })
  .ensureAlpha()
  .composite([{ input: tileMask, blend: "dest-in" }])
  .png()
  .toBuffer();

const shadow = await sharp(shadowSvg).blur(16).png().toBuffer();

await sharp({
  create: {
    width: SIZE,
    height: SIZE,
    channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  },
})
  .composite([{ input: shadow }, { input: body, left: INSET, top: INSET }])
  .png()
  .toFile(output);

console.log(`已輸出 ${output}`);
