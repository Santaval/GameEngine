#pragma once

// Traza la trayectoria prevista de la entidad: se reintegra su movimiento
// hacia adelante y se dibuja punteado. Los parámetros de estilo viven en
// el PathRenderSystem, aquí solo está el interruptor.
struct PathComponent
{
  bool active;

  PathComponent(bool active = true) {
    this->active = active;
  }
};
