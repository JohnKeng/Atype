#!/usr/bin/env bun
// Turn a square illustration into a macOS app icon: cover-crop to the
// rounded tile (824px on a 1024px canvas, Apple's icon grid), cut the corners,
// and add the soft drop shadow macOS icons carry.
//
//   bun scripts/make-icon.ts <input image> <output.png>
//   bun scripts/make-icon.ts --on-grid <input image> <output.png>
//
// --on-grid: the image is already a macOS-style icon laid out on Apple's grid
// (rounded tile at 100..924 of 1024) but flattened onto an opaque background,
// e.g. a JPG export. The tile is cut out in place instead of cover-cropping
// the whole picture, so its own rounded edge is not framed a second time.

import sharp from "sharp";

const argv = process.argv.slice(2);
const onGrid = argv[0] === "--on-grid";
const [input, output] = onGrid ? argv.slice(1) : argv;
if (!input || !output) {
  console.error(
    "用法：bun scripts/make-icon.ts [--on-grid] <輸入圖片> <輸出.png>",
  );
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

const source = onGrid
  ? sharp(
      await sharp(input)
        .resize(SIZE, SIZE, { fit: "fill" })
        .extract({ left: INSET, top: INSET, width: BODY, height: BODY })
        .toBuffer(),
    )
  : sharp(input).resize(BODY, BODY, { fit: "cover", position: "centre" });

const body = await source
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
