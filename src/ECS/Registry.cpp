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


void Registry::addEntityToSystems(Entity entity) {
  const int entityId = entity.getId();
  const Signature& entityComponentSignature 
    = this->entityComponentSignature[entityId];

  for(auto system : systems) {
    const auto& systemComponentSignature = system.second->getComponentSignature();

    bool isInterested = (entityComponentSignature & systemComponentSignature)
      == systemComponentSignature;

    if(isInterested) {
      system.second->addEntity(entity);
    }
  }
}


void Registry::removeEntityFromSystem(Entity entity) {
  for(auto system : systems) {
    system.second->removeEntity(entity);
  }
}

void Registry::update() {
  for(auto entity : this->entitiesToBeAdded) {
    this->addEntityToSystems(entity);
  }
  this->entitiesToBeAdded.clear();

  for(auto entity : this->entitiesToBeKilled) {
    this->removeEntityFromSystem(entity);
    this->entityComponentSignature[entity.getId()].reset();

    //  TOD: add id to deque of free ids
  }
  this->entitiesToBeKilled.clear();

}