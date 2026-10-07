#pragma once

#include <cmath>
#include <vector>
#include <glm/glm.hpp>
#include "../ECS/System.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/GravityComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/SpriteComponent.hpp"

class GravitySystem : public System {
  private:
    // Constante gravitacional "de juego": a = G * M / d^2 (suavizado)
    static constexpr float G = 1000.0f;
    // Radio (px) que evita la singularidad cerca del centro de un cuerpo:
    // sin esto la aceleracion se dispararia al atravesar un planeta
    static constexpr float SOFTENING = 40.0f;

    struct Attractor {
      int id;
      glm::vec2 center;
      float mass;
      float range;
    };

    // transform.position es la esquina superior izquierda del sprite, asi que
    // el centro se obtiene sumando medio ancho/alto (igual que CollisionSystem).
    // Los planetas no tienen collider: se usa el tamaño del sprite.
    static glm::vec2 centerOf(Entity entity) {
      auto& transform = entity.getComponent<TransformComponent>();
      glm::vec2 center = glm::vec2(transform.position.x, transform.position.y);

      if (entity.hasComponent<CircleColliderComponent>()) {
        auto& collider = entity.getComponent<CircleColliderComponent>();
        center.x += (collider.width / 2.0f) * transform.scale.x;
        center.y += (collider.height / 2.0f) * transform.scale.y;
      } else if (entity.hasComponent<SpriteComponent>()) {
        auto& sprite = entity.getComponent<SpriteComponent>();
        center.x += (sprite.width / 2.0f) * transform.scale.x;
        center.y += (sprite.height / 2.0f) * transform.scale.y;
      }

      return center;
    }

  public:
    GravitySystem() {
      this->requireComponent<TransformComponent>();
      this->requireComponent<GravityComponent>();
    }

    // Debe correr ANTES de MovementSystem: suma a la velocidad y asi el tope
    // maxSpeed se sigue aplicando despues
    void update(double dt) {
      auto entities = this->getEntities();

      std::vector<Attractor> attractors;
      for (auto entity : entities) {
        auto& gravity = entity.getComponent<GravityComponent>();
        if (gravity.attracts && gravity.mass > 0.0f) {
          attractors.push_back({ entity.getId(), centerOf(entity), gravity.mass, gravity.range });
        }
      }

      if (attractors.empty()) return;

      for (auto entity : entities) {
        auto& gravity = entity.getComponent<GravityComponent>();
        if (!gravity.affected || !entity.hasComponent<RigidBodyComponent>()) continue;

        glm::vec2 center = centerOf(entity);
        glm::vec2 accel = glm::vec2(0.0f);

        for (const auto& attractor : attractors) {
          if (attractor.id == entity.getId()) continue;

          glm::vec2 d = attractor.center - center;
          float distSq = d.x * d.x + d.y * d.y;
          if (attractor.range > 0.0f && distSq > attractor.range * attractor.range) continue;

          // a = G*M * d / (dist^2 + soft^2)^(3/2): no depende de la masa del receptor
          float denom = distSq + SOFTENING * SOFTENING;
          accel += (G * attractor.mass) * d / (denom * std::sqrt(denom));
        }

        auto& rigidBody = entity.getComponent<RigidBodyComponent>();
        rigidBody.velocity.x += accel.x * dt;
        rigidBody.velocity.y += accel.y * dt;
      }
    }
};
