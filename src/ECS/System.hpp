#pragma once
#include <bitset>
#include "Entity.hpp"
#include <vector>
#include "IComponent.hpp"


unsigned int const MAX_COMPONENTS = 64;

typedef std::bitset<MAX_COMPONENTS> Signature;

class System {
  private:
    Signature componentSignature;
    std::vector<Entity> entities;
    
    public:
      void addEntity(Entity entity);
      void removeEntity(Entity entity);
      void clearEntities();
      std::vector<Entity> getEntities() const;
      const Signature& getComponentSignature() const;

      template <typename TComponent>
      void requireComponent();
};

   template <typename TComponent>
   void System::requireComponent() {
    const int componentId = Component<TComponent>::getId();
    this->componentSignature.set(componentId);
   }
