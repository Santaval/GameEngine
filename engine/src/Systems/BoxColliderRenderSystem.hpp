#pragma once

#include <SDL2/SDL.h>

#include "../ECS/System.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Physics/Geometry.hpp"
#include "../Physics/StaticWorld.hpp"
#include "../Util/Culling.hpp"

// Overlay de debug de las cajas: contorno de cada BoxColliderComponent tal
// como lo usa CollisionSystem, mas las paredes estaticas del mundo. Igual que
// ColliderRenderSystem, solo dibuja cuando Game::render() lo llama.
//   cian = mover, magenta = trigger, rojo = solido, verde = normal,
//   ambar = con dueño, gris = desactivado, naranja oscuro = pared estatica
class BoxColliderRenderSystem : public System {
  private:
    static const Uint8 ALPHA = 160;

    static void drawRect(SDL_Renderer* renderer, const physics::Aabb& box, const SDL_Rect& camera) {
      SDL_Rect rect = {
        static_cast<int>(box.x) - camera.x,
        static_cast<int>(box.y) - camera.y,
        static_cast<int>(box.w),
        static_cast<int>(box.h)
      };
      // Fuera de camara: no se dibuja
      if (rect.x + rect.w < 0 || rect.y + rect.h < 0 || rect.x > camera.w || rect.y > camera.h) return;
      SDL_RenderDrawRect(renderer, &rect);
    }

  public:
    BoxColliderRenderSystem() {
      this->requireComponent<BoxColliderComponent>();
      this->requireComponent<TransformComponent>();
    }

    void update(SDL_Renderer* renderer, const SDL_Rect& camera) {
      SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

      for (auto entity : this->getEntities()) {
        if (isDormant(entity)) continue;
        const auto& box = entity.getComponent<BoxColliderComponent>();
        const auto& transform = entity.getComponent<TransformComponent>();

        if (!box.enabled) {
          SDL_SetRenderDrawColor(renderer, 120, 120, 120, ALPHA);
        } else if (box.trigger) {
          SDL_SetRenderDrawColor(renderer, 255, 0, 255, ALPHA);
        } else if (box.mover) {
          SDL_SetRenderDrawColor(renderer, 0, 255, 255, ALPHA);
        } else if (box.solid) {
          SDL_SetRenderDrawColor(renderer, 255, 0, 0, ALPHA);
        } else if (box.ownerId != -1) {
          SDL_SetRenderDrawColor(renderer, 255, 170, 0, ALPHA);
        } else {
          SDL_SetRenderDrawColor(renderer, 0, 255, 0, ALPHA);
        }

        drawRect(renderer, physics::boxWorldRect(
          transform.position.x, transform.position.y, transform.scale.x, transform.scale.y,
          box.offsetX, box.offsetY, box.width, box.height), camera);
      }

      SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    }

    // Paredes y tiles solidos del mundo (no son entidades)
    void drawStatic(SDL_Renderer* renderer, const SDL_Rect& camera, const physics::StaticWorld& world) {
      SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
      SDL_SetRenderDrawColor(renderer, 255, 120, 0, ALPHA);

      // Los borrados quedan con tamaño 0 y se saltan
      for (const physics::Aabb& box : world.boxes()) {
        if (box.w <= 0.0 || box.h <= 0.0) continue;
        drawRect(renderer, box, camera);
      }

      SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
    }
};
