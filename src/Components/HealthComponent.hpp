#pragma once

#include <SDL2/SDL.h>

// Vida de una entidad. Sin este componente la entidad es indestructible: el
// DamageSystem solo resta vida a quien lo tiene.
//
// La invulnerabilidad se mide con un timestamp en vez de un contador que haya
// que descontar cada frame: addComponent no reevalua la pertenencia a sistemas
// (ver Registry::update), asi que un sistema que iterase entidades se perderia
// a todas las que reciben vida en runtime.
struct HealthComponent
{
  int health;
  int maxHealth;
  double invulnerability;  // segundos de gracia tras recibir daño (0 = sin gracia)
  Uint32 lastDamageTicks;  // SDL_GetTicks() del ultimo golpe recibido
  bool isPlayer;           // nave de jugador: protegida por la regla de pvp (ver DamageSync)

  HealthComponent(int maxHealth = 1, int health = -1, double invulnerability = 0.0, bool isPlayer = false) {
    this->maxHealth = maxHealth;
    // health < 0 significa "empieza a tope"
    this->health = (health < 0) ? maxHealth : health;
    this->invulnerability = invulnerability;
    this->lastDamageTicks = 0;
    this->isPlayer = isPlayer;
  }
};
