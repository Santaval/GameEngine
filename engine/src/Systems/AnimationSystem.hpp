#pragma once


#include <SDL2/SDL.h>

#include "../ECS/System.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Util/Culling.hpp"

class AnimationSystem : public System {

  public:

    AnimationSystem() {
      this->requireComponent<AnimationComponent>();
      this->requireComponent<SpriteComponent>();
    }

    // dtSec: segundos del frame. Solo lo usa la rama de atlas; la legacy sigue
    // calculando el frame con SDL_GetTicks
    void update(double dtSec) {
      // Tras una pausa larga (arrastrar la ventana, breakpoint) no saltar ciclos
      if (dtSec > 0.25) dtSec = 0.25;
      if (dtSec < 0.0) dtSec = 0.0;

      for (auto entity : this->getEntities()) {
        if (isDormant(entity)) continue;
        auto& animation = entity.getComponent<AnimationComponent>();
        auto& sprite = entity.getComponent<SpriteComponent>();

        if (animation.atlas) {
          animation.playback.advance(*animation.atlas, dtSec * 1000.0);
          animation.finished = animation.playback.finished;
          animation.applyTo(sprite);
          continue;
        }

        animation.currentFrame = ((SDL_GetTicks() - animation.startTime)
          * animation.frameSpeedRate / 1000) % animation.numFrames;

        sprite.srcRect.x = animation.currentFrame * sprite.width;
      }
    }

};