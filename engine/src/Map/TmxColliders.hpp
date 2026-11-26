#pragma once

// Rectangulos solidos de un mapa de Tiled, para StaticWorld. Sin SDL ni sol.
//
// Convenciones (ver engine/docs/collision.md):
//   - Tile solido: la propiedad bool solid = true en el tile del tileset, o en
//     la capa de tiles (entonces todo tile no vacio de esa capa es solido).
//     solid = false en una capa la excluye por completo.
//   - Objetos: los de la capa de objetos llamada "collision" (configurable).
//     Rectangulos y tile objects; una elipse se aproxima por su caja con aviso;
//     poligonos, polilineas y objetos rotados se saltan con aviso. Un objeto
//     con solid = false se salta.
//   - Los desplazamientos de capa y de grupo se aplican.

#include <algorithm>
#include <map>
#include <string>
#include <utility>
#include <vector>

#include "TmxLoader.hpp"

namespace tmx {

struct SolidOptions {
  // Vacio = todas las capas de tiles; si no, solo las que se llamen asi
  std::vector<std::string> tileLayers;
  // Capa de objetos con rectangulos de colision; vacia = ninguna
  std::string objectLayer = "collision";
  // Origen del mapa en el mundo y escala (todo se multiplica por ella)
  double offsetX = 0.0;
  double offsetY = 0.0;
  double scale = 1.0;
};

struct SolidResult {
  bool ok = false;
  std::string error;
  std::vector<Rect> rects;
};

namespace detail {

inline const Property* findProperty(const Properties& props, const std::string& name) {
  for (const Property& p : props) {
    if (p.name == name) return &p;
  }
  return nullptr;
}

// true / false si la propiedad bool existe; -1 si no
inline int boolProperty(const Properties& props, const std::string& name) {
  const Property* p = findProperty(props, name);
  if (!p || p->type != PropType::Bool) return -1;
  return p->boolValue ? 1 : 0;
}

inline bool tileIsSolid(const Map& map, uint32_t gid, std::map<uint32_t, bool>& cache) {
  auto cached = cache.find(gid);
  if (cached != cache.end()) return cached->second;

  bool solid = false;
  const Tileset* ts = tilesetForGid(map, gid);
  if (ts) {
    auto tile = ts->tiles.find(static_cast<int>(gid) - ts->firstGid);
    if (tile != ts->tiles.end()) {
      solid = boolProperty(tile->second.properties, "solid") == 1;
    }
  }
  cache[gid] = solid;
  return solid;
}

struct Collector {
  const Map& map;
  const SolidOptions& opts;
  std::vector<std::string>& warnings;
  std::vector<Rect>& out;
  std::map<uint32_t, bool> solidCache;

  void emit(double x, double y, double w, double h) {
    if (w <= 0.0 || h <= 0.0) return;
    out.push_back({ opts.offsetX + x * opts.scale, opts.offsetY + y * opts.scale,
      w * opts.scale, h * opts.scale });
  }

  bool wantsTileLayer(const Layer& layer) const {
    if (opts.tileLayers.empty()) return true;
    return std::find(opts.tileLayers.begin(), opts.tileLayers.end(), layer.name) != opts.tileLayers.end();
  }

  // Une las celdas solidas: primero tramos horizontales por fila y luego los
  // tramos identicos de filas consecutivas (un bloque de 3x2 es un solo rect)
  void tileLayer(const Layer& layer, double ox, double oy) {
    if (!wantsTileLayer(layer)) return;
    const int layerSolid = boolProperty(layer.properties, "solid");
    if (layerSolid == 0) return;

    const int tw = map.tileWidth, th = map.tileHeight;
    struct Run { int col, len, row0, rows; };
    std::vector<Run> runs;
    // (col, len) -> indice en runs del rect abierto que termino en la fila anterior
    std::map<std::pair<int, int>, size_t> open;

    for (int row = 0; row < layer.height; row++) {
      std::map<std::pair<int, int>, size_t> nextOpen;
      int col = 0;
      while (col < layer.width) {
        auto solidAt = [&](int c) {
          const size_t i = static_cast<size_t>(row) * layer.width + c;
          if (i >= layer.data.size()) return false;
          const uint32_t gid = gidOf(layer.data[i]);
          if (gid == 0) return false;
          return layerSolid == 1 || tileIsSolid(map, gid, solidCache);
        };

        if (!solidAt(col)) { col++; continue; }
        int end = col;
        while (end < layer.width && solidAt(end)) end++;
        const int len = end - col;

        auto key = std::make_pair(col, len);
        auto it = open.find(key);
        if (it != open.end()) {
          runs[it->second].rows++;
          nextOpen[key] = it->second;
        } else {
          runs.push_back({ col, len, row, 1 });
          nextOpen[key] = runs.size() - 1;
        }
        col = end;
      }
      open.swap(nextOpen);
    }

    for (const Run& r : runs) {
      emit(ox + r.col * tw, oy + r.row0 * th, static_cast<double>(r.len) * tw,
        static_cast<double>(r.rows) * th);
    }
  }

  void objectLayer(const Layer& layer, double ox, double oy) {
    for (const Object& o : layer.objects) {
      const std::string label = "objeto '" + o.name + "' (id " + std::to_string(o.id) +
        ") de la capa '" + layer.name + "'";

      if (boolProperty(o.properties, "solid") == 0) continue;

      switch (o.shape) {
        case Shape::Point:
        case Shape::Text:
          continue;  // sin area: nada que colisionar
        case Shape::Polygon:
        case Shape::Polyline:
          warnings.push_back(label + ": poligonos y polilineas no se soportan, se salta");
          continue;
        case Shape::Ellipse:
          warnings.push_back(label + ": elipse aproximada por su caja");
          break;
        default:
          break;
      }

      if (o.rotation != 0.0) {
        warnings.push_back(label + ": rotado, se salta (las colisiones van alineadas a los ejes)");
        continue;
      }

      const Rect r = objectRect(o);
      emit(ox + r.x, oy + r.y, r.w, r.h);
    }
  }

  void walk(const std::vector<Layer>& layers, double ox, double oy) {
    for (const Layer& layer : layers) {
      const double lx = ox + layer.offsetX;
      const double ly = oy + layer.offsetY;

      switch (layer.kind) {
        case LayerKind::Tile:
          tileLayer(layer, lx, ly);
          break;
        case LayerKind::Object:
          if (!opts.objectLayer.empty() && layer.name == opts.objectLayer) objectLayer(layer, lx, ly);
          break;
        case LayerKind::Group:
          walk(layer.children, lx, ly);
          break;
        default:
          break;
      }
    }
  }
};

}  // namespace detail

// Recorre el mapa y devuelve sus rectangulos solidos (coordenadas de mundo).
// Los casos no soportados se anotan en warnings; un mapa no ortogonal es un
// error. Ninguna funcion lanza excepciones.
inline SolidResult collectSolidRects(const Map& map, const SolidOptions& opts,
  std::vector<std::string>& warnings) {
  SolidResult result;

  if (!map.orientation.empty() && map.orientation != "orthogonal") {
    result.error = "mapa '" + map.orientation + "' no soportado para colisiones (solo ortogonal)";
    return result;
  }

  detail::Collector collector{ map, opts, warnings, result.rects, {} };
  collector.walk(map.layers, 0.0, 0.0);
  result.ok = true;
  return result;
}

}  // namespace tmx
