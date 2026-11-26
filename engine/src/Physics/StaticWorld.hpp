#pragma once

#include <vector>

#include "Geometry.hpp"
#include "SpatialGrid.hpp"

// Geometria estatica del nivel: rectangulos solidos que bloquean a los movers
// (paredes, vallas, tiles solidos de un TMX). Vive en Game, no en entidades:
// un mapa con miles de tiles no crea miles de entidades. Nunca emite eventos.

namespace physics {

class StaticWorld {
  private:
    SpatialGrid grid{128.0};
    // Las cajas borradas quedan como tombstone (tamaño 0) para que los ids
    // ya entregados no cambien
    std::vector<Aabb> items;
    std::vector<char> alive;
    int liveCount = 0;

  public:
    // Devuelve el id de la caja (valido hasta clear())
    int add(const Aabb& box) {
      const int id = static_cast<int>(items.size());
      items.push_back(box);
      alive.push_back(1);
      liveCount++;
      grid.insert(id, grid.rangeOf(box.x, box.y, box.right(), box.bottom()));
      return id;
    }

    // false si el id no existe o ya estaba borrado
    bool remove(int id) {
      if (id < 0 || id >= static_cast<int>(items.size()) || !alive[id]) return false;
      alive[id] = 0;
      items[id] = { items[id].x, items[id].y, 0.0, 0.0 };
      liveCount--;
      return true;
    }

    void clear() {
      grid.clearAll();
      items.clear();
      alive.clear();
      liveCount = 0;
    }

    int count() const { return liveCount; }

    // Llama f(const Aabb&) por cada caja viva que solapa la region (solape
    // estricto, ver aabbOverlap)
    template <typename F>
    void query(const Aabb& region, F&& f) const {
      grid.query(region.x, region.y, region.right(), region.bottom(), [&](int id) {
        if (!alive[id]) return;
        if (aabbOverlap(items[id], region)) f(items[id]);
      });
    }

    bool overlaps(const Aabb& region) const {
      bool hit = false;
      query(region, [&](const Aabb&) { hit = true; });
      return hit;
    }

    // Todas las cajas, incluidos los tombstones (de tamaño 0). Para debug draw.
    const std::vector<Aabb>& boxes() const { return items; }
};

}  // namespace physics
