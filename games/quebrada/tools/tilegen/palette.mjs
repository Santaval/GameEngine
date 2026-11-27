// Colours per material. Mid-tone on purpose: the lighting layer darkens the map at night,
// so nothing here is darker than about #1c1a18.
import { rgb } from "./draw.mjs";

const P = (o) => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, rgb(v)]));

export const C = {
  zacate: P({ base: "#55903d", mid: "#4b8436", dark: "#3c6f2e", light: "#74ad52", hi: "#8cc063", dry: "#a39a4f", dryDark: "#857d3c", tall: "#2f6a2b" }),
  soil: P({ base: "#7d5b3d", light: "#94704b", dark: "#654730", clod: "#5a3f2a", lip: "#a98254" }),
  lastre: P({ base: "#a88f6a", light: "#bfa57e", dark: "#8a7352", stone: "#cfc4b0", stoneDark: "#7d7466", rut: "#8f7955", wet: "#6f5d44" }),
  asphalt: P({ base: "#5d5f66", light: "#6b6d74", dark: "#4d4f56", crack: "#35373c", yellow: "#d9b630", white: "#d8d8d0", patch: "#55575d" }),
  concrete: P({ base: "#b4b1a8", light: "#c6c3ba", dark: "#97948c", joint: "#827f78", stain: "#a39f95", chan: "#74726c", chanDark: "#5d5b57", water: "#4f6a6a" }),
  paver: P({ grey: "#9b9188", greyLight: "#aca298", joint: "#6c645d", red: "#a8694f", redLight: "#ba7b60" }),
  river: P({ base: "#3f7f8c", mid: "#4a8c99", light: "#69a9b3", dark: "#2f6270", foam: "#cfe6e6", mud: "#6b5a43", mudDark: "#52443a", stone: "#8c8c86", stoneDark: "#62625e" }),
  wood: P({ base: "#9c6b3f", light: "#b58553", dark: "#6f4a2a", gap: "#47311f", grain: "#8b5c34" }),
  wire: P({ metal: "#cfd2d6", dark: "#7a7f86", barb: "#e4e6e8", post: "#8c6a45", postDark: "#5f4730", postLight: "#a98558", cap: "#6b6e73" }),
  coffee: P({ leaf: "#2f7a33", leafDark: "#20562a", leafLight: "#4c9b45", red: "#c1272f", green: "#a8c94f", stem: "#5a4630" }),
  plantain: P({ leaf: "#6bb03a", light: "#93cf55", dark: "#4a8a2a", vein: "#b9e07b", stem: "#8fa84f", stemDark: "#66803a", fruit: "#d9c44a", fruitDark: "#a39430", flower: "#8a3d4f" }),
  guanacaste: P({ base: "#3b8040", dark: "#285f33", light: "#5da553", hi: "#7bc069", deep: "#1f4a2a", bark: "#7a6a56", barkDark: "#54483a", barkLight: "#948470" }),
  monte: P({ base: "#2f6c3a", dark: "#1f4d2c", light: "#4d8f50", hi: "#6aae5f", deep: "#183b25", bark: "#6b5848", barkDark: "#493c31" }),
  palm: P({ frond: "#4f9a3f", light: "#7ec259", dark: "#33702c", trunk: "#9a8465", trunkDark: "#6d5b44", trunkLight: "#b39d7c" }),
  post: P({ base: "#aaa79e", light: "#c2bfb5", dark: "#84817a", lamp: "#f1e6a8", lampDim: "#c8bd82", arm: "#6e6c68", cable: "#34312f" }),
  hedge: P({ base: "#3a7a34", dark: "#2a5a2a", light: "#5a9c46" }),
  rock: P({ base: "#8e8c86", light: "#adaba3", dark: "#64625d" }),
  flower: P({ pink: "#d4458a", pinkLight: "#ee7ab1", white: "#f1efe4", yellow: "#f0d34a", purple: "#8d5bb5" }),
  shadow: [0, 0, 0, 70],
};
