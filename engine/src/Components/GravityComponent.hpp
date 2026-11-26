#pragma once

// Cuerpo que participa en la gravedad. attracts = fuente (jala a los demas),
// affected = receptor (los demas lo jalan; ademas necesita RigidBody).
// Quien no tenga este componente (minerales, pickups...) nunca se ve afectado.
struct GravityComponent
{
  float mass;      // solo importa si attracts = true
  bool attracts;   // jala a otros cuerpos
  bool affected;   // es jalado por otros cuerpos
  float range;     // alcance maximo de su atraccion en px; 0 = ilimitado

  GravityComponent(float mass = 1.0f, bool attracts = false, bool affected = true, float range = 0.0f) {
    this->mass = mass;
    this->attracts = attracts;
    this->affected = affected;
    this->range = range;
  }
};
