#pragma once

#include <algorithm>
#include <cstdint>
#include <unordered_set>
#include <utility>
#include <vector>

// Convierte "pares que se solapan este frame" en enter / stay / exit. Puro:
// trabaja con ids de entidad, sin ECS.
//
// Uso por frame: mark() por cada par solapado, diff() para leer los cambios y
// beginFrame() para que los pares de este frame pasen a ser los "anteriores".

namespace physics {

using TriggerPair = std::pair<int, int>;  // (menor id, mayor id)

class TriggerTracker {
  private:
    std::unordered_set<uint64_t> previous;
    std::unordered_set<uint64_t> current;

    static uint64_t keyOf(int a, int b) {
      const uint32_t lo = static_cast<uint32_t>(std::min(a, b));
      const uint32_t hi = static_cast<uint32_t>(std::max(a, b));
      return (static_cast<uint64_t>(lo) << 32) | hi;
    }

    static TriggerPair pairOf(uint64_t key) {
      return { static_cast<int>(key >> 32), static_cast<int>(key & 0xFFFFFFFFu) };
    }

    static void eraseWith(std::unordered_set<uint64_t>& set, int id) {
      for (auto it = set.begin(); it != set.end();) {
        TriggerPair p = pairOf(*it);
        if (p.first == id || p.second == id) {
          it = set.erase(it);
        } else {
          ++it;
        }
      }
    }

    static std::vector<TriggerPair> sorted(const std::vector<uint64_t>& keys) {
      std::vector<uint64_t> copy = keys;
      std::sort(copy.begin(), copy.end());
      std::vector<TriggerPair> out;
      out.reserve(copy.size());
      for (uint64_t k : copy) out.push_back(pairOf(k));
      return out;
    }

  public:
    // Marca un par que se solapa en este frame (idempotente)
    void mark(int idA, int idB) {
      current.insert(keyOf(idA, idB));
    }

    // Compara los pares marcados con los del frame anterior. Salidas ordenadas
    // (deterministas). No modifica el estado: llamar a beginFrame() despues.
    void diff(std::vector<TriggerPair>& enters, std::vector<TriggerPair>& stays,
      std::vector<TriggerPair>& exits) const {
      std::vector<uint64_t> e, s, x;
      for (uint64_t k : current) {
        (previous.count(k) ? s : e).push_back(k);
      }
      for (uint64_t k : previous) {
        if (!current.count(k)) x.push_back(k);
      }
      enters = sorted(e);
      stays = sorted(s);
      exits = sorted(x);
    }

    // Cierra el frame: lo marcado pasa a ser el estado anterior
    void beginFrame() {
      previous.swap(current);
      current.clear();
    }

    // Olvida todos los pares de una entidad SIN generar exit (murio)
    void forget(int id) {
      eraseWith(previous, id);
      eraseWith(current, id);
    }

    void clear() {
      previous.clear();
      current.clear();
    }
};

}  // namespace physics
