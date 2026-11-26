#pragma once

// Caja de colision alineada a los ejes (la rotacion se ignora). El offset es
// desde la esquina superior izquierda del sprite (transform.position) y,
// igual que width/height, se escala con transform.scale.
//
//   solid   - bloquea a los movers (otras cajas con mover = true)
//   trigger - no bloquea ni emite CollisionEvent: genera enter/stay/exit
//             contra cualquier collider que no sea trigger. Gana sobre solid.
//   mover   - MovementSystem no integra su posicion: BoxColliderSystem la
//             mueve con barrido contra paredes y cajas solidas
//   enabled - false = el collider no existe para nadie
//   ownerId - como en CircleColliderComponent: no colisiona con su dueño
//   contacts- lados bloqueados en el ultimo movimiento (bits de Contact)
struct BoxColliderComponent
{
  float offsetX;
  float offsetY;
  float width;
  float height;
  bool solid;
  bool trigger;
  bool mover;
  bool enabled;
  int ownerId;
  unsigned contacts;

  BoxColliderComponent(float width = 0.0f, float height = 0.0f, float offsetX = 0.0f,
    float offsetY = 0.0f, bool solid = false, bool trigger = false, bool mover = false,
    int ownerId = -1) {
      this->width = width;
      this->height = height;
      this->offsetX = offsetX;
      this->offsetY = offsetY;
      this->solid = solid;
      this->trigger = trigger;
      this->mover = mover;
      this->enabled = true;
      this->ownerId = ownerId;
      this->contacts = 0;
  }
};
