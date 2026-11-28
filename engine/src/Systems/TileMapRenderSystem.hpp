#pragma once
#include <SDL2/SDL.h>
#include <algorithm>
#include <iostream>
#include <string>
#include <utility>
#include <vector>
#include "../AssetManager/AssetManager.hpp"
#include "../Map/TileMap.hpp"
#include "../Map/TileMath.hpp"

// Dibuja un tile map recortado a la camara. NO es un System del Registry a
// proposito: un System con firma vacia matricula a todas las entidades, y esto
// no trabaja sobre entidades. Lo posee Game (ver loadTileMap).
//
// Gancho de iluminacion: la pasada de luces ira entre las capas Above y las
// imagenes "front"/HUD (ver Game::render).
class TileMapRenderSystem {
    public:
        explicit TileMapRenderSystem(tilemap::TileMap built) : map(std::move(built)) {}

        // Las texturas se piden una sola vez al cargar: getTexture escribe en el
        // log cada vez que falla, asi que nunca se llama por tile
        void loadTextures(SDL_Renderer* renderer, AssetManager& assetManager) {
            textures.assign(map.tilesetImages.size(), nullptr);
            for (size_t i = 0; i < map.tilesetImages.size(); i++) {
                const std::string id = "tileset:" + map.tilesetImages[i];
                assetManager.addTexture(renderer, id, map.tilesetImages[i]);
                SDL_Texture* texture = assetManager.getTexture(id);
                if (texture == nullptr) {
                    std::cout << "[TileMap] tileset image could not be loaded: "
                        << map.tilesetImages[i] << " (its tiles are skipped)" << std::endl;
                    continue;
                }
                SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);
                textures[i] = texture;
            }
        }

        // Cuenta de tiles dibujados desde el ultimo reset (perfil: Game con ENGINE_PROFILE)
        size_t drawCount = 0;

        tilemap::TileMap& getMap() { return map; }
        const tilemap::TileMap& getMap() const { return map; }

        void advance(double dtSec) {
            const double dt = std::max(0.0, std::min(dtSec, 0.25));
            map.advance(dt * 1000.0);
        }

        // Capas de una pasada, en orden de archivo
        void drawPass(SDL_Renderer* renderer, const SDL_Rect& camera, tilemap::Pass pass) {
            for (const tilemap::Layer& layer : map.layers) {
                if (layer.pass != pass) continue;
                scratch.clear();
                tilemap::appendLayerInstances(map, layer, camera.x, camera.y, camera.w, camera.h, scratch);
                for (const tilemap::TileInstance& inst : scratch) drawInstance(renderer, inst);
            }
            resetAlpha();
        }

        // Instancias de las capas ysort (para mezclarlas con los sprites)
        void collectSorted(const SDL_Rect& camera, std::vector<tilemap::TileInstance>& out) const {
            for (const tilemap::Layer& layer : map.layers) {
                if (layer.pass != tilemap::Pass::YSort) continue;
                tilemap::appendLayerInstances(map, layer, camera.x, camera.y, camera.w, camera.h, out);
            }
        }

        // El alpha se fija en cada instancia: las texturas se comparten entre capas
        void drawInstance(SDL_Renderer* renderer, const tilemap::TileInstance& inst) {
            if (inst.tileset < 0 || static_cast<size_t>(inst.tileset) >= textures.size()) return;
            SDL_Texture* texture = textures[static_cast<size_t>(inst.tileset)];
            if (texture == nullptr) return;
            drawCount++;

            SDL_SetTextureAlphaMod(texture, static_cast<Uint8>(std::max(0, std::min(255, inst.alpha))));
            const SDL_Rect src = {inst.sx, inst.sy, inst.sw, inst.sh};
            const SDL_Rect dst = {inst.dx, inst.dy, inst.dw, inst.dh};
            if (inst.flags == 0 && inst.rotation == 0.0) {
                SDL_RenderCopy(renderer, texture, &src, &dst);
                return;
            }
            const tilemap::TileTransform tr = tilemap::flipTransform(inst.flags);
            int flip = SDL_FLIP_NONE;
            if (tr.flipH) flip |= SDL_FLIP_HORIZONTAL;
            if (tr.flipV) flip |= SDL_FLIP_VERTICAL;
            // Los tile objects giran sobre su esquina inferior izquierda
            const SDL_Point pivot = {0, inst.dh};
            SDL_RenderCopyEx(renderer, texture, &src, &dst, tr.angle + inst.rotation,
                inst.pivotBottomLeft ? &pivot : nullptr, static_cast<SDL_RendererFlip>(flip));
        }

        // Deja las texturas opacas para quien las use despues
        void resetAlpha() {
            for (SDL_Texture* texture : textures) {
                if (texture != nullptr) SDL_SetTextureAlphaMod(texture, 255);
            }
        }

    private:
        tilemap::TileMap map;
        std::vector<SDL_Texture*> textures;
        std::vector<tilemap::TileInstance> scratch;
};
