#pragma once

// Hoja de sprites exportada por Aseprite / pixelfx (PNG + JSON). Cabecera pura:
// sin SDL ni sol, para poder probarla sola (tests/AsepriteAtlasTest.cpp).
//
// El JSON admite los dos formatos de "JSON Data": "frames" como array o como
// hash (objeto). El hash se lee con ordered_json para conservar el orden del
// archivo, que es el orden de los frames. Los tags (meta.frameTags) dan nombre a
// rangos de frames con una direccion de reproduccion.

#include <cmath>
#include <fstream>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

namespace aseprite {

enum class Direction { Forward, Reverse, PingPong, PingPongReverse };

struct Frame {
  int x = 0;
  int y = 0;
  int w = 0;
  int h = 0;
  int durationMs = 100;
};

struct Tag {
  std::string name;
  int from = 0;
  int to = 0;
  Direction dir = Direction::Forward;

  int count() const { return to - from + 1; }
};

struct Atlas {
  int sizeW = 0;
  int sizeH = 0;
  std::vector<Frame> frames;
  std::vector<Tag> tags;

  // Indice del tag con ese nombre, o -1
  int findTag(const std::string& name) const {
    for (size_t i = 0; i < tags.size(); i++) {
      if (tags[i].name == name) return static_cast<int>(i);
    }
    return -1;
  }
};

struct Result {
  bool ok = false;
  std::string error;
  Atlas atlas;
};

namespace detail {

using Json = nlohmann::ordered_json;

inline int getInt(const Json& obj, const char* key, int fallback) {
  auto it = obj.find(key);
  if (it == obj.end() || !it->is_number()) return fallback;
  return it->get<int>();
}

inline Result fail(const std::string& message) {
  Result r;
  r.ok = false;
  r.error = message;
  return r;
}

inline Direction parseDirection(const std::string& s) {
  if (s == "reverse") return Direction::Reverse;
  if (s == "pingpong") return Direction::PingPong;
  if (s == "pingpong_reverse") return Direction::PingPongReverse;
  return Direction::Forward;
}

}  // namespace detail

// Nunca lanza: cualquier fallo vuelve en Result.error
inline Result parse(const std::string& text) {
  using detail::Json;
  try {
    Json j = Json::parse(text, nullptr, false);
    if (j.is_discarded()) return detail::fail("invalid JSON");
    if (!j.is_object()) return detail::fail("root is not an object");

    auto framesIt = j.find("frames");
    if (framesIt == j.end()) return detail::fail("missing 'frames'");

    std::vector<const Json*> entries;
    if (framesIt->is_array()) {
      for (const auto& e : *framesIt) entries.push_back(&e);
    } else if (framesIt->is_object()) {
      // ordered_json: se itera en el orden del archivo
      for (const auto& e : *framesIt) entries.push_back(&e);
    } else {
      return detail::fail("'frames' must be an array or an object");
    }
    if (entries.empty()) return detail::fail("'frames' is empty");

    Result r;
    for (const Json* e : entries) {
      if (!e->is_object()) return detail::fail("frame entry is not an object");
      auto rectIt = e->find("frame");
      if (rectIt == e->end() || !rectIt->is_object()) {
        return detail::fail("frame entry without 'frame' rect");
      }
      Frame f;
      f.x = detail::getInt(*rectIt, "x", 0);
      f.y = detail::getInt(*rectIt, "y", 0);
      f.w = detail::getInt(*rectIt, "w", 0);
      f.h = detail::getInt(*rectIt, "h", 0);
      f.durationMs = detail::getInt(*e, "duration", 100);
      if (f.durationMs <= 0) f.durationMs = 100;
      r.atlas.frames.push_back(f);
    }

    const int frameCount = static_cast<int>(r.atlas.frames.size());

    auto metaIt = j.find("meta");
    if (metaIt != j.end() && metaIt->is_object()) {
      auto sizeIt = metaIt->find("size");
      if (sizeIt != metaIt->end() && sizeIt->is_object()) {
        r.atlas.sizeW = detail::getInt(*sizeIt, "w", 0);
        r.atlas.sizeH = detail::getInt(*sizeIt, "h", 0);
      }
      auto tagsIt = metaIt->find("frameTags");
      if (tagsIt != metaIt->end() && tagsIt->is_array()) {
        for (const auto& t : *tagsIt) {
          if (!t.is_object()) return detail::fail("frameTag is not an object");
          Tag tag;
          auto nameIt = t.find("name");
          if (nameIt != t.end() && nameIt->is_string()) tag.name = nameIt->get<std::string>();
          tag.from = detail::getInt(t, "from", 0);
          tag.to = detail::getInt(t, "to", 0);
          auto dirIt = t.find("direction");
          if (dirIt != t.end() && dirIt->is_string()) {
            tag.dir = detail::parseDirection(dirIt->get<std::string>());
          }
          if (tag.from < 0 || tag.to >= frameCount || tag.from > tag.to) {
            return detail::fail("tag '" + tag.name + "' has an invalid frame range");
          }
          r.atlas.tags.push_back(tag);
        }
      }
    }

    // Sin tags: uno implicito, de nombre vacio, con todos los frames
    if (r.atlas.tags.empty()) {
      Tag all;
      all.from = 0;
      all.to = frameCount - 1;
      r.atlas.tags.push_back(all);
    }

    r.ok = true;
    return r;
  } catch (const std::exception& ex) {
    return detail::fail(std::string("parse error: ") + ex.what());
  }
}

inline Result loadFile(const std::string& path) {
  std::ifstream in(path);
  if (!in) return detail::fail("cannot open " + path);
  std::stringstream buffer;
  buffer << in.rdbuf();
  Result r = parse(buffer.str());
  if (!r.ok) r.error = path + ": " + r.error;
  return r;
}

// ---------------------------------------------------------------------------
// Reproduccion
//
// Un tag se recorre como una secuencia de pasos (step). Forward: from..to;
// Reverse: to..from; PingPong: from..to..from sin repetir los extremos
// (0,1,2,1,0,1,...). PingPongReverse es lo mismo empezando por el final.
// Con loop el ultimo paso vuelve al primero; sin loop el ultimo paso se mantiene
// y, al agotar su duracion, finished pasa a true. Un pingpong sin loop termina
// de vuelta en el primer frame (secuencia 0,1,2,1,0).
// ---------------------------------------------------------------------------

inline bool isPingPong(const Tag& tag) {
  return tag.dir == Direction::PingPong || tag.dir == Direction::PingPongReverse;
}

inline int sequenceLength(const Tag& tag, bool loop) {
  const int n = tag.count();
  if (n <= 1) return 1;
  if (!isPingPong(tag)) return n;
  return loop ? 2 * n - 2 : 2 * n - 1;
}

// Desplazamiento (0..n-1) dentro del tag para un paso de la secuencia
inline int frameOffset(const Tag& tag, int step) {
  const int n = tag.count();
  switch (tag.dir) {
    case Direction::Forward: return step;
    case Direction::Reverse: return n - 1 - step;
    case Direction::PingPong: return step < n ? step : 2 * n - 2 - step;
    case Direction::PingPongReverse: {
      const int off = step < n ? step : 2 * n - 2 - step;
      return n - 1 - off;
    }
  }
  return 0;
}

struct Playback {
  int tagIndex = -1;
  int step = 0;
  double elapsedMs = 0.0;
  bool loop = true;
  bool finished = false;

