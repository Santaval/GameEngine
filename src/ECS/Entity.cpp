#include "Entity.hpp"
#include "Registry.hpp"

int Entity::getId() const {
    return this->id;
}


void Entity::kill() {
  this->registry->killEntity(*this);
}
