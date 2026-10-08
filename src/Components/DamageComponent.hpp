#pragma once

// Daño que esta entidad inflige al colisionar con algo que tenga
// HealthComponent. El motor no sabe si es una bala, un asteroide o un laser:
// todo se configura desde Lua.
struct DamageComponent
{
  int amount;
  bool destroyOnHit;  // muere en el impacto (balas)
  bool fromPlayer;    // arma de jugador: respeta la regla de pvp (ver DamageSync)
  bool spent;         // ya impacto: no vuelve a aplicar daño mientras agoniza
  // Escala por velocidad de impacto (opt-in). Con fullImpactSpeed > 0, amount es
  // el tope: por debajo de minImpactSpeed no hay daño y en fullImpactSpeed (px/s,
  // velocidad de cierre) se aplica entero. 0 = daño plano (balas, lasers...)
  float minImpactSpeed;
  float fullImpactSpeed;

  DamageComponent(int amount = 0, bool destroyOnHit = false, bool fromPlayer = false,
                  float minImpactSpeed = 0.0f, float fullImpactSpeed = 0.0f) {
    this->amount = amount;
    this->destroyOnHit = destroyOnHit;
    // kill() es diferido (ver Registry::update): la bala sigue colisionando el
    // resto del frame y sin esta marca mataria a varios blancos de un disparo
    this->fromPlayer = fromPlayer;
    this->spent = false;
    this->minImpactSpeed = minImpactSpeed;
    this->fullImpactSpeed = fullImpactSpeed;
  }
};
