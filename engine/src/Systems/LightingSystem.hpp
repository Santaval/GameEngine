#pragma once

#include <SDL2/SDL.h>
#include <algorithm>
#include <cmath>
#include <iostream>
#include <vector>
#include <glm/glm.hpp>
#include "../ECS/System.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/LightComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Util/Culling.hpp"
#include "../Util/Lighting.hpp"

// Iluminacion: un mapa de luz del tamano de la pantalla se llena con el color
// ambiente, cada luz se suma encima como un gradiente radial suave y el resultado
// se multiplica sobre el mundo. Se dibuja despues del mundo y antes del HUD, asi
// que el HUD, los dialogos y los subtitulos nunca se oscurecen.
// Las luces de entidades (LightComponent) las recorre el propio sistema; las luces
// libres (add_light desde Lua) viven en `lights` y se identifican por id.
class LightingSystem : public System {
  public:
    struct FreeLight {
      int id;
      float x, y, radius;
      int r, g, b;
      lighting::Tween intensity;
      float flicker;
    };

    LightingSystem() {
      this->requireComponent<LightComponent>();
      this->requireComponent<TransformComponent>();
    }

    // Devuelve el id (> 0) de la luz, o 0 si el radio no es valido
    int addLight(float x, float y, float radius, int r, int g, int b, float intensity) {
      if (radius <= 0.0f) return 0;
      FreeLight light{ this->nextId++, x, y, radius, r, g, b, lighting::Tween(intensity), 0.0f };
      this->lights.push_back(light);
      return light.id;
    }

    FreeLight* getLight(int id) {
      for (auto& l : this->lights) {
        if (l.id == id) return &l;
      }
      return nullptr;
    }

    void moveLight(int id, float x, float y) {
      FreeLight* l = this->getLight(id);
      if (!l) return;
      l->x = x;
      l->y = y;
    }

    // Lleva la intensidad a `to` en `seconds` (<= 0: de golpe). No borra la luz
    void fadeLight(int id, float to, float seconds) {
      FreeLight* l = this->getLight(id);
      if (l) l->intensity.start(to, seconds);
    }

    void removeLight(int id) {
      this->lights.erase(
        std::remove_if(this->lights.begin(), this->lights.end(),
                       [id](const FreeLight& l) { return l.id == id; }),
        this->lights.end());
    }

    // Color ambiente 0..255 (255, 255, 255 = dia, sin oscuridad)
    void setAmbient(int r, int g, int b, float seconds) {
      this->ambient[0].start(static_cast<float>(r), seconds);
      this->ambient[1].start(static_cast<float>(g), seconds);
      this->ambient[2].start(static_cast<float>(b), seconds);
    }

    // Al cargar una escena: sin luces y ambiente blanco. nextId no se reinicia
    // para que un id viejo de Lua no apunte a una luz de la escena nueva
    void reset() {
      this->lights.clear();
      for (auto& a : this->ambient) a.set(255.0f);
      this->time = 0.0;
    }

    void update(double dt) {
      this->time += dt;
      for (auto& a : this->ambient) a.step(static_cast<float>(dt));
      for (auto& l : this->lights) l.intensity.step(static_cast<float>(dt));
    }

    // Con el ambiente blanco y sin transicion el pase se salta: los dias no cuestan nada
    bool isActive() const {
      if (this->disabled) return false;
      bool animating = this->ambient[0].active() || this->ambient[1].active() || this->ambient[2].active();
      return animating || !lighting::isWhite(this->ambient[0].value, this->ambient[1].value, this->ambient[2].value);
    }

    // Se llama con la pasada del mundo ya dibujada y antes del HUD. `camera` es el
    // rectangulo visible en coordenadas del mundo
    void render(SDL_Renderer* renderer, const SDL_Rect& camera) {
      if (!this->isActive()) return;

      int w = std::max(1, camera.w);
      int h = std::max(1, camera.h);
      if (!this->ensureTextures(renderer, w, h)) return;

      SDL_Texture* previous = SDL_GetRenderTarget(renderer);
      if (SDL_SetRenderTarget(renderer, this->lightMap) != 0) {
        std::cerr << "[Light] SDL_SetRenderTarget failed, lighting off: " << SDL_GetError() << std::endl;
        this->disabled = true;
        return;
      }

      SDL_SetRenderDrawColor(renderer,
        lighting::toByte(this->ambient[0].value),
        lighting::toByte(this->ambient[1].value),
        lighting::toByte(this->ambient[2].value), 255);
      SDL_RenderClear(renderer);

      for (const auto& l : this->lights) {
        float a = l.intensity.value * lighting::flickerFactor(l.flicker, this->time, l.id);
        if (a <= 0.0f) continue;
        if (!lighting::circleVisible(l.x, l.y, l.radius, camera.x, camera.y, camera.w, camera.h)) continue;
        this->drawLight(renderer, l.x - camera.x, l.y - camera.y, l.radius, l.r, l.g, l.b, a);
      }

      for (auto entity : this->getEntities()) {
        if (isDormant(entity)) continue;
        auto& lc = entity.getComponent<LightComponent>();
        if (lc.radius <= 0.0f) continue;
        float a = lc.intensity * lighting::flickerFactor(lc.flicker, this->time, entity.getId() + 7919);
        if (a <= 0.0f) continue;
        glm::vec2 c = entityCenter(entity) + lc.offset;
        if (!lighting::circleVisible(c.x, c.y, lc.radius, camera.x, camera.y, camera.w, camera.h)) continue;
        this->drawLight(renderer, c.x - camera.x, c.y - camera.y, lc.radius, lc.r, lc.g, lc.b, a);
      }

      // SDL restaura viewport, escala y tamano logico al volver al target anterior
      SDL_SetRenderTarget(renderer, previous);
      SDL_RenderCopy(renderer, this->lightMap, nullptr, nullptr);
    }

