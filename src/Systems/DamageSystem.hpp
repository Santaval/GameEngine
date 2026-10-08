#pragma once

#include <memory>

#include "../Events/CollisionEvent.hpp"
#include "../EventManager/EventManager.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../ECS/System.hpp"
#include "../Util/ColliderCenter.hpp"
#include "../Util/Damage.hpp"
#include "../Util/ImpactDamage.hpp"

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
    // Velocidad con la que se acercan los centros de los colliders, a lo largo
    // de la normal atacante -> blanco (misma formula que bounce_off_ship en
    // asteroid.lua). Positiva = se acercan, <= 0 = se separan o no hay normal.
    // Corre antes que ScriptSystem, asi que ve las velocidades previas al rebote
    static float closingSpeed(Entity attacker, Entity target) {
      glm::dvec2 delta = colliderCenter(target) - colliderCenter(attacker);
      double dist = glm::length(delta);
      if (dist < 0.001) return 0.0f;
      glm::vec2 normal = glm::vec2(delta / dist);

      glm::vec2 attackerVel(0.0f);
      glm::vec2 targetVel(0.0f);
      if (attacker.hasComponent<RigidBodyComponent>()) {
        attackerVel = attacker.getComponent<RigidBodyComponent>().velocity;
      }
      if (target.hasComponent<RigidBodyComponent>()) {
        targetVel = target.getComponent<RigidBodyComponent>().velocity;
      }

      return -glm::dot(targetVel - attackerVel, normal);
    }

    void resolve(Entity attacker, Entity target) {
      if (!attacker.hasComponent<DamageComponent>()) return;

      auto& damage = attacker.getComponent<DamageComponent>();
      if (damage.spent) return;

      // Contra un blanco indestructible el proyectil ni se gasta: lo atraviesa
      if (!target.hasComponent<HealthComponent>()) return;

      int amount = damage.amount;
      if (damage.fullImpactSpeed > 0.0f) {
        amount = impactDamage(amount, closingSpeed(attacker, target),
                              damage.minImpactSpeed, damage.fullImpactSpeed);
        // Un roce no daña ni abre la ventana de invulnerabilidad del blanco.
        // Solo se escala el daño por contacto (sin destroyOnHit), asi que no
        // hay nada que gastar aqui
        if (amount <= 0) return;
      }

      applyDamage(target, amount, attacker);

      // Esto solo quita la bala en esta maquina (killWithHooks nunca manda
      // "despawn"). Si la bala es de otro jugador, el dueño la borra al recibir
      // el "damage" del blanco; si es mia, DamageSync la despawnea en su momento.
      if (damage.destroyOnHit) {
        damage.spent = true;
        killWithHooks(attacker);
      }
    }
};
