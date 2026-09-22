#pragma once

#include <SDL2/SDL.h>
#include <algorithm>
#include <cmath>
#include <vector>
#include <glm/glm.hpp>

#include "../ECS/System.hpp"
#include "../Components/PathComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Game/Game.hpp"

// Dibuja una línea punteada y desvaneciente con la trayectoria prevista de
// la entidad: reintegra su movimiento hacia adelante (misma física que
// MovementSystem) y la traza en pantalla. Solo lectura: nunca toca el
// estado real de la entidad.
//
// OJO: este sistema requiere TransformComponent + RigidBodyComponent
// únicamente, NO PathComponent. Registry::update() asigna la pertenencia a
// un sistema una sola vez, cuando la entidad pasa por entitiesToBeAdded; si
// se exigiera PathComponent aquí, un add_path() hecho en caliente desde Lua
// nunca haría que la entidad entrara a este sistema. En su lugar se filtra
// PathComponent adentro del loop, entidad por entidad.
class PathRenderSystem : public System {
    private:
        // Cuánto tiempo hacia adelante se predice la trayectoria
        static constexpr double HORIZON_SECONDS = 2.0;

        // Por debajo de esta velocidad, sin empuje, no se dibuja nada
        // (una nave detenida no deja un muñón de línea)
        static constexpr double MIN_SPEED = 5.0;

        // Ritmo del punteado en píxeles de pantalla
        static constexpr double DASH_PIXELS = 10.0;
        static constexpr double GAP_PIXELS = 8.0;

        // Paso de integración: rango sano y valor de respaldo si deltaTime
        // llega en 0 (primer frame)
        static constexpr double MIN_STEP = 1.0 / 240.0;
        static constexpr double MAX_STEP = 1.0 / 10.0;

        // Mismo cian que la línea de velocidad del HUD (player.lua)
        static const Uint8 COLOR_R = 120;
        static const Uint8 COLOR_G = 220;
        static const Uint8 COLOR_B = 255;

        // Alfa inicial (tenue); se desvanece a 0 en el horizonte
        static const Uint8 ALPHA_START = 110;

        // Reutilizados entidad a entidad para no reservar memoria cada frame
        std::vector<glm::vec2> pathPoints;
        std::vector<double> cumulativeLength;

    public:
        PathRenderSystem() {
            this->requireComponent<TransformComponent>();
            this->requireComponent<RigidBodyComponent>();
        }

        void update(SDL_Renderer* renderer, const SDL_Rect& camera, double deltaTime) {
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

            for (auto entity : this->getEntities()) {
                if (!entity.hasComponent<PathComponent>()) continue;

                const auto& path = entity.getComponent<PathComponent>();
                if (!path.active) continue;

                const auto& transform = entity.getComponent<TransformComponent>();
                const auto& rigidBody = entity.getComponent<RigidBodyComponent>();

                bool hasThrust = rigidBody.acceleration.x != 0.0f || rigidBody.acceleration.y != 0.0f;
                if (glm::length(rigidBody.velocity) < MIN_SPEED && !hasThrust) continue;

                this->simulate(transform, rigidBody, deltaTime);
                if (this->pathPoints.size() < 2) continue;

                glm::vec2 centerOffset(0.0f, 0.0f);
                if (entity.hasComponent<SpriteComponent>()) {
                    const auto& sprite = entity.getComponent<SpriteComponent>();
                    centerOffset.x = sprite.width * transform.scale.x / 2.0f;
                    centerOffset.y = sprite.height * transform.scale.y / 2.0f;
                }

                this->buildCumulativeLength();
                this->drawDashes(renderer, camera, centerOffset);
            }

            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
        }

