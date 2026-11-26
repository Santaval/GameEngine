#pragma once
#include <glm/glm.hpp>

struct RigidBodyComponent
{
    glm::vec2 velocity;
    glm::vec2 acceleration;
    float maxSpeed; // 0 o menos = sin límite

    RigidBodyComponent(glm::vec2 velocity = glm::vec2(0.0), glm::vec2 acceleration = glm::vec2(0.0), float maxSpeed = 0.0f) {
        this->velocity = velocity;
        this->acceleration = acceleration;
        this->maxSpeed = maxSpeed;
    }
};
