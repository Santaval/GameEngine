#pragma once

#include <algorithm>
#include <cmath>
#include <iostream>
#include <memory>
#include <unordered_map>
#include <vector>

#include "../ECS/System.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Events/CollisionEvent.hpp"

class CollisionSystem : public System {
  private:
    // Broadphase: grilla uniforme. Cada collider se anota en todas las celdas
    // que toca su caja, y solo se comparan pares que comparten celda. Con el
    // mapa del sistema solar (~550 colliders) evita el O(n^2) de antes.
    static constexpr float CELL_SIZE = 256.0f;

    struct Body {
      Entity entity;
      glm::vec2 center;
      int radius;
      int ownerId;
      // Caja en celdas (inclusive)
      int minCellX, minCellY, maxCellX, maxCellY;
    };

    std::vector<Body> bodies;
    std::unordered_map<long long, std::vector<int>> grid;

    static long long cellKey(int cx, int cy) {
      return (static_cast<long long>(cx) << 32) ^ static_cast<unsigned int>(cy);
    }

    static int toCell(float v) {
      return static_cast<int>(std::floor(v / CELL_SIZE));
    }

  public:
    CollisionSystem() {
      this->requireComponent<CircleColliderComponent>();
      this->requireComponent<TransformComponent>();
    }

    void update(std::unique_ptr<EventManager>& eventManager) {
      auto entities = this->getEntities();

      bodies.clear();
      // Se vacian los vectores pero se conservan las celdas: menos allocs.
      // Si se acumularon muchas celdas vacias (rocas que cruzaron el mapa)
      // se tira todo para no recorrerlas cada frame
      if (grid.size() > entities.size() * 4 + 1024) {
        grid.clear();
      } else {
        for (auto& cell : grid) cell.second.clear();
      }

      for (auto entity : entities) {
        const auto& collider = entity.getComponent<CircleColliderComponent>();
        const auto& transform = entity.getComponent<TransformComponent>();

        // transform.position es la esquina superior izquierda del sprite
        // (ver RenderSystem y make_asteroid en asteroid_field.lua), así que
        // el centro se obtiene SUMANDO medio ancho/alto, no restando.
        glm::vec2 center = glm::vec2(
          transform.position.x + (collider.width / 2) * transform.scale.x,
          transform.position.y + (collider.height / 2) * transform.scale.y
        );
        int radius = collider.radius * transform.scale.x;

        Body body = { entity, center, radius, collider.ownerId,
          toCell(center.x - radius), toCell(center.y - radius),
          toCell(center.x + radius), toCell(center.y + radius) };

        int index = static_cast<int>(bodies.size());
        bodies.push_back(body);

        for (int cx = body.minCellX; cx <= body.maxCellX; cx++) {
          for (int cy = body.minCellY; cy <= body.maxCellY; cy++) {
            grid[cellKey(cx, cy)].push_back(index);
          }
        }
      }

      for (const auto& cell : grid) {
        const auto& members = cell.second;

        for (size_t i = 0; i < members.size(); i++) {
          const Body& a = bodies[members[i]];

          for (size_t j = i + 1; j < members.size(); j++) {
            const Body& b = bodies[members[j]];

            // Un par que comparte varias celdas se prueba solo en una: la
            // esquina superior izquierda de la interseccion de sus cajas
            int ownerCellX = std::max(a.minCellX, b.minCellX);
            int ownerCellY = std::max(a.minCellY, b.minCellY);
            if (cell.first != cellKey(ownerCellX, ownerCellY)) {
              continue;
            }

            bool ownedByOther =
              (a.ownerId != -1 && a.ownerId == b.entity.getId()) ||
              (b.ownerId != -1 && b.ownerId == a.entity.getId());

            if (ownedByOther) {
              continue;
            }

            if (this->checkCircularCollision(a.radius, b.radius, a.center, b.center)) {
              eventManager->emit<CollisionEvent>(a.entity, b.entity);
            }
          }
        }
      }
    }

    bool checkCircularCollision(int aRadius, int bRadius, glm::vec2 aPos, glm::vec2 bPos) {
      glm::vec2 dif = aPos - bPos;
      double length = glm::sqrt((dif.x * dif.x) + (dif.y * dif.y));
      // There is collision if the radius sume is greater than distancce
      return (aRadius + bRadius) >= length;
    }

};