    private:
        // Repite la integración semi-implícita de MovementSystem hacia
        // adelante, sobre copias locales, y llena this->pathPoints.
        // La rotación se mantiene constante durante todo el horizonte: el
        // jugador apunta con el mouse y eso no es predecible.
        void simulate(const TransformComponent& transform, const RigidBodyComponent& rigidBody, double deltaTime) {
            double rotation = transform.rotation;
            double cosR = std::cos(rotation);
            double sinR = std::sin(rotation);

            double worldAccelX = rigidBody.acceleration.x * cosR - rigidBody.acceleration.y * sinR;
            double worldAccelY = rigidBody.acceleration.x * sinR + rigidBody.acceleration.y * cosR;

            double step = deltaTime;
            if (step <= 0.0) step = 1.0 / FPS;
            step = std::clamp(step, MIN_STEP, MAX_STEP);

            int steps = static_cast<int>(HORIZON_SECONDS / step);

            glm::vec2 simPosition = transform.position;
            glm::vec2 simVelocity = rigidBody.velocity;

            this->pathPoints.clear();
            this->pathPoints.push_back(simPosition);

            for (int i = 0; i < steps; i++) {
                simVelocity.x += static_cast<float>(worldAccelX * step);
                simVelocity.y += static_cast<float>(worldAccelY * step);

                simPosition.x += simVelocity.x * static_cast<float>(step);
                simPosition.y += simVelocity.y * static_cast<float>(step);

                this->pathPoints.push_back(simPosition);
            }
        }

        // Tabla de longitud acumulada sobre this->pathPoints, para poder
        // remuestrear por longitud de arco y que los guiones no cambien de
        // tamaño con la velocidad.
        void buildCumulativeLength() {
            this->cumulativeLength.assign(this->pathPoints.size(), 0.0);

            for (size_t i = 1; i < this->pathPoints.size(); i++) {
                double segmentLength = glm::length(this->pathPoints[i] - this->pathPoints[i - 1]);
                this->cumulativeLength[i] = this->cumulativeLength[i - 1] + segmentLength;
            }
        }

        // Punto sobre la polilínea a longitud de arco `s`. `segmentIndex` es
        // un índice de avance monótono: como `s` solo crece entre llamadas
        // sucesivas dentro de un mismo dibujado, el recorrido total es O(n+m).
        glm::vec2 pointAt(double s, size_t& segmentIndex) const {
            size_t lastSegment = this->pathPoints.size() - 2;

            while (segmentIndex < lastSegment && this->cumulativeLength[segmentIndex + 1] < s) {
                segmentIndex++;
            }

            double segmentStart = this->cumulativeLength[segmentIndex];
            double segmentEnd = this->cumulativeLength[segmentIndex + 1];
            double segmentLength = segmentEnd - segmentStart;

            double t = segmentLength > 0.0 ? (s - segmentStart) / segmentLength : 0.0;
            t = std::clamp(t, 0.0, 1.0);

            const glm::vec2& a = this->pathPoints[segmentIndex];
            const glm::vec2& b = this->pathPoints[segmentIndex + 1];
            return a + static_cast<float>(t) * (b - a);
        }

        static bool outsideCamera(const glm::vec2& point, const SDL_Rect& camera) {
            return point.x < camera.x || point.x > camera.x + camera.w ||
                point.y < camera.y || point.y > camera.y + camera.h;
        }

        void drawDashes(SDL_Renderer* renderer, const SDL_Rect& camera, const glm::vec2& centerOffset) {
            double total = this->cumulativeLength.back();
            if (total <= 0.0) return;

            size_t segmentIndex = 0;
            double s = 0.0;

            while (s < total) {
                double s2 = std::min(s + DASH_PIXELS, total);

                glm::vec2 p1 = this->pointAt(s, segmentIndex) + centerOffset;
                glm::vec2 p2 = this->pointAt(s2, segmentIndex) + centerOffset;

                if (!outsideCamera(p1, camera) || !outsideCamera(p2, camera)) {
                    Uint8 alpha = static_cast<Uint8>(ALPHA_START * (1.0 - s / total));

                    SDL_SetRenderDrawColor(renderer, COLOR_R, COLOR_G, COLOR_B, alpha);
                    SDL_RenderDrawLine(renderer,
                        static_cast<int>(p1.x) - camera.x, static_cast<int>(p1.y) - camera.y,
                        static_cast<int>(p2.x) - camera.x, static_cast<int>(p2.y) - camera.y);
                }

                s += DASH_PIXELS + GAP_PIXELS;
            }
        }
};
