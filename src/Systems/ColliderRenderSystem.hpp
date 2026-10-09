#pragma once

#include <SDL2/SDL.h>
#include <algorithm>
#include <cmath>
#include <vector>
#include <glm/glm.hpp>

#include "../ECS/System.hpp"
#include "../Components/CircleColliderComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Util/Culling.hpp"

// Overlay de debug: dibuja el contorno de cada CircleColliderComponent tal
// como lo usa CollisionSystem, para poder ver a ojo si el hitbox real
// coincide con el sprite. Se activa/desactiva desde Game::render(); este
// sistema no conoce el flag, solo dibuja cuando lo llaman.
class ColliderRenderSystem : public System {
    private:
        // Cantidad de segmentos de la polilínea que aproxima el círculo:
        // pocos para radios chicos (barato), más para radios grandes
        // (que no se note el poligonito)
        static constexpr int MIN_SEGMENTS = 12;
        static constexpr int MAX_SEGMENTS = 64;

        // Verde para colliders normales
        static const Uint8 COLOR_R = 0;
        static const Uint8 COLOR_G = 255;
        static const Uint8 COLOR_B = 0;

        // Ámbar para colliders con dueño (balas): así se distinguen de un
        // vistazo los que tienen filtro de colisión por ownerId
        static const Uint8 OWNED_COLOR_R = 255;
        static const Uint8 OWNED_COLOR_G = 170;
        static const Uint8 OWNED_COLOR_B = 0;

        static const Uint8 ALPHA = 160;

        // Medio largo de la cruz central, en píxeles de pantalla
        static constexpr int CROSS_HALF_SIZE = 3;

        // Reutilizado entidad a entidad y frame a frame para no reservar
        // memoria en el hot path (patrón de pathPoints en PathRenderSystem)
        std::vector<SDL_Point> circlePoints;

    public:
        ColliderRenderSystem() {
            // Los mismos dos componentes que CollisionSystem: así el overlay
            // dibuja exactamente lo que se testea, ni más ni menos.
            this->requireComponent<CircleColliderComponent>();
            this->requireComponent<TransformComponent>();
        }

        void update(SDL_Renderer* renderer, const SDL_Rect& camera) {
            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);

            for (auto entity : this->getEntities()) {
                if (isDormant(entity)) continue;
                const auto& collider = entity.getComponent<CircleColliderComponent>();
                const auto& transform = entity.getComponent<TransformComponent>();

                // transform.position es la esquina superior izquierda del
                // sprite (ver RenderSystem y makeAsteroid en scene_01.lua),
                // así que el centro se obtiene sumando medio ancho/alto.
                glm::vec2 center(
                    transform.position.x + (collider.width / 2) * transform.scale.x,
                    transform.position.y + (collider.height / 2) * transform.scale.y
                );

                // A propósito solo se escala con scale.x, igual que
                // CollisionSystem.hpp: el overlay tiene que mostrar el
                // hitbox real, no una versión "mejorada" del cálculo.
                int radius = static_cast<int>(collider.radius * transform.scale.x);

                if (this->outsideCamera(center, radius, camera)) continue;

                int screenX = static_cast<int>(center.x) - camera.x;
                int screenY = static_cast<int>(center.y) - camera.y;

                bool owned = collider.ownerId != -1;
                if (owned) {
                    SDL_SetRenderDrawColor(renderer, OWNED_COLOR_R, OWNED_COLOR_G, OWNED_COLOR_B, ALPHA);
                } else {
                    SDL_SetRenderDrawColor(renderer, COLOR_R, COLOR_G, COLOR_B, ALPHA);
                }

                this->drawCircle(renderer, screenX, screenY, radius);
                this->drawCross(renderer, screenX, screenY);
            }

            SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_NONE);
        }

    private:
        // Con ~400 asteroides con collider en la escena, dibujar 400
        // círculos por frame sin descartar los que están fuera de cámara
        // se nota a 30 FPS. Se compara el AABB del círculo contra el rect
        // de cámara.
        static bool outsideCamera(const glm::vec2& center, int radius, const SDL_Rect& camera) {
            return center.x + radius < camera.x ||
                center.x - radius > camera.x + camera.w ||
                center.y + radius < camera.y ||
                center.y - radius > camera.y + camera.h;
        }

        // El motor no tiene ninguna primitiva de círculo (SDL2 puro, sin
        // SDL2_gfx): se aproxima el contorno con una polilínea y se emite
        // en una sola llamada a SDL_RenderDrawLines.
        void drawCircle(SDL_Renderer* renderer, int cx, int cy, int radius) {
            int segments = std::clamp(radius / 2, MIN_SEGMENTS, MAX_SEGMENTS);

            this->circlePoints.clear();
            for (int i = 0; i < segments; i++) {
                double angle = (2.0 * M_PI * i) / segments;
                this->circlePoints.push_back(SDL_Point{
                    cx + static_cast<int>(std::round(radius * std::cos(angle))),
                    cy + static_cast<int>(std::round(radius * std::sin(angle)))
                });
            }
            // Repetir el primer punto al final para cerrar el lazo
            this->circlePoints.push_back(this->circlePoints.front());

            SDL_RenderDrawLines(renderer, this->circlePoints.data(),
                static_cast<int>(this->circlePoints.size()));
        }

        // Cruz central: hace visibles los colliders de radio chico, donde
        // el contorno solo puede llegar a ser un puntito.
        static void drawCross(SDL_Renderer* renderer, int cx, int cy) {
            SDL_RenderDrawLine(renderer, cx - CROSS_HALF_SIZE, cy, cx + CROSS_HALF_SIZE, cy);
            SDL_RenderDrawLine(renderer, cx, cy - CROSS_HALF_SIZE, cx, cy + CROSS_HALF_SIZE);
        }
};
