#pragma once

#include <algorithm>
#include <cmath>
#include <iostream>
#include <memory>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include "../ECS/System.hpp"
#include "../Components/BoxColliderComponent.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Events/CollisionEvent.hpp"
#include "../Events/TriggerEvent.hpp"
#include "../Physics/Geometry.hpp"
#include "../Physics/SpatialGrid.hpp"
#include "../Physics/TriggerTracker.hpp"
#include "../Util/Culling.hpp"

class CollisionSystem : public System {
  private:
    // Broadphase: grilla uniforme compartida (ver Physics/SpatialGrid.hpp).
    // Los circulos se insertan primero y en el mismo orden de siempre, y luego
    // las cajas: el orden de los eventos entre circulos no cambia.
    static constexpr double CELL_SIZE = 256.0;

    struct Body {
      Entity entity;
      glm::vec2 center;
      int radius;
      int ownerId;
      bool isBox;
      bool trigger;
      physics::Aabb box;
    };

    std::vector<Body> bodies;
    physics::SpatialGrid grid{CELL_SIZE};

    // Triggers: pares solapados de este frame contra el anterior
    physics::TriggerTracker tracker;
    // Entidades de los pares marcados (este frame y el anterior): un Exit
    // necesita la Entity aunque ya no entre al broadphase
    std::unordered_map<int, Entity> trackedCurrent;
    std::unordered_map<int, Entity> trackedPrevious;
    // Pares que ya emitieron CollisionEvent este frame (solo si hay cajas):
    // una entidad con circulo y caja no avisa dos veces del mismo choque
    std::unordered_set<unsigned long long> emittedPairs;

    static unsigned long long pairKey(int a, int b) {
      const unsigned int lo = static_cast<unsigned int>(std::min(a, b));
      const unsigned int hi = static_cast<unsigned int>(std::max(a, b));
      return (static_cast<unsigned long long>(lo) << 32) | hi;
    }

    bool lookupTracked(int id, Entity& out) const {
      auto cur = trackedCurrent.find(id);
      if (cur != trackedCurrent.end()) { out = cur->second; return true; }
      auto prev = trackedPrevious.find(id);
      if (prev != trackedPrevious.end()) { out = prev->second; return true; }
      return false;
    }

    void emitTrigger(std::unique_ptr<EventManager>& eventManager,
      const std::vector<physics::TriggerPair>& pairs, TriggerEvent::Phase phase) {
      for (const auto& p : pairs) {
        Entity a(0), b(0);
        if (!lookupTracked(p.first, a) || !lookupTracked(p.second, b)) continue;
        eventManager->emit<TriggerEvent>(a, b, phase);
      }
    }

  public:
    CollisionSystem() {
      this->requireComponent<CircleColliderComponent>();
      this->requireComponent<TransformComponent>();
    }

