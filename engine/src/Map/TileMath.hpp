#pragma once

// Matematica pura del dibujado de tile maps: rango de celdas visibles, frame de
// una animacion y volteo de gids. Sin SDL ni sol, para poder probarla en tests.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include "TmxLoader.hpp"

namespace tilemap {

// Division entera que redondea hacia -infinito (la de C++ redondea hacia 0)
inline int floorDiv(int a, int b) {
  int q = a / b;
  if ((a % b != 0) && ((a < 0) != (b < 0))) q--;
  return q;
}

// Rango de celdas [col0, col1) x [row0, row1) (semiabierto)
struct TileRange {
  int col0 = 0, row0 = 0, col1 = 0, row1 = 0;
  bool empty() const { return col1 <= col0 || row1 <= row0; }
};

// Celdas que toca la camara. origin es la esquina de la celda (0,0) en el mundo
// (offset de la capa). extraW/extraH ensanchan el rango por la izquierda y por
// abajo para tiles mas grandes que la rejilla (se dibujan alineados abajo).
inline TileRange visibleTiles(int camX, int camY, int camW, int camH, int originX, int originY,
                              int tileW, int tileH, int cols, int rows, int extraW, int extraH) {
  TileRange r;
  if (tileW <= 0 || tileH <= 0 || cols <= 0 || rows <= 0) return r;
  r.col0 = floorDiv(camX - originX - extraW, tileW);
  r.col1 = floorDiv(camX + camW - 1 - originX, tileW) + 1;
  r.row0 = floorDiv(camY - originY, tileH);
  r.row1 = floorDiv(camY + camH - 1 - originY + extraH, tileH) + 1;
  r.col0 = std::max(r.col0, 0);
  r.row0 = std::max(r.row0, 0);
  r.col1 = std::min(r.col1, cols);
  r.row1 = std::min(r.row1, rows);
  return r;
}

// Indice del frame de una animacion en el instante clockMs. Duracion <= 0 se
// trata como 100 ms. Devuelve 0 si no hay frames.
inline int animFrame(const std::vector<int>& durationsMs, double clockMs) {
  if (durationsMs.empty()) return 0;
  double total = 0;
  for (int d : durationsMs) total += (d <= 0 ? 100 : d);
  double t = std::fmod(clockMs, total);
  if (t < 0) t += total;
  double acc = 0;
  for (size_t i = 0; i < durationsMs.size(); i++) {
    acc += (durationsMs[i] <= 0 ? 100 : durationsMs[i]);
    if (t < acc) return static_cast<int>(i);
  }
  return static_cast<int>(durationsMs.size()) - 1;
}

// Equivalente en SDL (voltear y despues girar en sentido horario) de los flags
// de Tiled (transponer si D, luego H, luego V)
struct TileTransform {
  double angle = 0;
  bool flipH = false;
  bool flipV = false;
};

inline TileTransform flipTransform(uint32_t rawGid) {
  const bool h = (rawGid & tmx::FLIP_H) != 0;
  const bool v = (rawGid & tmx::FLIP_V) != 0;
  const bool d = (rawGid & tmx::FLIP_D) != 0;
  TileTransform t;
  if (!d) {
    t.flipH = h;
    t.flipV = v;
    return t;
  }
  if (!h && !v) {
    t.angle = 90;
    t.flipV = true;
  } else if (h && !v) {
    t.angle = 90;
  } else if (!h && v) {
    t.angle = 270;
  } else {
    t.angle = 90;
    t.flipH = true;
  }
  return t;
}

}  // namespace tilemap
