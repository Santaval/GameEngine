#pragma once

#include <SDL2/SDL.h>
#include <SDL2/SDL_ttf.h>
#include <iostream>
#include <memory>
#include <string>
#include <unordered_map>

#include "../AssetManager/AssetManager.hpp"
#include "../ECS/System.hpp"
#include "../Components/TextComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Util/TextBuffer.hpp"

class TextRenderSystem : public System {
    private:
        // Textura cacheada por (fontId + texto). El color NO forma parte de la
        // clave: se rasteriza en blanco y se tiñe con SDL_SetTextureColorMod.
        struct CachedText {
            SDL_Texture* texture = nullptr;
            int width = 0;
            int height = 0;
            int lastUsedFrame = 0;
        };

        std::unordered_map<std::string, CachedText> cache;
        int currentFrame = 0;

        // Los textos dinámicos ("Vel: 120.5") generan una cadena distinta cada
        // frame, así que hay que tirar lo que no se usa o el caché crece sin fin.
        static const int FRAMES_TO_EVICT = 90;

    public:
        TextRenderSystem() {
            this->requireComponent<TextComponent>();
            this->requireComponent<TransformComponent>();
        }

        void update(SDL_Renderer* renderer, std::unique_ptr<AssetManager>& assetManager,
            const SDL_Rect& camera, const TextBuffer& textBuffer) {

            this->currentFrame++;

            // 1. Etiquetas pegadas a entidades
            for (auto entity : this->getEntities()) {
                const auto& text = entity.getComponent<TextComponent>();
                const auto& transform = entity.getComponent<TransformComponent>();

                this->draw(renderer, assetManager, camera, text.text, text.fontId,
                    static_cast<int>(transform.position.x) + text.offsetX,
                    static_cast<int>(transform.position.y) + text.offsetY,
                    text.color, text.isWorldSpace);
            }

            // 2. Modo inmediato: lo que los scripts pidieron este frame (va encima)
            for (const auto& command : textBuffer.getCommands()) {
                this->draw(renderer, assetManager, camera, command.text, command.fontId,
                    command.x, command.y, command.color, command.isWorldSpace);
            }

            this->evictOldEntries();
        }

        // Libera las texturas del caché. HAY QUE LLAMARLO ANTES DE SDL_DestroyRenderer.
        void clearCache() {
            for (auto entry : this->cache) {
                SDL_DestroyTexture(entry.second.texture);
            }
            this->cache.clear();
        }

    private:
        void draw(SDL_Renderer* renderer, std::unique_ptr<AssetManager>& assetManager,
            const SDL_Rect& camera, const std::string& text, const std::string& fontId,
            int x, int y, SDL_Color color, bool isWorldSpace) {

            CachedText* cached = this->getOrCreate(renderer, assetManager, fontId, text);
            if (!cached) return;

            SDL_SetTextureColorMod(cached->texture, color.r, color.g, color.b);
            SDL_SetTextureAlphaMod(cached->texture, color.a);

            SDL_Rect dstRec = {
                isWorldSpace ? x - camera.x : x,
                isWorldSpace ? y - camera.y : y,
                cached->width,
                cached->height
            };

            SDL_RenderCopy(renderer, cached->texture, NULL, &dstRec);
        }

        CachedText* getOrCreate(SDL_Renderer* renderer, std::unique_ptr<AssetManager>& assetManager,
            const std::string& fontId, const std::string& text) {

            if (text.empty()) return nullptr;

            const std::string key = fontId + "\x1f" + text;

            auto found = this->cache.find(key);
            if (found != this->cache.end()) {
                found->second.lastUsedFrame = this->currentFrame;
                return &found->second;
            }

            TTF_Font* font = assetManager->getFont(fontId);
            if (!font) return nullptr;

            // Blanco puro: el color final lo pone SDL_SetTextureColorMod
            SDL_Color white = { 255, 255, 255, 255 };
            SDL_Surface* surface = TTF_RenderUTF8_Blended(font, text.c_str(), white);

            if (!surface) {
                std::cout << "[TextRenderSystem] Error rendering text: "
                    << TTF_GetError() << std::endl;
                return nullptr;
            }

            CachedText entry;
            entry.texture = SDL_CreateTextureFromSurface(renderer, surface);
            entry.width = surface->w;
            entry.height = surface->h;
            entry.lastUsedFrame = this->currentFrame;
            SDL_FreeSurface(surface);

            if (!entry.texture) return nullptr;
            SDL_SetTextureBlendMode(entry.texture, SDL_BLENDMODE_BLEND);

            auto inserted = this->cache.emplace(key, entry);
            return &inserted.first->second;
        }

        void evictOldEntries() {
            for (auto it = this->cache.begin(); it != this->cache.end(); ) {
                if (this->currentFrame - it->second.lastUsedFrame > FRAMES_TO_EVICT) {
                    SDL_DestroyTexture(it->second.texture);
                    it = this->cache.erase(it);
                } else {
                    ++it;
                }
            }
        }
};
