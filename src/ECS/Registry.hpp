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

  public:
    Registry();
    ~Registry();

    void update();

    Entity createEntity();
    void killEntity(Entity entity);

    // components managment

    template <typename TComponent, typename... TArgs>
    void AddComponent(Entity Entity, TArgs&&... args);

    template <typename TComponent>
    void removeComponent(Entity entity);

    template <typename TComponent>
    bool hasComponent(Entity entity) const;

    template <typename TComponent>
    TComponent& getComponent(Entity entity) const;

    // systems managment

    template <typename TSystem, typename... TArgs>
    void AddSystem(TArgs&&... args);

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
void Registry::AddComponent(Entity entity, TArgs&&... args) {
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