    // Antes de SDL_DestroyRenderer
    void releaseTextures() {
      if (this->lightMap) SDL_DestroyTexture(this->lightMap);
      if (this->gradient) SDL_DestroyTexture(this->gradient);
      this->lightMap = nullptr;
      this->gradient = nullptr;
      this->mapW = this->mapH = 0;
    }

  private:
    // Centro de la entidad: position es la esquina superior izquierda, asi que se
    // suma medio sprite (con la escala). Copia de SpatialAudioSystem::entityCenter
    // (no se incluye ese header porque arrastra AudioManager)
    static glm::vec2 entityCenter(Entity entity) {
      auto& transform = entity.getComponent<TransformComponent>();
      glm::vec2 center = transform.position;
      if (entity.hasComponent<SpriteComponent>()) {
        auto& sprite = entity.getComponent<SpriteComponent>();
        center.x += (sprite.width / 2.0f) * transform.scale.x;
        center.y += (sprite.height / 2.0f) * transform.scale.y;
      }
      return center;
    }

    void drawLight(SDL_Renderer* renderer, float sx, float sy, float radius,
                   int r, int g, int b, float alpha01) {
      SDL_FRect dst = { sx - radius, sy - radius, radius * 2.0f, radius * 2.0f };
      SDL_SetTextureColorMod(this->gradient,
        lighting::toByte(static_cast<float>(r)),
        lighting::toByte(static_cast<float>(g)),
        lighting::toByte(static_cast<float>(b)));
      SDL_SetTextureAlphaMod(this->gradient, lighting::toByte(std::min(alpha01, 1.0f) * 255.0f));
      SDL_RenderCopyF(renderer, this->gradient, nullptr, &dst);
    }

    // Crea (o recrea si cambio el tamano) el mapa de luz y el gradiente. false si no se puede
    bool ensureTextures(SDL_Renderer* renderer, int w, int h) {
      if (this->disabled) return false;

      if (!SDL_RenderTargetSupported(renderer)) {
        std::cerr << "[Light] render targets not supported, lighting off" << std::endl;
        this->disabled = true;
        return false;
      }

      if (!this->gradient) {
        const int size = lighting::GRADIENT_SIZE;
        SDL_Texture* tex = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                             SDL_TEXTUREACCESS_STATIC, size, size);
        if (!tex) {
          std::cerr << "[Light] gradient texture failed, lighting off: " << SDL_GetError() << std::endl;
          this->disabled = true;
          return false;
        }
        // RGB blanco y la caida en el alfa: ADD hace srcRGB * srcA + dst
        std::vector<Uint32> pixels(static_cast<size_t>(size) * size);
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            pixels[static_cast<size_t>(y) * size + x] =
              (static_cast<Uint32>(lighting::gradientAlpha(x, y, size)) << 24) | 0x00FFFFFFu;
          }
        }
        SDL_UpdateTexture(tex, nullptr, pixels.data(), size * static_cast<int>(sizeof(Uint32)));
        SDL_SetTextureBlendMode(tex, SDL_BLENDMODE_ADD);
        // El hint global es nearest (pixel-perfect): aqui se quiere filtro lineal
        SDL_SetTextureScaleMode(tex, SDL_ScaleModeLinear);
        this->gradient = tex;
      }

      if (!this->lightMap || w != this->mapW || h != this->mapH) {
        if (this->lightMap) SDL_DestroyTexture(this->lightMap);
        this->lightMap = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_ARGB8888,
                                           SDL_TEXTUREACCESS_TARGET, w, h);
        if (!this->lightMap) {
          std::cerr << "[Light] light map failed, lighting off: " << SDL_GetError() << std::endl;
          this->disabled = true;
          return false;
        }
        SDL_SetTextureScaleMode(this->lightMap, SDL_ScaleModeLinear);
        // dst = dst * src: multiplica el mundo por el mapa de luz (el alfa de dst no cambia)
        SDL_BlendMode multiply = SDL_ComposeCustomBlendMode(
          SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_SRC_COLOR, SDL_BLENDOPERATION_ADD,
          SDL_BLENDFACTOR_ZERO, SDL_BLENDFACTOR_ONE, SDL_BLENDOPERATION_ADD);
        if (SDL_SetTextureBlendMode(this->lightMap, multiply) != 0) {
          SDL_SetTextureBlendMode(this->lightMap, SDL_BLENDMODE_MOD);
        }
        this->mapW = w;
        this->mapH = h;
      }
      return true;
    }

    std::vector<FreeLight> lights;
    int nextId = 1;
    lighting::Tween ambient[3] = { lighting::Tween(255.0f), lighting::Tween(255.0f), lighting::Tween(255.0f) };
    double time = 0.0;
    SDL_Texture* lightMap = nullptr;
    int mapW = 0, mapH = 0;
    SDL_Texture* gradient = nullptr;
    bool disabled = false;
};
