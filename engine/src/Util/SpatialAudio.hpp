#pragma once

#include <algorithm>
#include <cmath>
#include <string>

// Matematica del audio espacial: volumen por distancia y paneo por desfase
// horizontal. Solo cabecera, sin SDL y sin reservar memoria, para poder
// llamarla por cada voz y cada frame.

namespace spatial {

enum class Rolloff { Linear, Inverse };

struct SpatialParams {
  // Dentro de minDist el sonido suena a volumen completo
  float minDist = 64.0f;
  // A partir de maxDist el sonido es inaudible
  float maxDist = 400.0f;
  Rolloff rolloff = Rolloff::Linear;
  // Desfase horizontal (px) con el que el paneo llega al extremo; 0 = media maxDist
  float panWidth = 0.0f;
};

// "linear" / "inverse" -> curva. false (y out intacto) si el nombre no existe
inline bool parseRolloff(const std::string& name, Rolloff& out) {
  if (name == "linear") { out = Rolloff::Linear; return true; }
  if (name == "inverse") { out = Rolloff::Inverse; return true; }
  return false;
}

// Ganancia 0..1 segun la distancia al oyente
inline float spatialGain(float dist, const SpatialParams& p) {
  float minDist = std::max(p.minDist, 0.0f);
  float maxDist = std::max(p.maxDist, minDist + 1.0f);
  if (dist <= minDist) return 1.0f;
  if (dist >= maxDist) return 0.0f;

  if (p.rolloff == Rolloff::Inverse) {
    float gain = minDist / dist;
    // La curva inversa nunca llega a 0: se apaga en el ultimo cuarto antes de maxDist
    float fade = std::clamp((maxDist - dist) / (0.25f * maxDist), 0.0f, 1.0f);
    return gain * fade;
  }
  return std::clamp(1.0f - (dist - minDist) / (maxDist - minDist), 0.0f, 1.0f);
}

// Paneo -1 (izquierda) .. 1 (derecha). dx = emisor - oyente; dist = distancia real
inline float spatialPan(float dx, float dist, const SpatialParams& p) {
  float width = p.panWidth > 0.0f ? p.panWidth : 0.5f * std::max(p.maxDist, 1.0f);
  float pan = std::clamp(dx / width, -1.0f, 1.0f);
  // Encima del emisor el signo de dx es ruido: el paneo se apaga al acercarse
  float fadeRadius = std::max(0.25f * p.minDist, 1.0f);
  return pan * std::clamp(dist / fadeRadius, 0.0f, 1.0f);
}

// Ley de potencia constante. Devuelve los gains 0..255 de Mix_SetPanning,
// reescalados para que el lado mas fuerte siempre quede en 255
inline void panToGains(float pan, int& left, int& right) {
  const float quarterPi = 0.7853981634f;
  float angle = (std::clamp(pan, -1.0f, 1.0f) + 1.0f) * quarterPi;
  float l = std::cos(angle);
  float r = std::sin(angle);
  float peak = std::max(l, r);
  if (peak <= 0.0f) peak = 1.0f;
  left = static_cast<int>(std::lround(l / peak * 255.0f));
  right = static_cast<int>(std::lround(r / peak * 255.0f));
}

// Factor de suavizado exponencial para un paso dt con constante de tiempo tau
inline float smoothAlpha(float dt, float tau) {
  if (tau <= 0.0f) return 1.0f;
  return 1.0f - std::exp(-std::max(dt, 0.0f) / tau);
}

}  // namespace spatial
