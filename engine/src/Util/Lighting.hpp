#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>

// Matematica pura de la iluminacion (sin SDL): falloff del gradiente, parpadeo,
// culling y transiciones lineales. El LightingSystem la usa y LightingTest la prueba
namespace lighting {

constexpr int GRADIENT_SIZE = 256;

// Caida suave del centro (t = 0) al borde (t = 1): (1 - t^2)^2, pendiente cero en el borde
inline float falloff(float t) {
  if (t < 0.0f) t = 0.0f;
  if (t >= 1.0f) return 0.0f;
  float k = 1.0f - t * t;
  return k * k;
}

// Matriz de Bayer 4x4 normalizada a [-0.5, 0.5): dither de +-0.5 LSB contra el banding
inline float bayer4(int x, int y) {
  static const int m[4][4] = {
    {  0,  8,  2, 10 },
    { 12,  4, 14,  6 },
    {  3, 11,  1,  9 },
    { 15,  7, 13,  5 },
  };
  return (m[y & 3][x & 3] + 0.5f) / 16.0f - 0.5f;
}

// Alfa (0..255) del pixel (x, y) de un gradiente de `size` x `size`
inline uint8_t gradientAlpha(int x, int y, int size) {
  float half = size / 2.0f;
  float dx = (x + 0.5f) - half;
  float dy = (y + 0.5f) - half;
  float t = std::sqrt(dx * dx + dy * dy) / half;
  if (t >= 1.0f) return 0;
  float v = falloff(t) * 255.0f + bayer4(x, y);
  return static_cast<uint8_t>(std::lround(std::min(255.0f, std::max(0.0f, v))));
}

// Multiplicador de intensidad en [1 - flicker, 1]. Ruido determinista (suma de senos)
inline float flickerFactor(float flicker, double time, int seed) {
  if (flicker <= 0.0f) return 1.0f;
  float f = std::min(flicker, 1.0f);
  double s = seed * 1.618;
  double n = 0.5 * std::sin(time * 7.3 + s) +
             0.3 * std::sin(time * 13.7 + s * 2.1) +
             0.2 * std::sin(time * 23.1 + s * 3.7);
  // n esta en [-1, 1] -> (0.5 + 0.5 n) en [0, 1]
  return 1.0f - f * static_cast<float>(0.5 + 0.5 * n);
}

// Factor del radio con el parpadeo: el radio parpadea menos que la intensidad (calma, no frenetico).
// En [0.75, 1] para flickerFactor en [0, 1]
inline float radiusFactor(float flickerFactor) { return 0.75f + 0.25f * flickerFactor; }

// true si el circulo (cx, cy, r) toca el rectangulo de la camara
inline bool circleVisible(float cx, float cy, float r, int camX, int camY, int camW, int camH) {
  return cx + r > camX && cx - r < camX + camW && cy + r > camY && cy - r < camY + camH;
}

inline uint8_t toByte(float v) {
  return static_cast<uint8_t>(std::lround(std::min(255.0f, std::max(0.0f, v))));
}

// Ambiente blanco: las luces no cambian nada y el pase se salta
inline bool isWhite(float r, float g, float b) {
  return r >= 254.5f && g >= 254.5f && b >= 254.5f;
}

// Transicion lineal de un valor hacia un objetivo
struct Tween {
  float value, from, to;
  float duration = 0.0f;
  float elapsed = 0.0f;

  explicit Tween(float v = 0.0f) : value(v), from(v), to(v) {}

  void set(float v) {
    value = from = to = v;
    duration = elapsed = 0.0f;
  }

  void start(float target, float seconds) {
    if (seconds <= 0.0f) {
      set(target);
      return;
    }
    from = value;
    to = target;
    duration = seconds;
    elapsed = 0.0f;
  }

  void step(float dt) {
    if (!active()) return;
    elapsed += dt;
    if (elapsed >= duration) {
      value = to;
      duration = 0.0f;
      elapsed = 0.0f;
    } else {
      value = from + (to - from) * (elapsed / duration);
    }
  }

  bool active() const { return duration > 0.0f; }
};

}  // namespace lighting
