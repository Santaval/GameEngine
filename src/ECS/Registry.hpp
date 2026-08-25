#pragma once

#include <vector>
#include <memory>
#include <unordered_map>
#include <set>
#include <typeindex>
#include <deque>
#include <iostream>
#include "../Util/Pool.hpp"
#include "System.hpp"
#include "Entity.hpp"

class Registry {
  private:
    int numEntity = 0;
    std::vector<std::shared_ptr<IPool>> componentsPool;
    std::vector<Signature> entityComponentSignature;
    std::unordered_map<std::type_index, std::shared_ptr<System>> systems;
    std::set<Entity> entitiesToBeAdded;
    std::set<Entity> entitiesToBeKilled;
    std::deque<int> freeIds;

  public:
    Registry();
    ~Registry();

    void update();

    Entity createEntity();
    void killEntity(Entity entity);

    // components managment

    template <typename TComponent, typename... TArgs>
    void addComponent(Entity Entity, TArgs&&... args);

    template <typename TComponent>
    void removeComponent(Entity entity);

    template <typename TComponent>
    bool hasComponent(Entity entity) const;

    template <typename TComponent>
    TComponent& getComponent(Entity entity) const;

    // systems managment

    template <typename TSystem, typename... TArgs>
    void addSystem(TArgs&&... args);

    template <typename TSystem>
    void removeSystem();

    template <typename TSystem>
    bool hasSystem() const;

    template <typename TSystem>
    TSystem& getSystem() const;


    // Add system entities
    void addEntityToSystems(Entity entity);
    void removeEntityFromSystem(Entity entity);
};


template <typename TComponent, typename... TArgs>
void Registry::addComponent(Entity entity, TArgs&&... args) {
  const int componentId = Component<TComponent>::getid();
  const int entityId = entity.getId();

  if(componentId >= this->componentsPool.size()) {
    this->componentsPool.resize(componentId + 10, nullptr);
  }

  if(!this->componentsPool[componentId]) {
    std::shared_ptr<Pool<TComponent>> newComponentPool = std::make_shared<Pool<TComponent>>();
    this->componentsPool[componentId] = newComponentPool;
  }

  std::shared_ptr<Pool<TComponent>> componentPool 
    = std::static_pointer_cast<Pool<TComponent>> (this->componentsPool[componentId]);

  if(entityId >= componentPool->GetSize()) {
    componentPool->Resize(numEntity + 100);
  }

  TComponent newComponent(std::forward<TArgs>(args)...);
  componentPool->Set(entityId, newComponent);
  this->entityComponentSignature[entityId].set(componentId);
}


template <typename TComponent>
void Registry::removeComponent(Entity entity) {
  const int componentId = Component<TComponent>::getid();
  const int entityId = entity.getId();

  this->entityComponentSignature[entityId].set(componentId, false);
}

template <typename TComponent>
bool Registry::hasComponent(Entity entity) const {
  const int componentId = Component<TComponent>::getid();
  const int entityId = entity.getId();

  return this->entityComponentSignature[entityId].test(componentId);
}

template <typename TComponent>
TComponent& Registry::getComponent(Entity entity) const {
  const int componentId = Component<TComponent>::getid();
  const int entityId = entity.getId();

  auto componentPool = 
    std::static_pointer_cast<Pool<TComponent>>(this->componentsPool[componentId]);

  return componentPool->Get(entityId);
}


template <typename TSystem, typename... TArgs>
void Registry::addSystem(TArgs&&... args) {
  std::shared_ptr<TSystem> newSystem =
    std::make_shared<TSystem>(std::forward<TArgs>(args) ...);

  this->systems.insert(std::make_pair(std::type_index(typeid(TSystem)), newSystem));
}


template <typename TSystem>
void Registry::removeSystem() {
  auto system = this->systems.find(std::type_index(typeid(TSystem)));
  this->systems.erase(system);
}


template <typename TSystem>
bool Registry::hasSystem() const {
  return this->systems.find(std::type_index(typeid(TSystem))) != this->systems.end();
}


template <typename TSystem>
TSystem& Registry::getSystem() const {
  auto system = this->systems.find(std::type_index(typeid(TSystem)));
  return *(std::static_pointer_cast<TSystem>(system->second));
}