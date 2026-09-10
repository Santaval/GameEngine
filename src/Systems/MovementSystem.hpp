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

    for (auto entity : this->getEntities()) {

        auto& transform = entity.getComponent<TransformComponent>();
        const auto& rigidBody = entity.getComponent<RigidBodyComponent>();

        double rotation = transform.rotation;

        double cosR = std::cos(rotation);
        double sinR = std::sin(rotation);

        double worldVelocityX = rigidBody.velocity.x * cosR - rigidBody.velocity.y * sinR;
        double worldVelocityY = rigidBody.velocity.x * sinR + rigidBody.velocity.y * cosR;

        transform.position.x += worldVelocityX * dt;
        transform.position.y += worldVelocityY * dt;
    }
}
};