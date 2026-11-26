#pragma once

// Modelo en tiempo de ejecucion de un mapa de Tiled para dibujarlo: capas ya
// clasificadas por pasada (suelo / ordenadas por Y / por encima), tiles resueltos
// por gid y animaciones. Puro: sin SDL ni sol. El dibujado vive en
// Systems/TileMapRenderSystem.hpp. Ninguna funcion lanza excepciones; los errores
// vuelven en BuildResult::error y los avisos en BuildResult::warnings.

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <vector>

#include "TileMath.hpp"
#include "TmxLoader.hpp"

namespace tilemap {

// Ground: en orden de archivo bajo las entidades. YSort: tiles altos mezclados por Y
// con los sprites. Above: sobre todo (copas de arboles, tejados)
enum class Pass { Ground, YSort, Above };

// Un tile del tileset, indexado por gid en TileMap::defs
struct TileDef {
  int tileset = -1;  // indice en TileMap::tilesetImages; -1 = gid sin tileset valido
  int sx = 0, sy = 0, w = 0, h = 0;  // rectangulo origen en la imagen
  int sortOffset = 0;  // propiedad int "sort_offset" del tile
  int anim = -1;       // indice en TileMap::anims; -1 = sin animacion
};

struct TileAnim {
  std::vector<uint32_t> gids;      // gid de cada frame (firstGid + tileId)
  std::vector<int> durationsMs;
  int current = 0;
};

// Tile object (objeto con gid) de una capa de objetos. x/y ya incluyen el origen
// de la capa y el del mapa; y es el borde inferior, como en Tiled.
struct TileObject {
  uint32_t rawGid = 0;
  double x = 0, y = 0, w = 0, h = 0;
  double rotation = 0;
  int sortOffset = 0;
  bool visible = true;
};

struct Layer {
  std::vector<std::string> names;  // el suyo y despues los de los grupos que lo contienen
  Pass pass = Pass::Ground;
  bool isObjects = false;
  int width = 0, height = 0;  // en celdas
  int originX = 0, originY = 0;  // esquina de la celda (0,0) en el mundo
  std::vector<uint32_t> cells;   // gids crudos, width*height
  std::vector<TileObject> objects;
  bool visible = true;
  double opacity = 1.0;  // la de Tiled (acumulada con la de los grupos)
  int alpha = 255;       // 0-255, lo mueve Lua; se dibuja opacity*alpha
  std::string roofOf;
  tmx::Properties properties;  // propias mas las heredadas del grupo
  bool hasAnimatedTiles = false;  // gancho para un futuro baking por chunks
};

struct TileMap {
  int tileWidth = 0, tileHeight = 0;
  int width = 0, height = 0;  // en celdas
  int maxTileW = 0, maxTileH = 0;  // el tile mas grande (mapa incluido)
  std::vector<std::string> tilesetImages;
  std::vector<TileDef> defs;  // indexado por gid
  std::vector<TileAnim> anims;
  std::vector<Layer> layers;
  double clockMs = 0;

  void advance(double dtMs) {
    clockMs += dtMs;
    for (TileAnim& a : anims) a.current = animFrame(a.durationsMs, clockMs);
  }

  // gid sin flags -> definicion, o nullptr si no existe
  const TileDef* def(uint32_t gid) const {
    if (gid == 0 || gid >= defs.size()) return nullptr;
    const TileDef& d = defs[gid];
    return d.tileset < 0 ? nullptr : &d;
  }

  // gid sin flags -> gid del frame actual si tiene animacion
  uint32_t displayGid(uint32_t gid) const {
    const TileDef* d = def(gid);
    if (!d || d->anim < 0) return gid;
    const TileAnim& a = anims[static_cast<size_t>(d->anim)];
    if (a.gids.empty()) return gid;
    const size_t i = std::min(static_cast<size_t>(std::max(a.current, 0)), a.gids.size() - 1);
    return a.gids[i];
  }

