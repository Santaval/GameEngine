#pragma once

#include <algorithm>
#include <cmath>
#include <vector>

#include "Geometry.hpp"
#include "StaticWorld.hpp"

// Movimiento de una caja contra solidos con barrido exacto por ejes (primero X
// y luego Y): se desliza por las paredes y no atraviesa nada a ninguna
// velocidad ni dt (el barrido cubre todo el recorrido, sin subpasos).

namespace physics {

enum Contact : unsigned {
  CONTACT_LEFT = 1,
  CONTACT_RIGHT = 2,
  CONTACT_TOP = 4,
  CONTACT_BOTTOM = 8
};

struct SlideResult {
  // Desplazamiento total a sumar a la posicion (incluye el empuje de
  // depenetracion). Las componentes bloqueadas ya vienen recortadas.
  double dx = 0.0;
  double dy = 0.0;
  unsigned contacts = 0;      // bits Contact: lados que bloquearon el movimiento
  bool depenetrated = false;  // true si la caja empezo dentro de un solido
};

namespace detail {

template <typename F>
void forEachSolid(const StaticWorld& world, const std::vector<Aabb>* extra,
  const Aabb& region, F&& f) {
  world.query(region, f);
  if (extra) {
    for (const Aabb& s : *extra) {
      if (aabbOverlap(s, region)) f(s);
    }
  }
}

// Saca la caja de los solidos en los que esta metida (por ejemplo tras un
// teletransporte o una correccion de red). Empuja por el eje de menor
// penetracion; hasta 4 iteraciones.
inline bool depenetrate(Aabb& box, double& totalX, double& totalY,
  const StaticWorld& world, const std::vector<Aabb>* extra) {
  bool moved = false;

  for (int iter = 0; iter < 4; iter++) {
    double bestPen = 0.0;
    double pushX = 0.0, pushY = 0.0;
    bool found = false;

    forEachSolid(world, extra, box, [&](const Aabb& s) {
      const double penX = std::min(box.right(), s.right()) - std::max(box.x, s.x);
      const double penY = std::min(box.bottom(), s.bottom()) - std::max(box.y, s.y);
      const double boxCx = box.x + box.w * 0.5, boxCy = box.y + box.h * 0.5;
      const double sCx = s.x + s.w * 0.5, sCy = s.y + s.h * 0.5;

      double pen, px = 0.0, py = 0.0;
      if (penX <= penY) {
        pen = penX;
        px = boxCx < sCx ? -penX : penX;
      } else {
        pen = penY;
        py = boxCy < sCy ? -penY : penY;
      }
      if (!found || pen < bestPen) {
        found = true;
        bestPen = pen;
        pushX = px;
        pushY = py;
      }
    });

    if (!found) break;
    box.x += pushX;
    box.y += pushY;
    totalX += pushX;
    totalY += pushY;
    moved = true;
  }

  return moved;
}

}  // namespace detail

inline SlideResult moveAndSlide(Aabb box, double dx, double dy, const StaticWorld& world,
  const std::vector<Aabb>* extraSolids = nullptr) {
  SlideResult result;
  if (!std::isfinite(dx)) dx = 0.0;
  if (!std::isfinite(dy)) dy = 0.0;

  double totalX = 0.0, totalY = 0.0;
  result.depenetrated = detail::depenetrate(box, totalX, totalY, world, extraSolids);

  // Eje X: se recorta contra todos los solidos de la region barrida
  if (dx != 0.0) {
    Aabb region = { std::min(box.x, box.x + dx), box.y, box.w + std::fabs(dx), box.h };
    double allowed = dx;

    detail::forEachSolid(world, extraSolids, region, [&](const Aabb& s) {
      // Solo cuenta si solapa en Y (mas que SKIN)
      const double overlapY = std::min(box.bottom(), s.bottom()) - std::max(box.y, s.y);
      if (overlapY <= SKIN) return;

      if (dx > 0.0) {
        if (s.x < box.right() - SKIN) return;  // detras o dentro: no bloquea
        allowed = std::min(allowed, std::max(0.0, s.x - box.right()));
      } else {
        if (s.right() > box.x + SKIN) return;
        allowed = std::max(allowed, std::min(0.0, s.right() - box.x));
      }
    });

    if (allowed != dx) {
      result.contacts |= dx > 0.0 ? CONTACT_RIGHT : CONTACT_LEFT;
      dx = allowed;
    }
    box.x += dx;
    totalX += dx;
  }

  // Eje Y: con la X ya movida
  if (dy != 0.0) {
    Aabb region = { box.x, std::min(box.y, box.y + dy), box.w, box.h + std::fabs(dy) };
    double allowed = dy;

    detail::forEachSolid(world, extraSolids, region, [&](const Aabb& s) {
      const double overlapX = std::min(box.right(), s.right()) - std::max(box.x, s.x);
      if (overlapX <= SKIN) return;

      if (dy > 0.0) {
        if (s.y < box.bottom() - SKIN) return;
        allowed = std::min(allowed, std::max(0.0, s.y - box.bottom()));
      } else {
        if (s.bottom() > box.y + SKIN) return;
        allowed = std::max(allowed, std::min(0.0, s.bottom() - box.y));
      }
    });

    if (allowed != dy) {
      result.contacts |= dy > 0.0 ? CONTACT_BOTTOM : CONTACT_TOP;
      dy = allowed;
    }
    totalY += dy;
  }

  result.dx = totalX;
  result.dy = totalY;
  return result;
}

}  // namespace physics
