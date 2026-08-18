#include "ECS.hpp"

int IComponent::nextId = 0;

int Entity::getId() const {
    return this->id;
}