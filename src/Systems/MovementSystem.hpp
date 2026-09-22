#pragma once
#include <cmath>
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
            auto& rigidBody = entity.getComponent<RigidBodyComponent>(); // ya no puede ser const&

            double rotation = transform.rotation;
            double cosR = std::cos(rotation);
            double sinR = std::sin(rotation);

            // 1) Rotar la ACELERACIÓN local (dirección del empuje) al espacio mundo
            double worldAccelX = rigidBody.acceleration.x * cosR - rigidBody.acceleration.y * sinR;
            double worldAccelY = rigidBody.acceleration.x * sinR + rigidBody.acceleration.y * cosR;

            // 2) Integrar velocidad: se ACUMULA, nunca se resetea ni se re-rota
            rigidBody.velocity.x += worldAccelX * dt;
            rigidBody.velocity.y += worldAccelY * dt;

            // 2.5) Limitar la rapidez máxima (0 o menos = sin límite)
            if (rigidBody.maxSpeed > 0.0f) {
                double speedSq = rigidBody.velocity.x * rigidBody.velocity.x + rigidBody.velocity.y * rigidBody.velocity.y;
                double maxSpeedSq = static_cast<double>(rigidBody.maxSpeed) * rigidBody.maxSpeed;
                if (speedSq > maxSpeedSq) {
                    double scale = rigidBody.maxSpeed / std::sqrt(speedSq);
                    rigidBody.velocity.x *= scale;
                    rigidBody.velocity.y *= scale;
                }
            }

            // 3) Integrar posición desde la velocidad ya acumulada (espacio mundo)
            transform.position.x += rigidBody.velocity.x * dt;
            transform.position.y += rigidBody.velocity.y * dt;
    }
    }
};