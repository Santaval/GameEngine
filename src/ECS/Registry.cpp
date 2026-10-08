#include "Registry.hpp"

Registry::Registry() {
  std::cout << "[Registry] Registry init" << std::endl;
}

Registry::~Registry() {
  std::cout << "[Registry] Registry destroyed" << std::endl;
}

Entity Registry::createEntity() {
  int entityId;

  if(this->freeIds.empty()) {
    entityId = numEntity++;
    if (entityId >= static_cast<int>(this->entityComponentSignature.size())) {
      this->entityComponentSignature.resize(entityId + 100);
    }
  } else {
    entityId = this->freeIds.front();
    this->freeIds.pop_front();
  }


  Entity entity(entityId);
  entity.registry = this;
  this->entitiesToBeAdded.insert(entity);

  std::cout << "[Registry] Entity created" << std::endl;

  return entity;
}


void Registry::killEntity(Entity entity) {
  this->entitiesToBeKilled.insert(entity);
}


void Registry::onEntityKilled(std::function<void(Entity)> listener) {
  this->killListeners.push_back(std::move(listener));
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

void Registry::refreshEntity(Entity entity) {
  // Pendiente: update() la agregara una sola vez; aqui duplicaria la entrada
  if (this->entitiesToBeAdded.count(entity) > 0) {
    return;
  }
  this->removeEntityFromSystem(entity);
  this->addEntityToSystems(entity);
}

void Registry::update() {
  for(auto entity : this->entitiesToBeAdded) {
    this->addEntityToSystems(entity);
  }
  this->entitiesToBeAdded.clear();

  for(auto entity : this->entitiesToBeKilled) {
    this->removeEntityFromSystem(entity);

    // Antes de resetear la firma y de liberar el id: los listeners aun pueden
    // leer los componentes y el id todavia no se puede reciclar
    for(auto& listener : this->killListeners) {
      listener(entity);
    }

    this->entityComponentSignature[entity.getId()].reset();

    this->freeIds.push_back(entity.getId());
  }
  this->entitiesToBeKilled.clear();

}

void Registry::clear() {
  for(auto system : systems) {
    system.second->clearEntities();
  }

  // Los pools se quedan: sin firma ningun componente viejo es accesible
  for(auto& signature : this->entityComponentSignature) {
    signature.reset();
  }

  this->entitiesToBeAdded.clear();
  this->entitiesToBeKilled.clear();
  this->freeIds.clear();
  this->numEntity = 0;
}
