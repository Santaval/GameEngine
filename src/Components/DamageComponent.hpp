#pragma once

// Daño que esta entidad inflige al colisionar con algo que tenga
// HealthComponent. El motor no sabe si es una bala, un asteroide o un laser:
// todo se configura desde Lua.
struct DamageComponent
{
  int amount;
  bool destroyOnHit;  // muere en el impacto (balas)
  bool spent;         // ya impacto: no vuelve a aplicar daño mientras agoniza

  DamageComponent(int amount = 0, bool destroyOnHit = false) {
    this->amount = amount;
    this->destroyOnHit = destroyOnHit;
    // kill() es diferido (ver Registry::update): la bala sigue colisionando el
    // resto del frame y sin esta marca mataria a varios blancos de un disparo
    this->spent = false;
  }
};
