#pragma once
#include <SDL2/SDL.h>
#include <cmath>
#include <memory>
#include "../AssetManager/AssetManager.hpp"
#include "../ECS/System.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/TransformComponent.hpp"

class RenderSystem : public System{
    public:
        RenderSystem() {
            this->requireComponent<SpriteComponent>();
            this->requireComponent<TransformComponent>();
        }

    void update(SDL_Renderer* renderer, std::unique_ptr<AssetManager>& assetManager, const SDL_Rect& camera) {
        for(auto entity : this->getEntities()) {
            const auto sprite = entity.getComponent<SpriteComponent>();
            const auto transform = entity.getComponent<TransformComponent>();

            SDL_Rect srcRec = sprite.srcRect;
            SDL_Rect dstRec = {
                static_cast<int>(transform.position.x) - camera.x,
                static_cast<int>(transform.position.y) - camera.y,
                static_cast<int>(sprite.width * transform.scale.x),
                static_cast<int>(sprite.height * transform.scale.y),
            };

            double rotationDegrees = transform.rotation * 180.0 / M_PI;

            SDL_RenderCopyEx(
                renderer,
                assetManager->getTexture(sprite.teaxtureId),
                &srcRec,
                &dstRec,
                rotationDegrees,
                NULL,
                SDL_FLIP_NONE
            );
        }
    }
};