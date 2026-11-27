#pragma once

#include <algorithm>
#include <string>

// Buses de audio: agrupan las voces por tipo (voz, efectos, ambiente, musica)
// para tener un volumen por grupo y ducking (bajar ambiente y musica mientras
// suena una voz). Solo cabecera, sin SDL y sin reservar memoria.

namespace audiobus {

enum class Bus { Voice = 0, Sfx = 1, Ambience = 2, Music = 3 };

const int BUS_COUNT = 4;

// Nombre del bus tal como se escribe en Lua y en los mapas
inline const char* busName(Bus bus) {
  switch (bus) {
    case Bus::Voice: return "voice";
    case Bus::Sfx: return "sfx";
    case Bus::Ambience: return "ambience";
    case Bus::Music: return "music";
  }
  return "sfx";
}

// "voice" / "sfx" / "ambience" / "music" -> bus. false (y out intacto) si no existe
inline bool parseBus(const std::string& name, Bus& out) {
  if (name == "voice") { out = Bus::Voice; return true; }
  if (name == "sfx") { out = Bus::Sfx; return true; }
  if (name == "ambience") { out = Bus::Ambience; return true; }
  if (name == "music") { out = Bus::Music; return true; }
  return false;
}

// Configuracion del ducking: mientras haya una voz en el bus Voice, los buses
// marcados en "buses" bajan a "amount" (0..1) en "fadeMs" milisegundos
struct DuckConfig {
  bool enabled = true;
  float amount = 0.35f;
  int fadeMs = 300;
  // Por defecto solo ambiente y musica; la voz nunca se atenua a si misma
  bool buses[BUS_COUNT] = {false, false, true, true};
};

// Avanza la ganancia de ducking hacia target. Rampa lineal que recorre
// [amount, 1] en fadeMs; fadeMs <= 0 la pone de golpe. dt acotado a 0.1 s
// para que un tiron no sea un salto
inline float duckStep(float current, float target, double dt, const DuckConfig& cfg) {
  if (cfg.fadeMs <= 0) return target;

  double clampedDt = std::clamp(dt, 0.0, 0.1);
  float span = std::max(1.0f - cfg.amount, 0.05f);
  float step = static_cast<float>(span / (cfg.fadeMs / 1000.0) * clampedDt);
  if (current < target) return std::min(current + step, target);
  return std::max(current - step, target);
}

}  // namespace audiobus