  int pixelWidth() const { return width * tileWidth; }
  int pixelHeight() const { return height * tileHeight; }
};

struct BuildOptions {
  double x = 0, y = 0;  // posicion del mapa en el mundo
};

struct BuildResult {
  bool ok = false;
  std::string error;
  TileMap map;
  std::vector<std::string> warnings;
};

namespace detail {

inline const tmx::Property* findProp(const tmx::Properties& props, const std::string& name) {
  for (const tmx::Property& p : props) {
    if (p.name == name) return &p;
  }
  return nullptr;
}

inline bool boolProp(const tmx::Properties& props, const std::string& name) {
  const tmx::Property* p = findProp(props, name);
  if (!p) return false;
  if (p->type == tmx::PropType::Bool) return p->boolValue;
  return p->stringValue == "true";
}

struct Inherited {
  std::vector<std::string> names;  // de los grupos, del mas cercano al mas lejano
  tmx::Properties props;
  double offsetX = 0, offsetY = 0;
  double opacity = 1.0;
  bool visible = true;
};

struct Builder {
  TileMap map;
  std::vector<std::string> warnings;
  bool warnedFlipD = false;

  void checkFlipD(const TileDef& d, uint32_t raw) {
    if (warnedFlipD || !(raw & tmx::FLIP_D) || d.w == d.h) return;
    warnedFlipD = true;
    warnings.push_back("diagonal flip on non-square tiles is not supported; ignored");
  }