    // boxEntities: entidades con BoxColliderComponent + Transform (las da
    // BoxColliderSystem). Vacio = solo circulos, como antes.
    void update(std::unique_ptr<EventManager>& eventManager,
      const std::vector<Entity>& boxEntities) {
      auto entities = this->getEntities();

      bodies.clear();
      grid.resetDynamic(entities.size() + boxEntities.size());
      emittedPairs.clear();
      const bool anyBoxes = !boxEntities.empty();

      for (auto entity : entities) {
        // Un cuerpo dormido no entra al broadphase: ningun par con el se prueba
        if (isDormant(entity)) continue;
        const auto& collider = entity.getComponent<CircleColliderComponent>();
        const auto& transform = entity.getComponent<TransformComponent>();

        // transform.position es la esquina superior izquierda del sprite
        // (ver RenderSystem y prefabs/asteroid.lua), así que
        // el centro se obtiene SUMANDO medio ancho/alto, no restando.
        glm::vec2 center = glm::vec2(
          transform.position.x + (collider.width / 2) * transform.scale.x,
          transform.position.y + (collider.height / 2) * transform.scale.y
        );
        int radius = collider.radius * transform.scale.x;

        Body body = { entity, center, radius, collider.ownerId, false, false, {} };

        int index = static_cast<int>(bodies.size());
        bodies.push_back(body);

        grid.insert(index, grid.rangeOf(center.x - radius, center.y - radius,
          center.x + radius, center.y + radius));
      }

      for (auto entity : boxEntities) {
        if (isDormant(entity)) continue;
        const auto& collider = entity.getComponent<BoxColliderComponent>();
        if (!collider.enabled) continue;
        const auto& transform = entity.getComponent<TransformComponent>();

        physics::Aabb box = physics::boxWorldRect(
          transform.position.x, transform.position.y,
          transform.scale.x, transform.scale.y,
          collider.offsetX, collider.offsetY, collider.width, collider.height);

        Body body = { entity, glm::vec2(box.x + box.w * 0.5, box.y + box.h * 0.5), 0,
          collider.ownerId, true, collider.trigger, box };

        int index = static_cast<int>(bodies.size());
        bodies.push_back(body);

        grid.insert(index, grid.rangeOf(box.x, box.y, box.right(), box.bottom()));
      }

      grid.forEachPair([&](int indexA, int indexB) {
        const Body& a = bodies[indexA];
        const Body& b = bodies[indexB];

        bool ownedByOther =
          (a.ownerId != -1 && a.ownerId == b.entity.getId()) ||
          (b.ownerId != -1 && b.ownerId == a.entity.getId());

        if (ownedByOther) {
          return;
        }

        // Circulo contra circulo: el camino de siempre
        if (!a.isBox && !b.isBox) {
          if (this->checkCircularCollision(a.radius, b.radius, a.center, b.center)) {
            eventManager->emit<CollisionEvent>(a.entity, b.entity);
            if (anyBoxes) emittedPairs.insert(pairKey(a.entity.getId(), b.entity.getId()));
          }
          return;
        }

        // Un circulo y una caja de la misma entidad no se tocan entre si
        if (a.entity == b.entity) {
          return;
        }

        bool hit;
        if (a.isBox && b.isBox) {
          hit = physics::aabbOverlap(a.box, b.box);
        } else if (a.isBox) {
          hit = physics::circleAabbOverlap(b.center.x, b.center.y, b.radius, a.box);
        } else {
          hit = physics::circleAabbOverlap(a.center.x, a.center.y, a.radius, b.box);
        }
        if (!hit) return;

        if (a.trigger || b.trigger) {
          // Trigger contra trigger se ignora
          if (a.trigger && b.trigger) return;
          tracker.mark(a.entity.getId(), b.entity.getId());
          trackedCurrent.insert_or_assign(a.entity.getId(), a.entity);
          trackedCurrent.insert_or_assign(b.entity.getId(), b.entity);
          return;
        }

        if (emittedPairs.insert(pairKey(a.entity.getId(), b.entity.getId())).second) {
          eventManager->emit<CollisionEvent>(a.entity, b.entity);
        }
      });

      // Triggers: los hooks de Lua corren aqui, ya fuera del bucle de pares.
      // Orden fijo: primero las salidas, luego las entradas y luego los stay.
      std::vector<physics::TriggerPair> enters, stays, exits;
      tracker.diff(enters, stays, exits);
      emitTrigger(eventManager, exits, TriggerEvent::Phase::Exit);
      emitTrigger(eventManager, enters, TriggerEvent::Phase::Enter);
      emitTrigger(eventManager, stays, TriggerEvent::Phase::Stay);
      tracker.beginFrame();
      trackedPrevious.swap(trackedCurrent);
      trackedCurrent.clear();
    }

    // La entidad murio: se olvidan sus pares de trigger sin emitir Exit (usa
    // on_death si hay que limpiar algo). Lo llama Game desde onEntityKilled.
    void forgetEntity(int id) {
      tracker.forget(id);
      trackedCurrent.erase(id);
      trackedPrevious.erase(id);
    }

    // Cambio de escena: ningun par sobrevive
    void resetTriggers() {
      tracker.clear();
      trackedCurrent.clear();
      trackedPrevious.clear();
    }

    bool checkCircularCollision(int aRadius, int bRadius, glm::vec2 aPos, glm::vec2 bPos) {
      glm::vec2 dif = aPos - bPos;
      double length = glm::sqrt((dif.x * dif.x) + (dif.y * dif.y));
      // There is collision if the radius sume is greater than distancce
      return (aRadius + bRadius) >= length;
    }

};