  // Empieza el tag desde su primer frame
  void start(int tag, bool looping) {
    tagIndex = tag;
    step = 0;
    elapsedMs = 0.0;
    loop = looping;
    finished = false;
  }

  // Indice absoluto en atlas.frames del frame actual (0 si no hay tag valido)
  int frameIndex(const Atlas& atlas) const {
    if (tagIndex < 0 || tagIndex >= static_cast<int>(atlas.tags.size())) return 0;
    const Tag& tag = atlas.tags[tagIndex];
    return tag.from + frameOffset(tag, step);
  }

  void advance(const Atlas& atlas, double dtMs) {
    if (finished || dtMs <= 0.0) return;
    if (tagIndex < 0 || tagIndex >= static_cast<int>(atlas.tags.size())) return;
    const Tag& tag = atlas.tags[tagIndex];
    const int len = sequenceLength(tag, loop);

    elapsedMs += dtMs;

    // Con loop, los ciclos completos no cambian el estado: se descartan para
    // que un dt enorme no cueste mas que un ciclo
    if (loop) {
      double total = 0.0;
      for (int s = 0; s < len; s++) {
        total += atlas.frames[tag.from + frameOffset(tag, s)].durationMs;
      }
      if (total > 0.0 && elapsedMs >= total) elapsedMs = std::fmod(elapsedMs, total);
    }

    // Cota defensiva: tras el modulo caben como mucho len+1 pasos
    for (int guard = 0; guard < len + 2; guard++) {
      const double dur = atlas.frames[tag.from + frameOffset(tag, step)].durationMs;
      if (elapsedMs < dur) break;
      elapsedMs -= dur;
      if (step + 1 >= len) {
        if (loop) {
          step = 0;
        } else {
          finished = true;
          elapsedMs = 0.0;
          break;
        }
      } else {
        step++;
      }
    }
  }
};

}  // namespace aseprite
