#pragma once

#include <glm/glm.hpp>

// Luz circular centrada en la entidad (centro del sprite + offset). Colores 0..255,
// intensity 0..1 (se recorta al dibujar), flicker 0..1 (cuanto baja la luz al parpadear)
struct LightComponent {
  float radius;
  int r, g, b;
  float intensity;
  float flicker;
  glm::vec2 offset;

  LightComponent(float radius = 64.0f, int r = 255, int g = 255, int b = 255,
                 float intensity = 1.0f, float flicker = 0.0f,
                 glm::vec2 offset = glm::vec2(0.0f)) {
    this->radius = radius;
    this->r = r;
    this->g = g;
    this->b = b;
    this->intensity = intensity;
    this->flicker = flicker;
    this->offset = offset;
  }
};
