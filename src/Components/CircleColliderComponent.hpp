#pragma once

struct CircleColliderComponent
{
  int radius;
  int width;
  int height;

  CircleColliderComponent(int radius = 0, int width = 0, int height = 0) {
    this->radius = radius;
    this->height = height;
    this->width = width;
  }
};