  void walk(const std::vector<tmx::Layer>& layers, const Inherited& parent, double mapX, double mapY) {
    for (const tmx::Layer& l : layers) {
      Inherited cur;
      cur.names.reserve(parent.names.size() + 1);
      cur.names.push_back(l.name);
      cur.names.insert(cur.names.end(), parent.names.begin(), parent.names.end());
      // Las propiedades propias ganan; las que faltan se heredan del grupo
      cur.props = l.properties;
      for (const tmx::Property& p : parent.props) {
        if (!findProp(cur.props, p.name)) cur.props.push_back(p);
      }
      cur.offsetX = parent.offsetX + l.offsetX;
      cur.offsetY = parent.offsetY + l.offsetY;
      cur.opacity = parent.opacity * l.opacity;
      cur.visible = parent.visible && l.visible;

      if (l.kind == tmx::LayerKind::Group) {
        // Los hijos heredan los nombres del grupo (cur.names ya los incluye)
        Inherited childParent;
        childParent.names = cur.names;
        childParent.props = cur.props;
        childParent.offsetX = cur.offsetX;
        childParent.offsetY = cur.offsetY;
        childParent.opacity = cur.opacity;
        childParent.visible = cur.visible;
        walk(l.children, childParent, mapX, mapY);
        continue;
      }
      if (l.kind == tmx::LayerKind::Image) {
        warnings.push_back("image layer '" + l.name + "' skipped (not supported)");
        continue;
      }

      const bool above = boolProp(cur.props, "above");
      const bool ysortFlag = boolProp(cur.props, "ysort");
      if (above && ysortFlag) {
        warnings.push_back("layer '" + l.name + "' has above and ysort: above wins");
      }
      Pass pass = above ? Pass::Above : (ysortFlag ? Pass::YSort : Pass::Ground);

      // Las capas de objetos solo se dibujan si son ysort o above; el resto son datos
      if (l.kind == tmx::LayerKind::Object && !above && !ysortFlag) continue;

      Layer out;
      out.names = cur.names;
      out.pass = pass;
      out.isObjects = l.kind == tmx::LayerKind::Object;
      out.visible = cur.visible;
      out.opacity = cur.opacity;
      out.originX = static_cast<int>(std::lround(mapX + cur.offsetX));
      out.originY = static_cast<int>(std::lround(mapY + cur.offsetY));
      out.properties = cur.props;
      if (const tmx::Property* ro = findProp(cur.props, "roof_of")) out.roofOf = ro->stringValue;

      if (l.kind == tmx::LayerKind::Tile) {
        out.width = l.width;
        out.height = l.height;
        out.cells = l.data;
        if (out.cells.size() != static_cast<size_t>(l.width) * static_cast<size_t>(l.height)) {
          warnings.push_back("layer '" + l.name + "' data size does not match its width*height");
        }
        for (uint32_t raw : out.cells) {
          const TileDef* d = map.def(tmx::gidOf(raw));
          if (!d) continue;
          checkFlipD(*d, raw);
          if (d->anim >= 0) out.hasAnimatedTiles = true;
        }
      } else {
        for (const tmx::Object& o : l.objects) {
          if (o.shape != tmx::Shape::Tile || tmx::gidOf(o.gid) == 0) continue;
          const TileDef* d = map.def(tmx::gidOf(o.gid));
          if (!d) continue;
          checkFlipD(*d, o.gid);
          TileObject t;
          t.rawGid = o.gid;
          t.x = o.x + mapX + cur.offsetX;
          t.y = o.y + mapY + cur.offsetY;
          t.w = o.width > 0 ? o.width : d->w;
          t.h = o.height > 0 ? o.height : d->h;
          t.rotation = o.rotation;
          t.sortOffset = d->sortOffset;
          t.visible = o.visible;
          out.objects.push_back(t);
          if (d->anim >= 0) out.hasAnimatedTiles = true;
        }
      }
      map.layers.push_back(std::move(out));
    }
  }
};

}  // namespace detail

inline BuildResult build(const tmx::Map& src, const BuildOptions& opts) {
  BuildResult res;
  if (src.orientation != "orthogonal") {
    res.error = "only orthogonal maps can be rendered (got '" + src.orientation + "')";
    return res;
  }
  if (src.tileWidth <= 0 || src.tileHeight <= 0) {
    res.error = "map has no valid tile size";
    return res;
  }

  detail::Builder b;
  TileMap& m = b.map;
  m.tileWidth = src.tileWidth;
  m.tileHeight = src.tileHeight;
  m.width = src.width;
  m.height = src.height;
  m.maxTileW = src.tileWidth;
  m.maxTileH = src.tileHeight;

  size_t defCount = 0;
  for (const tmx::Tileset& ts : src.tilesets) {
    defCount = std::max(defCount, static_cast<size_t>(std::max(ts.firstGid + ts.tileCount, 0)));
  }
  m.defs.assign(defCount, TileDef());

  for (const tmx::Tileset& ts : src.tilesets) {
    if (ts.columns <= 0 || ts.imagePath.empty() || ts.tileWidth <= 0 || ts.tileHeight <= 0) {
      b.warnings.push_back("tileset '" + ts.name + "' skipped (needs an image and columns > 0)");
      continue;
    }
    const int tsIndex = static_cast<int>(m.tilesetImages.size());
    m.tilesetImages.push_back(ts.imagePath);
    m.maxTileW = std::max(m.maxTileW, ts.tileWidth);
    m.maxTileH = std::max(m.maxTileH, ts.tileHeight);

    for (int local = 0; local < ts.tileCount; local++) {
      TileDef d;
      d.tileset = tsIndex;
      d.sx = ts.margin + (local % ts.columns) * (ts.tileWidth + ts.spacing);
      d.sy = ts.margin + (local / ts.columns) * (ts.tileHeight + ts.spacing);
      d.w = ts.tileWidth;
      d.h = ts.tileHeight;
      auto info = ts.tiles.find(local);
      if (info != ts.tiles.end()) {
        if (const tmx::Property* so = detail::findProp(info->second.properties, "sort_offset")) {
          d.sortOffset = static_cast<int>(so->intValue);
        }
        if (!info->second.animation.empty()) {
          TileAnim a;
          for (const tmx::AnimationFrame& f : info->second.animation) {
            a.gids.push_back(static_cast<uint32_t>(ts.firstGid + f.tileId));
            a.durationsMs.push_back(f.durationMs);
          }
          d.anim = static_cast<int>(m.anims.size());
          m.anims.push_back(std::move(a));
        }
      }
      m.defs[static_cast<size_t>(ts.firstGid + local)] = d;
    }
  }

  detail::Inherited root;
  b.walk(src.layers, root, opts.x, opts.y);

  res.ok = true;
  res.map = std::move(b.map);
  res.warnings = std::move(b.warnings);
  return res;
}

// Un tile listo para dibujar (coordenadas de pantalla, ya restada la camara)
struct TileInstance {
  int tileset = 0;
  int sx = 0, sy = 0, sw = 0, sh = 0;
  int dx = 0, dy = 0, dw = 0, dh = 0;
  uint32_t flags = 0;       // bits FLIP_H/V/D del gid crudo
  double rotation = 0;      // grados, solo tile objects
  bool pivotBottomLeft = false;  // los tile objects giran sobre su esquina inferior izquierda
  int alpha = 255;
  int sortY = 0;            // en coordenadas de mundo
};

// Capas que responden a un nombre: el suyo o el de cualquier grupo que las contiene.
// Sirve igual para TileMap const o no const
template <class MapT, class F>
inline void forEachLayerNamed(MapT& map, const std::string& name, F fn) {
  for (auto& layer : map.layers) {
    if (std::find(layer.names.begin(), layer.names.end(), name) != layer.names.end()) fn(layer);
  }
}

inline int layerAlpha(const Layer& layer) {
  const double a = layer.opacity * layer.alpha;
  return static_cast<int>(std::lround(std::max(0.0, std::min(255.0, a))));
}

// Anade las instancias visibles de una capa, en orden de celda (fila a fila) o de objeto
inline void appendLayerInstances(const TileMap& map, const Layer& layer, int camX, int camY,
                                 int camW, int camH, std::vector<TileInstance>& out) {
  if (!layer.visible) return;
  const int alpha = layerAlpha(layer);
  if (alpha <= 0) return;

  if (!layer.isObjects) {
    const int tw = map.tileWidth;
    const int th = map.tileHeight;
    const TileRange range = visibleTiles(camX, camY, camW, camH, layer.originX, layer.originY, tw, th,
                                         layer.width, layer.height, map.maxTileW - tw, map.maxTileH - th);
    if (range.empty()) return;
    for (int r = range.row0; r < range.row1; r++) {
      for (int c = range.col0; c < range.col1; c++) {
        const size_t idx = static_cast<size_t>(r) * static_cast<size_t>(layer.width) + static_cast<size_t>(c);
        if (idx >= layer.cells.size()) continue;
        const uint32_t raw = layer.cells[idx];
        const uint32_t gid = tmx::gidOf(raw);
        if (gid == 0) continue;
        const TileDef* base = map.def(gid);
        if (!base) continue;
        // La animacion cambia el origen del dibujo; el orden y el tamaño siguen al frame
        const TileDef* frame = map.def(map.displayGid(gid));
        if (!frame) frame = base;

        TileInstance t;
        t.tileset = frame->tileset;
        t.sx = frame->sx;
        t.sy = frame->sy;
        t.sw = frame->w;
        t.sh = frame->h;
        t.dw = frame->w;
        t.dh = frame->h;
        // Los tiles mas altos que la rejilla se alinean con el borde inferior de la celda
        t.dx = layer.originX + c * tw - camX;
        t.dy = layer.originY + (r + 1) * th - frame->h - camY;
        t.flags = raw & (tmx::FLIP_H | tmx::FLIP_V | tmx::FLIP_D);
        if ((t.flags & tmx::FLIP_D) && frame->w != frame->h) t.flags &= ~tmx::FLIP_D;
        t.alpha = alpha;
        t.sortY = layer.originY + (r + 1) * th + base->sortOffset;
        out.push_back(t);
      }
    }
    return;
  }

  for (const TileObject& o : layer.objects) {
    if (!o.visible) continue;
    const uint32_t gid = tmx::gidOf(o.rawGid);
    const TileDef* base = map.def(gid);
    if (!base) continue;
    const TileDef* frame = map.def(map.displayGid(gid));
    if (!frame) frame = base;

    // Caja de colision con la camara; un objeto girado cabe en un circulo de radio
    // diagonal alrededor de su pivote
    double left = o.x;
    double top = o.y - o.h;
    double right = o.x + o.w;
    double bottom = o.y;
    if (o.rotation != 0) {
      const double diag = std::sqrt(o.w * o.w + o.h * o.h);
      left = o.x - diag;
      right = o.x + diag;
      top = o.y - diag;
      bottom = o.y + diag;
    }
    if (right < camX || left > camX + camW || bottom < camY || top > camY + camH) continue;

    TileInstance t;
    t.tileset = frame->tileset;
    t.sx = frame->sx;
    t.sy = frame->sy;
    t.sw = frame->w;
    t.sh = frame->h;
    t.dw = static_cast<int>(std::lround(o.w));
    t.dh = static_cast<int>(std::lround(o.h));
    t.dx = static_cast<int>(std::lround(o.x)) - camX;
    t.dy = static_cast<int>(std::lround(o.y)) - t.dh - camY;
    t.flags = o.rawGid & (tmx::FLIP_H | tmx::FLIP_V | tmx::FLIP_D);
    if ((t.flags & tmx::FLIP_D) && frame->w != frame->h) t.flags &= ~tmx::FLIP_D;
    t.rotation = o.rotation;
    t.pivotBottomLeft = o.rotation != 0;
    t.alpha = alpha;
    t.sortY = static_cast<int>(std::lround(o.y)) + o.sortOffset;
    out.push_back(t);
  }
}

}  // namespace tilemap
