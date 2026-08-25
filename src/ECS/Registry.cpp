#include "Registry.hpp"

Registry::Registry() {
  std::cout << "[Registry] Registry init" << std::endl;
}

Registry::~Registry() {
  std::cout << "[Registry] Registry destroyed" << std::endl;
}

Entity Registry::createEntity() {
  int entityId = numEntity++;

  if (entityId >= this->entityComponentSignature.size()) {
    this->entityComponentSignature.resize(entityId + 100);
  }

  Entity entity(entityId);
  this->entitiesToBeAdded.insert(entity);

  std::cout << "[Registry] Entity created" << std::endl;

  return entity;
}


void Registry::killEntity(Entity entity) {
  this->entitiesToBeKilled.insert(entity);
}
