#pragma once

#include "../EventManager/Event.hpp"
#include "../ECS/Entity.hpp"

// Una zona trigger y otro collider empiezan a solaparse (Enter), siguen
// solapandose (Stay, cada frame) o dejan de hacerlo (Exit). a es la entidad
// de menor id del par.
class TriggerEvent : public Event {
  public:
    enum class Phase { Enter, Stay, Exit };

    Entity a;
    Entity b;
    Phase phase;

    TriggerEvent(Entity a, Entity b, Phase phase) : a(a), b(b), phase(phase) {}
};
