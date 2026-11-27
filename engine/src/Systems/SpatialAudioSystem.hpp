#pragma once

#include <glm/glm.hpp>
#include "../ECS/System.hpp"
#include "../ECS/Entity.hpp"
#include "../Audio/AudioManager.hpp"
#include "../Components/SoundEmitterComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Util/Culling.hpp"
#include "../Util/SpatialAudio.hpp"

// Arranca la voz de cada SoundEmitterComponent la primera vez que lo ve. Despues
// AudioManager::updateSpatial mueve la voz con la entidad (followEntity).
class SpatialAudioSystem : public System {
  public:
    SpatialAudioSystem() {
      this->requireComponent<SoundEmitterComponent>();
      this->requireComponent<TransformComponent>();
    }

    // Centro de la entidad: position es la esquina superior izquierda, asi que
    // se suma medio sprite (con la escala) si lo tiene; si no, la posicion
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

    void update(AudioManager& audio) {
      for (auto entity : this->getEntities()) {
        auto& emitter = entity.getComponent<SoundEmitterComponent>();
        if (emitter.started) continue;
        // Un emisor dormido arranca cuando vuelve al area activa
        if (isDormant(entity)) continue;

        // Se marca antes de pedir la voz: si falla (sin canal, sonido inexistente) no se reintenta cada frame
        emitter.started = true;

        glm::vec2 pos = entityCenter(entity) + emitter.offset;
        spatial::SpatialParams params;
        params.minDist = emitter.minDist;
        params.maxDist = emitter.maxDist;
        params.rolloff = emitter.rolloff;

        emitter.handle = audio.playSoundAt(emitter.sound, emitter.volume, emitter.loop,
          pos.x, pos.y, params, entity.getId(), emitter.bus);
      }
    }
};
