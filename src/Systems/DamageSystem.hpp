#pragma once

#include <memory>
#include <iostream>

#include "../Events/CollisionEvent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../ECS/System.hpp"

class DamageSystem : public System {
  public:
    DamageSystem() {
      this->requireComponent<CircleColliderComponent>();
    }

    void subscribeToCollisionEvent(std::unique_ptr<EventManager>& eventManager) {
      eventManager->subscribe<CollisionEvent, DamageSystem>(this, &DamageSystem::onCollision);
    }

    void onCollision(CollisionEvent&  e) {
      std::cout << "[DamageSystem] Callback on collision " << e.a.getId() 
        << " and " << e.b.getId() << std::endl;
      
      e.a.kill();
      e.b.kill();
    }
};