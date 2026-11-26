#pragma once
#include <SDL2/SDL.h>
#include <algorithm>
#include <cmath>
#include <memory>
#include <vector>
#include "../AssetManager/AssetManager.hpp"
#include "../ECS/System.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Util/Culling.hpp"
#include "../Util/YSort.hpp"
#include "TileMapRenderSystem.hpp"

class RenderSystem : public System{
    public:
        RenderSystem() {
            this->requireComponent<SpriteComponent>();
            this->requireComponent<TransformComponent>();
        }

    // Sprite listo para dibujar. Se copia todo lo necesario para no guardar
    // entidades entre llamadas (getEntities() devuelve una copia)
    struct SpriteDraw {
        SDL_Texture* texture = nullptr;
        SDL_Rect src = {0, 0, 0, 0};
        SDL_Rect dst = {0, 0, 0, 0};
        double angle = 0.0;
        SDL_RendererFlip flip = SDL_FLIP_NONE;
        int sortY = 0;
        SpriteLayer layer = SpriteLayer::World;
    };

    // Recorre las entidades en el orden de getEntities(), descarta las que estan
    // fuera de camara y guarda lo que hay que dibujar
    void collect(std::unique_ptr<AssetManager>& assetManager, const SDL_Rect& camera) {
        draws.clear();
        for(auto entity : this->getEntities()) {
            if (isDormant(entity)) continue;
            const auto& sprite = entity.getComponent<SpriteComponent>();
            const auto& transform = entity.getComponent<TransformComponent>();

            SDL_Rect srcRec = sprite.srcRect;
            SDL_Rect dstRec = {
                static_cast<int>(transform.position.x) - camera.x,
                static_cast<int>(transform.position.y) - camera.y,
                static_cast<int>(sprite.width * transform.scale.x),
                static_cast<int>(sprite.height * transform.scale.y),
            };

            // Fuera de camara no se dibuja. La rotacion gira alrededor del
            // centro, asi que el margen es lo que crece la caja al girar
            // (media diagonal menos medio lado)
            int halfDiagonal = static_cast<int>(std::sqrt(
                static_cast<double>(dstRec.w) * dstRec.w + static_cast<double>(dstRec.h) * dstRec.h) / 2.0);
            int marginX = halfDiagonal - dstRec.w / 2;
            int marginY = halfDiagonal - dstRec.h / 2;
            if (dstRec.x + dstRec.w + marginX < 0 || dstRec.x - marginX > camera.w ||
                dstRec.y + dstRec.h + marginY < 0 || dstRec.y - marginY > camera.h) {
                continue;
            }

            // Un prefab de red puede llegar antes de que la escena cargue su textura
            SDL_Texture* texture = assetManager->getTexture(sprite.teaxtureId);
            if (texture == nullptr) {
                continue;
            }

            SpriteDraw draw;
            draw.texture = texture;
            draw.src = srcRec;
            draw.dst = dstRec;
            draw.angle = transform.rotation * 180.0 / M_PI;
            draw.flip = sprite.flipH ? SDL_FLIP_HORIZONTAL : SDL_FLIP_NONE;
            // El orden va en coordenadas de mundo (sin restar la camara)
            draw.sortY = ysort::spriteSortY(transform.position.y, sprite.sortOffset,
                sprite.height, transform.scale.y);
            draw.layer = sprite.layer;
            draws.push_back(draw);
        }
    }

    static void drawOne(SDL_Renderer* renderer, const SpriteDraw& d) {
        SDL_RenderCopyEx(renderer, d.texture, &d.src, &d.dst, d.angle, NULL, d.flip);
    }

    // Dibuja los sprites de una capa en el orden en que se recogieron
    void drawLayer(SDL_Renderer* renderer, SpriteLayer layer) {
        for (const SpriteDraw& d : draws) {
            if (d.layer == layer) drawOne(renderer, d);
        }
    }

    // Mezcla los tiles altos (capas ysort) con los sprites World y los dibuja por
    // sortY; el empate lo gana el tile y despues el orden de insercion
    void drawSorted(SDL_Renderer* renderer, const SDL_Rect& camera, TileMapRenderSystem* tileMap) {
        tiles.clear();
        if (tileMap) tileMap->collectSorted(camera, tiles);

        items.clear();
        int seq = 0;
        for (size_t i = 0; i < tiles.size(); i++) {
            ysort::Item it;
            it.sortY = tiles[i].sortY;
            it.kind = ysort::KindTile;
            it.seq = seq++;
            it.index = static_cast<int>(i);
            items.push_back(it);
        }
        for (size_t i = 0; i < draws.size(); i++) {
            if (draws[i].layer != SpriteLayer::World) continue;
            ysort::Item it;
            it.sortY = draws[i].sortY;
            it.kind = ysort::KindSprite;
            it.seq = seq++;
            it.index = static_cast<int>(i);
            items.push_back(it);
        }
        std::sort(items.begin(), items.end(), ysort::less);

        for (const ysort::Item& it : items) {
            if (it.kind == ysort::KindTile) {
                tileMap->drawInstance(renderer, tiles[static_cast<size_t>(it.index)]);
            } else {
                drawOne(renderer, draws[static_cast<size_t>(it.index)]);
            }
        }
        if (tileMap) tileMap->resetAlpha();
    }

    // Compatibilidad: sin tile map ni orden por Y, las tres capas en orden de insercion
    void update(SDL_Renderer* renderer, std::unique_ptr<AssetManager>& assetManager, const SDL_Rect& camera) {
        collect(assetManager, camera);
        drawLayer(renderer, SpriteLayer::Ground);
        drawLayer(renderer, SpriteLayer::World);
        drawLayer(renderer, SpriteLayer::Above);
    }

    private:
        std::vector<SpriteDraw> draws;
        std::vector<ysort::Item> items;
        std::vector<tilemap::TileInstance> tiles;
};
