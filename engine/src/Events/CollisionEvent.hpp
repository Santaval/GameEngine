#pragma once

#include "../EventManager/Event.hpp"
#include "../ECS/Entity.hpp"

class CollisionEvent : public Event {
  public:
    Entity a;
    Entity b;

    CollisionEvent(Entity a, Entity b) : a(a), b(b) {}
};