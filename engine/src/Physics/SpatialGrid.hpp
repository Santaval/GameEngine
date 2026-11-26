#pragma once

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <unordered_map>
#include <vector>

// Broadphase: grilla uniforme. Cada elemento se anota en todas las celdas que
// toca su caja, y solo se comparan pares que comparten celda. Sacada tal cual
// de CollisionSystem (con el mapa del sistema solar, ~550 colliders, evita el
// O(n^2)); el orden de insercion y de iteracion NO debe cambiar: el orden de
// los eventos de colision depende de el.
//
// Los indices los pone quien llama y deben insertarse en orden 0, 1, 2... en
// la grilla dinamica; en la estatica pueden ser cualquiera (resize implicito).

namespace physics {

struct CellRange {
  int minX = 0, minY = 0, maxX = 0, maxY = 0;  // inclusive
};

class SpatialGrid {
  private:
    double cellSize;
    std::unordered_map<long long, std::vector<int>> cells;
    std::vector<CellRange> ranges;
    mutable std::vector<unsigned> stamps;
    mutable unsigned currentStamp = 0;

    static long long cellKey(int cx, int cy) {
      return (static_cast<long long>(cx) << 32) ^ static_cast<unsigned int>(cy);
    }

    int toCell(double v) const {
      return static_cast<int>(std::floor(v / cellSize));
    }

  public:
    explicit SpatialGrid(double cellSize = 256.0) : cellSize(cellSize) {}

    CellRange rangeOf(double minX, double minY, double maxX, double maxY) const {
      return { toCell(minX), toCell(minY), toCell(maxX), toCell(maxY) };
    }

    // Anota el indice en todas las celdas de su rango
    void insert(int index, const CellRange& range) {
      if (index >= static_cast<int>(ranges.size())) {
        ranges.resize(index + 1);
      }
      ranges[index] = range;

      for (int cx = range.minX; cx <= range.maxX; cx++) {
        for (int cy = range.minY; cy <= range.maxY; cy++) {
          cells[cellKey(cx, cy)].push_back(index);
        }
      }
    }

    // Vacia los vectores pero conserva las celdas: menos allocs. Si se
    // acumularon muchas celdas vacias (rocas que cruzaron el mapa) se tira
    // todo para no recorrerlas cada frame. n = cantidad de elementos del frame.
    void resetDynamic(size_t n) {
      ranges.clear();
      if (cells.size() > n * 4 + 1024) {
        cells.clear();
      } else {
        for (auto& cell : cells) cell.second.clear();
      }
    }

    void clearAll() {
      cells.clear();
      ranges.clear();
      stamps.clear();
      currentStamp = 0;
    }

    // Llama f(indexA, indexB) una vez por cada par que comparte celda. Un par
    // que comparte varias celdas se prueba solo en una: la esquina superior
    // izquierda de la interseccion de sus cajas.
    template <typename F>
    void forEachPair(F&& f) const {
      for (const auto& cell : cells) {
        const auto& members = cell.second;

        for (size_t i = 0; i < members.size(); i++) {
          const CellRange& a = ranges[members[i]];

          for (size_t j = i + 1; j < members.size(); j++) {
            const CellRange& b = ranges[members[j]];

            int ownerCellX = std::max(a.minX, b.minX);
            int ownerCellY = std::max(a.minY, b.minY);
            if (cell.first != cellKey(ownerCellX, ownerCellY)) {
              continue;
            }

            f(members[i], members[j]);
          }
        }
      }
    }

    // Llama f(index) una vez por cada elemento cuyas celdas tocan la region
    // (puede incluir elementos que no la solapan de verdad: es broadphase).
    // Recorre las celdas en orden fijo, asi que el orden es determinista.
    template <typename F>
    void query(double minX, double minY, double maxX, double maxY, F&& f) const {
      const CellRange r = rangeOf(minX, minY, maxX, maxY);

      if (stamps.size() < ranges.size()) stamps.resize(ranges.size(), 0);
      if (++currentStamp == 0) {
        std::fill(stamps.begin(), stamps.end(), 0u);
        currentStamp = 1;
      }

      for (int cx = r.minX; cx <= r.maxX; cx++) {
        for (int cy = r.minY; cy <= r.maxY; cy++) {
          auto it = cells.find(cellKey(cx, cy));
          if (it == cells.end()) continue;

          for (int index : it->second) {
            if (stamps[index] == currentStamp) continue;
            stamps[index] = currentStamp;
            f(index);
          }
        }
      }
    }
};

}  // namespace physics
