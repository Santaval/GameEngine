#pragma once 

#include <iostream>
#include <memory>

#include "../ECS/System.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Events/CollisionEvent.hpp"

class CollisionSystem : public System {

  public:
    CollisionSystem() {
      this->requireComponent<CircleColliderComponent>();
      this->requireComponent<TransformComponent>();
    }

    void update(std::unique_ptr<EventManager>& eventManager) {
      auto entities = this->getEntities();

      for (auto i = entities.begin(); i != entities.end(); i++) {
        Entity a = *i;
        auto aCollider = a.getComponent<CircleColliderComponent>();
        auto aTransform = a.getComponent<TransformComponent>();

        for (auto j = i; j != entities.end(); j++) {
          Entity b = *j;
          if (a == b) {
            continue;
          }

          auto bCollider = b.getComponent<CircleColliderComponent>();
          auto bTransform = b.getComponent<TransformComponent>();

          bool ownedByOther =
            (aCollider.ownerId != -1 && aCollider.ownerId == b.getId()) ||
            (bCollider.ownerId != -1 && bCollider.ownerId == a.getId());

          if (ownedByOther) {
            continue;
          }

         glm::vec2 aCenterPos = glm::vec2(
          aTransform.position.x - (aCollider.width / 2) * aTransform.scale.x,
          aTransform.position.y - (aCollider.height / 2) * aTransform.scale.y
         );

          glm::vec2 bCenterPos = glm::vec2(
          bTransform.position.x - (bCollider.width / 2) * bTransform.scale.x,
          bTransform.position.y - (bCollider.height / 2) * bTransform.scale.y
         );

         int aRadius = aCollider.radius * aTransform.scale.x;
         int bRadius = bCollider.radius * bTransform.scale.x;

          bool collision = this->checkCircularCollision(aRadius,
              bRadius, aCenterPos, bCenterPos);

          if (collision) {
            eventManager->emit<CollisionEvent>(a, b);
          }

        };
      }
    }

    bool checkCircularCollision(int aRadius, int bRadius, glm::vec2 aPos, glm::vec2 bPos) {
      glm::vec2 dif = aPos - bPos;
      double length = glm::sqrt((dif.x * dif.x) + (dif.y * dif.y));
      // There is collision if the radius sume is greater than distancce  
      return (aRadius + bRadius) >= length;
    }

};