#pragma once
#include <glm/glm.hpp>

struct RigidBodyComponent
{
    glm::vec2 velocity;
    glm::vec2 acceleration;

    RigidBodyComponent(glm::vec2 velocity = glm::vec2(0.0), glm::vec2 acceleration = glm::vec2(0.0)) {
        this->velocity = velocity;
        this->acceleration = acceleration;
    }
};
