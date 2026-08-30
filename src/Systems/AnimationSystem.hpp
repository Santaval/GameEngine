#pragma once


#include <SDL2/SDL.h>

#include "../ECS/System.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/SpriteComponent.hpp"

class AnimationSystem : public System {

  public:

    AnimationSystem() {
      this->requireComponent<AnimationComponent>();
      this->requireComponent<SpriteComponent>();
    }

    void update() {
      for (auto entity : this->getEntities()) {
        auto& animation = entity.getComponent<AnimationComponent>();
        auto& sprite = entity.getComponent<SpriteComponent>();

        animation.currentFrame = ((SDL_GetTicks() - animation.startTime)
          * animation.frameSpeedRate / 1000) % animation.numFrames;

        sprite.srcRect.x = animation.currentFrame * sprite.width;
      }
    }

};