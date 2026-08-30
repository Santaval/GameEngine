#pragma once

#include "../EventManager/Event.hpp"
#include "../ECS/Entity.hpp"

class CollisionEvenet : public Event {
  public:
    Entity a;
    Entity b;

    CollisionEvenet(Entity a, Entity b) : a(a), b(b) {}
};