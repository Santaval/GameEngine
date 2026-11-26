#pragma once

#include <algorithm>
#include <cmath>

// Geometria 2D basica para colisiones con cajas. Solo datos y matematica: sin
// SDL, sin ECS, sin sol, para poder probarla en tests unitarios.

namespace physics {

// Rectangulo alineado a los ejes. (x, y) es la esquina superior izquierda,
// igual que transform.position en el resto del motor.
struct Aabb {
  double x = 0.0;
  double y = 0.0;
  double w = 0.0;
  double h = 0.0;

  double right() const { return x + w; }
  double bottom() const { return y + h; }
};

// Tolerancia de contacto. Dos cajas pegadas (o solapadas menos que esto por
// deriva de coma flotante) NO cuentan como solapadas: una caja que se apoya en
// una pared no se detecta como "dentro" de ella.
constexpr double SKIN = 0.01;

// Solape estricto: mas de SKIN en ambos ejes
inline bool aabbOverlap(const Aabb& a, const Aabb& b) {
  const double overlapX = std::min(a.right(), b.right()) - std::max(a.x, b.x);
  const double overlapY = std::min(a.bottom(), b.bottom()) - std::max(a.y, b.y);
  return overlapX > SKIN && overlapY > SKIN;
}

// Circulo contra caja. Tocar el borde cuenta (>= como el circulo contra
// circulo de CollisionSystem), asi que un circulo tangente a la caja colisiona.
inline bool circleAabbOverlap(double cx, double cy, double radius, const Aabb& box) {
  const double nearestX = std::clamp(cx, box.x, box.right());
  const double nearestY = std::clamp(cy, box.y, box.bottom());
  const double dx = cx - nearestX;
  const double dy = cy - nearestY;
  return dx * dx + dy * dy <= radius * radius;
}

// Caja del mundo de un BoxCollider. posX/posY es la esquina superior izquierda
// del sprite; offset y tamaño van en unidades locales y se escalan con la
// escala del transform. Ignora la rotacion a proposito (colisiones alineadas
// a los ejes). Una escala negativa se normaliza para que w, h >= 0.
inline Aabb boxWorldRect(double posX, double posY, double scaleX, double scaleY,
  double offsetX, double offsetY, double width, double height) {
  double x0 = posX + offsetX * scaleX;
  double y0 = posY + offsetY * scaleY;
  double x1 = posX + (offsetX + width) * scaleX;
  double y1 = posY + (offsetY + height) * scaleY;
  if (x1 < x0) std::swap(x0, x1);
  if (y1 < y0) std::swap(y0, y1);
  return { x0, y0, x1 - x0, y1 - y0 };
}

}  // namespace physics
