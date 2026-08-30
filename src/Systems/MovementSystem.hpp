#pragma once
#include "../ECS/System.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"

class MovementSystem : public System {
    public:
        MovementSystem() {
            this->requireComponent<RigidBodyComponent>();
            this->requireComponent<TransformComponent>();
        }

    void update(double dt) {
        for(auto entity : this->getEntities()) {
            auto& transform = entity.getComponent<TransformComponent>();
            const auto& regidBody = entity.getComponent<RigidBodyComponent>();

            transform.position.x += regidBody.velocity.x * dt;
            transform.position.y += regidBody.velocity.y * dt;
        }
    }
};