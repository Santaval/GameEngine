#pragma once

#include <vector>

#include "../ECS/System.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Physics/Geometry.hpp"
#include "../Physics/MoveAndSlide.hpp"
#include "../Physics/StaticWorld.hpp"
#include "../Util/Culling.hpp"

// Mueve las cajas con mover = true: MovementSystem ya actualizo su velocidad
// pero no su posicion, y aqui se integra con barrido contra la geometria
// estatica (Game::staticWorld) y las cajas solidas de otras entidades. Una
// componente de velocidad bloqueada se pone a 0. getEntities() tambien es la
// lista de cajas que recibe CollisionSystem.
class BoxColliderSystem : public System {
  private:
    // Reutilizado frame a frame para no reservar memoria en el hot path
    std::vector<physics::Aabb> solids;

    static physics::Aabb worldRect(const BoxColliderComponent& box, const TransformComponent& transform) {
      return physics::boxWorldRect(
        transform.position.x, transform.position.y,
        transform.scale.x, transform.scale.y,
        box.offsetX, box.offsetY, box.width, box.height);
    }

  public:
    BoxColliderSystem() {
      this->requireComponent<BoxColliderComponent>();
      this->requireComponent<TransformComponent>();
    }

    void resolveMovers(double dt, const physics::StaticWorld& world) {
      auto entities = this->getEntities();

      // Solidos de otras entidades: cajas activas, solidas, que no se mueven
      solids.clear();
      for (auto entity : entities) {
        if (isDormant(entity)) continue;
        const auto& box = entity.getComponent<BoxColliderComponent>();
        if (!box.enabled || !box.solid || box.trigger || box.mover) continue;
        solids.push_back(worldRect(box, entity.getComponent<TransformComponent>()));
      }

      for (auto entity : entities) {
        if (isDormant(entity)) continue;
        auto& box = entity.getComponent<BoxColliderComponent>();
        // Un trigger no choca con nada: MovementSystem lo integra normal
        if (!box.enabled || !box.mover || box.trigger) continue;
        if (!entity.hasComponent<RigidBodyComponent>()) {
          box.contacts = 0;
          continue;
        }

        auto& transform = entity.getComponent<TransformComponent>();
        auto& rigidBody = entity.getComponent<RigidBodyComponent>();

        physics::SlideResult result = physics::moveAndSlide(
          worldRect(box, transform),
          rigidBody.velocity.x * dt, rigidBody.velocity.y * dt,
          world, &solids);

        transform.position.x += static_cast<float>(result.dx);
        transform.position.y += static_cast<float>(result.dy);

        // Chocar contra una pared anula la velocidad en esa direccion
        if ((result.contacts & physics::CONTACT_RIGHT) && rigidBody.velocity.x > 0.0f) rigidBody.velocity.x = 0.0f;
        if ((result.contacts & physics::CONTACT_LEFT) && rigidBody.velocity.x < 0.0f) rigidBody.velocity.x = 0.0f;
        if ((result.contacts & physics::CONTACT_BOTTOM) && rigidBody.velocity.y > 0.0f) rigidBody.velocity.y = 0.0f;
        if ((result.contacts & physics::CONTACT_TOP) && rigidBody.velocity.y < 0.0f) rigidBody.velocity.y = 0.0f;

        box.contacts = result.contacts;
      }
    }
};
