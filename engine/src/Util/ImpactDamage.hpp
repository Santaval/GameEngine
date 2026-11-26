#pragma once

#include <algorithm>
#include <cmath>

// Escala el daño de un impacto segun la velocidad de cierre (px/s) a lo largo
// de la normal entre los dos colliders. Sin dependencias de SDL ni Lua para
// poder probarla en solitario (tests/ImpactDamageTest.cpp).
//
// - full <= 0: la escala esta desactivada, daño plano (comportamiento clasico)
// - closing <= min: 0 (roce o separandose); closing >= full: amount (el tope)
// - entre medias: interpolacion lineal, redondeada al entero mas cercano
inline int impactDamage(int amount, float closing, float min, float full) {
  if (full <= 0.0f) return amount;
  if (closing <= min) return 0;
  if (full <= min) return amount;

  float t = std::clamp((closing - min) / (full - min), 0.0f, 1.0f);
  return static_cast<int>(std::lround(amount * t));
}
