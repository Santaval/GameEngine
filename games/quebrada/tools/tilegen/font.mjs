// Shared 3x5 pixel font for signs and name boards (school / colegio / ebais boards, shop sign bands, vida plaques).
// Glyphs are 3 px wide, 5 px tall, with a 1 px gap: advance 4. An unknown character throws (so a typo never silently draws nothing).
// Accents are dropped (JARDIN, DOÑA -> DONA with a compact Ñ kept: the tilde needs the first row).
export const GLYPH_W = 3, GLYPH_H = 5, ADVANCE = 4;
export const GLYPHS = {
  A: ["010", "101", "111", "101", "101"], B: ["110", "101", "110", "101", "110"], C: ["111", "100", "100", "100", "111"],
  D: ["110", "101", "101", "101", "110"], E: ["111", "100", "110", "100", "111"], F: ["111", "100", "110", "100", "100"],
  G: ["111", "100", "101", "101", "111"], H: ["101", "101", "111", "101", "101"], I: ["111", "010", "010", "010", "111"],
  J: ["001", "001", "001", "101", "111"], K: ["101", "101", "110", "101", "101"], L: ["100", "100", "100", "100", "111"],
  M: ["101", "111", "111", "101", "101"], N: ["111", "101", "101", "101", "101"], O: ["111", "101", "101", "101", "111"],
  P: ["111", "101", "111", "100", "100"], Q: ["111", "101", "101", "111", "001"], R: ["110", "101", "110", "101", "101"],
  S: ["111", "100", "111", "001", "111"], T: ["111", "010", "010", "010", "010"], U: ["101", "101", "101", "101", "111"],
  V: ["101", "101", "101", "101", "010"], W: ["101", "101", "111", "111", "101"], X: ["101", "101", "010", "101", "101"],
  Y: ["101", "101", "010", "010", "010"], Z: ["111", "001", "010", "100", "111"],
  "Ñ": ["111", "000", "111", "101", "101"],
  0: ["111", "101", "101", "101", "111"], 1: ["010", "110", "010", "010", "111"], 2: ["111", "001", "111", "100", "111"],
  3: ["111", "001", "111", "001", "111"], 4: ["101", "101", "111", "001", "001"], 5: ["111", "100", "111", "001", "111"],
  6: ["111", "100", "111", "101", "111"], 7: ["111", "001", "001", "010", "010"], 8: ["111", "101", "111", "101", "111"],
  9: ["111", "101", "111", "001", "111"],
  " ": ["000", "000", "000", "000", "000"], ".": ["000", "000", "000", "000", "010"], "-": ["000", "000", "111", "000", "000"], "'": ["010", "010", "000", "000", "000"],
};

/** Uppercase, accents removed (Ñ kept). Throws on a character the font does not have. */
export function normalize(text) {
  const t = String(text).toUpperCase().replace(/Ñ/g, "\u0001").normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/\u0001/g, "Ñ");
  for (const ch of t) if (!(ch in GLYPHS)) throw new Error(`font: unknown char "${ch}" in "${text}"`);
  return t;
}

/** Width in px of a text: n * ADVANCE - 1 (0 for an empty text). */
export function textWidth(text) {
  const n = [...normalize(text)].length;
  return n === 0 ? 0 : n * ADVANCE - 1;
}

/** Plot `text` with its top-left at (x, y) in colour `col`; returns the width drawn. */
export function drawText(f, text, x, y, col) {
  const t = [...normalize(text)];
  t.forEach((ch, i) => GLYPHS[ch].forEach((row, j) => [...row].forEach((v, k) => { if (v === "1") f.px(x + i * ADVANCE + k, y + j, col); })));
  return textWidth(text);
}
