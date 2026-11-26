#pragma once

// Orden por Y para dibujar tiles altos y sprites mezclados (top-down). Puro, sin SDL.

#include <cmath>

namespace ysort {

// Ante igual sortY el tile va antes que el sprite
constexpr int KindTile = 0;
constexpr int KindSprite = 1;

struct Item {
  int sortY = 0;
  int kind = KindSprite;
  int seq = 0;    // orden de insercion: desempata de forma estable
  int index = 0;  // posicion en la lista de origen (tiles o sprites)
};

inline bool less(const Item& a, const Item& b) {
  if (a.sortY != b.sortY) return a.sortY < b.sortY;
  if (a.kind != b.kind) return a.kind < b.kind;
  return a.seq < b.seq;
}

// Y de los "pies" de un sprite. sortOffset < 0: borde inferior del frame actual;
// si no, px desde el borde superior del frame (se multiplica por la escala)
inline int spriteSortY(double posY, int sortOffset, int frameH, double scaleY) {
  const double off = sortOffset < 0 ? frameH : sortOffset;
  return static_cast<int>(std::floor(posY + off * scaleY));
}

}  // namespace ysort
