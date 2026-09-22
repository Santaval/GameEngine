#pragma once

#include <memory>

#include "../Events/CollisionEvent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../ECS/System.hpp"
#include "../Util/Damage.hpp"

// Traduce colisiones en daño. Es generico: no sabe que es una bala ni que es
// una nave, solo mira si el que golpea tiene DamageComponent y si el golpeado
// tiene HealthComponent. Lo demas se configura desde Lua.
//
// Es puramente event-driven (nunca usa getEntities), asi que funciona tambien
// con entidades que reciben vida o daño despues de haber sido creadas.
class DamageSystem : public System {
  public:
    DamageSystem() {
      this->requireComponent<CircleColliderComponent>();
    }

    void subscribeToCollisionEvent(std::unique_ptr<EventManager>& eventManager) {
      eventManager->subscribe<CollisionEvent, DamageSystem>(this, &DamageSystem::onCollision);
    }

    void onCollision(CollisionEvent&  e) {
      // Simetrico: cada uno puede dañar al otro en el mismo impacto
      this->resolve(e.a, e.b);
      this->resolve(e.b, e.a);
    }

  private:
    void resolve(Entity attacker, Entity target) {
      if (!attacker.hasComponent<DamageComponent>()) return;

      auto& damage = attacker.getComponent<DamageComponent>();
      if (damage.spent) return;

      // Contra un blanco indestructible el proyectil ni se gasta: lo atraviesa
      if (!target.hasComponent<HealthComponent>()) return;

      applyDamage(target, damage.amount, attacker);

      if (damage.destroyOnHit) {
        damage.spent = true;
        killWithHooks(attacker);
      }
    }
};
