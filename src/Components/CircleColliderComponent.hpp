#pragma once

struct CircleColliderComponent
{
  int radius;
  int width;
  int height;
  int ownerId;

  CircleColliderComponent(int radius = 0, int width = 0, int height = 0, int ownerId = -1) {
    this->radius = radius;
    this->height = height;
    this->width = width;
    this->ownerId = ownerId;
  }
};