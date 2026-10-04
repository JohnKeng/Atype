// Prompts for Atype's app icon, written to match John's existing icon series
// (LogScope squirrel, Tako octopus, Omi Ear bat): one chibi animal mascot,
// thick dark-brown outlines, soft shading, blush, pastel background.
//
// The background is asked to fill the whole square: scripts/make-icon.ts cuts
// the macOS rounded tile and adds the shadow, so every candidate ends up with
// the same shape as the rest of the series.

export const STYLE = [
  "App icon artwork for a cohesive kawaii mascot series.",
  "A single cute chibi animal character, thick rounded dark-brown outlines (#4A2F22),",
  "soft cel shading with gentle gradients, rosy blush on the cheeks, small shiny friendly eyes,",
  "a gentle smile, cozy and warm mood, clean high-quality vector-like illustration,",
  "a subtle soft shadow on the ground under the character.",
  "Centered composition with comfortable padding; the character fills about 70% of the canvas.",
  "The background is one flat soft pastel color filling the entire square canvas edge to edge:",
  "no rounded corners, no frame, no border, no text, no letters, no logo, no watermark.",
].join(" ");

export const SUBJECTS: Record<string, string> = {
  elephant: [
    "Subject: a chubby baby Asian elephant, like the elephants at ARTIS zoo in Amsterdam,",
    "with big round floppy ears (soft pink inside) and warm grey-brown skin,",
    "sitting and happily holding a small golden vintage microphone in its curled trunk.",
    "A tiny cream speech bubble with three short golden lines floats beside it.",
    "Accent colors: chrysanthemum gold (#E3A008, #F5C443).",
    "Background: warm cream (#FBF3E4).",
  ].join(" "),
  owl: [
    "Subject: a round fluffy burrowing owl, like the ones at ARTIS zoo in Amsterdam,",
    "with big golden eyes, wearing small cozy headphones and holding a tiny pencil,",
    "standing on a little open notebook.",
    "Accent colors: chrysanthemum gold (#E3A008, #F5C443).",
    "Background: pale butter yellow (#FBF1D6).",
  ].join(" "),
  meerkat: [
    "Subject: a cheerful meerkat, like the ones at ARTIS zoo in Amsterdam,",
    "standing upright on its hind legs with one paw cupped behind its ear as if listening carefully,",
    "sandy golden fur and a tiny chrysanthemum flower tucked behind the other ear.",
    "Accent colors: chrysanthemum gold (#E3A008, #F5C443).",
    "Background: soft beige (#F3EBDD).",
  ].join(" "),
};

export function buildPrompt(subject: string): string {
  return `${STYLE} ${subject}`;
}
