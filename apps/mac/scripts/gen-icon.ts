#!/usr/bin/env bun
// Generate Atype icon candidates with a GPT image model through CLIProxyAPI's
// OpenAI-compatible endpoint.
//
//   bun run icon:gen                       # 3 elephant candidates
//   bun run icon:gen owl 4                 # 4 owl candidates (elephant | owl | meerkat)
//   bun run icon:gen elephant 2 --ref ~/Desktop/tako.png
//                                          # match a reference icon's style (images/edits)
//   bun run icon:gen --prompt "a red panda holding a pen"
//
// Environment:
//   CLIPROXY_BASE_URL  default http://127.0.0.1:8317
//   CLIPROXY_API_KEY   one of the api-keys in your CLIProxyAPI config (optional if none)
//   ATYPE_ICON_MODEL   default gpt-image-2
//   ATYPE_ICON_OUT     default ~/Desktop/atype-icons
//
// Then pick one:  bun run icon:set ~/Desktop/atype-icons/<file>.png

import { mkdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";
import { SUBJECTS, buildPrompt } from "./icon-prompts";

type ImageResponse = { data?: { b64_json?: string; url?: string }[] };

const args = process.argv.slice(2);
const flag = (name: string): string | undefined => {
  const i = args.indexOf(name);
  if (i === -1) return undefined;
  const value = args[i + 1];
  args.splice(i, 2);
  return value;
};

const customPrompt = flag("--prompt");
const refPath = flag("--ref");
const animal = (args[0] ?? "elephant").toLowerCase();
const count = Math.max(1, Math.min(8, Number(args[1] ?? 3) || 3));

const subject = customPrompt ? `Subject: ${customPrompt}.` : SUBJECTS[animal];
if (!subject) {
  console.error(
    `不認識「${animal}」。可用：${Object.keys(SUBJECTS).join("、")}，或用 --prompt 自己寫。`,
  );
  process.exit(2);
}

const base = (process.env.CLIPROXY_BASE_URL ?? "http://127.0.0.1:8317").replace(
  /\/+$/,
  "",
);
const apiKey = process.env.CLIPROXY_API_KEY ?? "";
const model = process.env.ATYPE_ICON_MODEL ?? "gpt-image-2";
const outDir = resolve(
  (
    process.env.ATYPE_ICON_OUT ?? join(homedir(), "Desktop", "atype-icons")
  ).replace(/^~(?=\/)/, homedir()),
);
const label = customPrompt ? "custom" : animal;

let prompt = buildPrompt(subject);
if (refPath) {
  prompt =
    "Redraw as a new icon in exactly the same illustration style, line weight, shading and " +
    `background treatment as the reference image, but with a different subject. ${prompt}`;
}

const headers: Record<string, string> = apiKey
  ? { Authorization: `Bearer ${apiKey}` }
  : {};

async function requestOnce(withQuality: boolean): Promise<Response> {
  if (refPath) {
    const form = new FormData();
    form.append("model", model);
    form.append("prompt", prompt);
    form.append("size", "1024x1024");
    if (withQuality) form.append("quality", "high");
    form.append(
      "image",
      Bun.file(resolve(refPath.replace(/^~(?=\/)/, homedir()))),
      basename(refPath),
    );
    return fetch(`${base}/v1/images/edits`, {
      method: "POST",
      headers,
      body: form,
    });
  }
  const body: Record<string, unknown> = {
    model,
    prompt,
    n: 1,
    size: "1024x1024",
  };
  if (withQuality) body.quality = "high";
  return fetch(`${base}/v1/images/generations`, {
    method: "POST",
    headers: { ...headers, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

async function generateOne(): Promise<Buffer> {
  let res = await requestOnce(true);
  if (res.status === 400) {
    // Some backends reject `quality`; retry once without it.
    res = await requestOnce(false);
  }
  if (!res.ok) {
    const text = (await res.text()).slice(0, 600);
    throw new Error(`HTTP ${res.status}: ${text}`);
  }
  const json = (await res.json()) as ImageResponse;
  const item = json.data?.[0];
  if (item?.b64_json) return Buffer.from(item.b64_json, "base64");
  if (item?.url) {
    const img = await fetch(item.url);
    if (!img.ok) throw new Error(`下載圖片失敗：HTTP ${img.status}`);
    return Buffer.from(await img.arrayBuffer());
  }
  throw new Error(`回應裡沒有圖片：${JSON.stringify(json).slice(0, 300)}`);
}

mkdirSync(outDir, { recursive: true });
console.log(`用 ${model}（${base}）產生 ${count} 張「${label}」候選圖…`);

const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
const saved: string[] = [];
for (let i = 1; i <= count; i++) {
  try {
    const png = await generateOne();
    const file = join(outDir, `atype-${label}-${stamp}-${i}.png`);
    writeFileSync(file, png);
    saved.push(file);
    console.log(`  ✓ ${file}`);
  } catch (e) {
    console.error(`  ✗ 第 ${i} 張失敗：${(e as Error).message}`);
    if (i === 1) {
      console.error(
        [
          "",
          "檢查：",
          `  1. CLIProxyAPI 有在跑：curl ${base}/v1/models${apiKey ? ' -H "Authorization: Bearer $CLIPROXY_API_KEY"' : ""}`,
          "  2. CLIPROXY_API_KEY 是設定檔 api-keys 裡的其中一把",
          `  3. 模型名稱對：ATYPE_ICON_MODEL=${model}（可改成 /v1/models 列出的圖像模型）`,
        ].join("\n"),
      );
      process.exit(1);
    }
  }
}

if (saved.length > 0) {
  console.log(`\n在 Finder 打開：open "${outDir}"`);
  console.log(`選好一張後：bun run icon:set "${saved[0]}"`);
}
