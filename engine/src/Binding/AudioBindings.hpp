#pragma once

#include <algorithm>
#include <iostream>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Systems/SpatialAudioSystem.hpp"
#include "../Util/AudioBus.hpp"
#include "../Util/SpatialAudio.hpp"

// Lee bus = "voice" | "sfx" | "ambience" | "music" de una tabla de opciones.
// Si no esta o el nombre no existe, avisa y usa sfx
inline audiobus::Bus readBus(const sol::table& t, const char* fn) {
    audiobus::Bus bus = audiobus::Bus::Sfx;
    std::string name = t.get_or("bus", std::string("sfx"));
    if (!audiobus::parseBus(name, bus)) {
        std::cerr << "[Audio] " << fn << ": unknown bus '" << name << "', using sfx" << std::endl;
        bus = audiobus::Bus::Sfx;
    }
    return bus;
}

// opts = { volume = 0..1 (1 por defecto), loop = bool (false por defecto), bus = "sfx" }
// Devuelve un handle > 0, o 0 si el sonido no existe o no hay canal libre
inline int playSound(const std::string& soundId, sol::optional<sol::table> opts) {
    double volume = 1.0;
    bool loop = false;
    audiobus::Bus bus = audiobus::Bus::Sfx;
    if (opts) {
        volume = opts->get_or("volume", 1.0);
        loop = opts->get_or("loop", false);
        bus = readBus(*opts, "play_sound");
    }
    return Game::getInstance().getAudio()->playSound(soundId, volume, loop, bus);
}

// set_bus_volume(name, v): volumen 0..1 de un bus. Se guarda en settings.json.
// Nombre desconocido: aviso y no hace nada
inline void setBusVolume(const std::string& name, double volume) {
    audiobus::Bus bus = audiobus::Bus::Sfx;
    if (!audiobus::parseBus(name, bus)) {
        std::cerr << "[Audio] set_bus_volume: unknown bus '" << name << "'" << std::endl;
        return;
    }
    Game::getInstance().getAudio()->setBusVolume(bus, volume);
    Game::getInstance().markAudioSettingsDirty();
}

// get_bus_volume(name): volumen 0..1 del bus, o nil si el nombre no existe
inline sol::optional<double> getBusVolume(const std::string& name) {
    audiobus::Bus bus = audiobus::Bus::Sfx;
    if (!audiobus::parseBus(name, bus)) return sol::nullopt;
    return static_cast<double>(Game::getInstance().getAudio()->getBusVolume(bus));
}

// set_ducking({ enabled, amount, fade_ms, buses }): ver Game::applyDuckTable
inline void setDucking(const sol::table& opts) {
    Game::getInstance().applyDuckTable(opts);
}

inline void stopSound(int handle, sol::optional<int> fadeMs) {
    Game::getInstance().getAudio()->stopSound(handle, std::max(0, fadeMs.value_or(0)));
}

inline void setSoundVolume(int handle, double volume) {
    Game::getInstance().getAudio()->setSoundVolume(handle, volume);
}

inline bool isSoundPlaying(int handle) {
    return Game::getInstance().getAudio()->isPlaying(handle);
}

// Segundos reproducidos, o nil si el handle ya no suena
inline sol::optional<double> soundPosition(int handle) {
    double seconds = Game::getInstance().getAudio()->soundPosition(handle);
    if (seconds < 0.0) return sol::nullopt;
    return seconds;
}

// Segundos, o nil si el sonido no existe
inline sol::optional<double> soundDuration(const std::string& soundId) {
    double seconds = Game::getInstance().getAudio()->soundDuration(soundId);
    if (seconds < 0.0) return sol::nullopt;
    return seconds;
}

// opts = { loop = bool (true por defecto), volume = 0..1 (1 por defecto) }
inline void playMusic(const std::string& musicId, sol::optional<int> fadeMs, sol::optional<sol::table> opts) {
    bool loop = true;
    double volume = 1.0;
    if (opts) {
        loop = opts->get_or("loop", true);
        volume = opts->get_or("volume", 1.0);
    }
    Game::getInstance().getAudio()->playMusic(musicId, std::max(0, fadeMs.value_or(0)), loop, volume);
}

inline void stopMusic(sol::optional<int> fadeMs) {
    Game::getInstance().getAudio()->stopMusic(std::max(0, fadeMs.value_or(0)));
}

// set_listener(entity | nil): quien "oye" el audio espacial. nil vuelve al automatico
// (global player_entity, o el centro de la camara si no existe)
inline void setListener(sol::optional<Entity> entity) {
    Game::getInstance().setListener(entity ? entity->getId() : -1);
}

// opts = { volume = 1, loop = false, min_dist = 64, max_dist = 400,
//          rolloff = "linear" | "inverse", pan_width = 0, follow = entity, bus = "sfx" }
// Devuelve un handle como play_sound (0 si falla). Con follow, (x, y) es solo
// la posicion inicial: despues la voz sigue al centro de esa entidad
inline int playSoundAt(const std::string& soundId, double x, double y, sol::optional<sol::table> opts) {
    double volume = 1.0;
    bool loop = false;
    int followId = -1;
    audiobus::Bus bus = audiobus::Bus::Sfx;
    spatial::SpatialParams params;
    if (opts) {
        volume = opts->get_or("volume", 1.0);
        loop = opts->get_or("loop", false);
        bus = readBus(*opts, "play_sound_at");
        params.minDist = opts->get_or("min_dist", params.minDist);
        params.maxDist = opts->get_or("max_dist", params.maxDist);
        params.panWidth = opts->get_or("pan_width", params.panWidth);

        std::string rolloffName = opts->get_or("rolloff", std::string("linear"));
        if (!spatial::parseRolloff(rolloffName, params.rolloff)) {
            std::cerr << "[Audio] play_sound_at: unknown rolloff '" << rolloffName << "', using linear" << std::endl;
        }

        sol::optional<Entity> follow = opts->get<sol::optional<Entity>>("follow");
        if (follow) {
            Registry* registry = Game::getInstance().getRegistry();
            if (registry->hasComponent<TransformComponent>(*follow)) {
                glm::vec2 center = SpatialAudioSystem::entityCenter(*follow);
                x = center.x;
                y = center.y;
                followId = follow->getId();
            }
        }
    }
    return Game::getInstance().getAudio()->playSoundAt(soundId, volume, loop,
        static_cast<float>(x), static_cast<float>(y), params, followId, bus);
}

// Mueve el emisor a (x, y) y deja de seguir a la entidad si la seguia
inline void setEmitterPosition(int handle, double x, double y) {
    Game::getInstance().getAudio()->setEmitterPosition(handle, static_cast<float>(x), static_cast<float>(y));
}

// d = distancia que se usa en lugar de la real para el volumen; nil la quita
inline void setEmitterDistanceOverride(int handle, sol::optional<double> dist) {
    float value = dist ? static_cast<float>(*dist) : -1.0f;
    Game::getInstance().getAudio()->setEmitterDistanceOverride(handle, value);
}

// Crea un emisor por cada objeto de la clase opts.class ("emitter" por defecto) del
// mapa de load_tmx. Propiedades: sound (obligatoria), radius / max_distance,
// min_distance, volume, loop (true por defecto), rolloff, bus (sfx por defecto). La posicion es el
// centro del rectangulo del objeto. Devuelve la lista de handles
inline sol::table emittersFromMap(sol::table map, sol::optional<sol::table> opts, sol::this_state s) {
    sol::state_view lua(s);
    sol::table handles = lua.create_table();

    std::string className = "emitter";
    if (opts) className = opts->get_or("class", className);

    sol::optional<sol::table> objects = map["objects"];
    if (!objects) return handles;

    int count = 0;
    size_t total = objects->size();
    for (size_t i = 1; i <= total; i++) {
        sol::optional<sol::table> object = (*objects)[i];
        if (!object) continue;
        if (object->get_or("type", std::string()) != className) continue;

        sol::optional<sol::table> hasProps = (*object)["properties"];
        if (!hasProps) continue;
        sol::table props = *hasProps;

        std::string sound = props.get_or("sound", std::string());
        if (sound.empty()) {
            std::cerr << "[Audio] emitters_from_map: emitter without 'sound' property, ignored" << std::endl;
            continue;
        }

        spatial::SpatialParams params;
        params.minDist = props.get_or("min_distance", params.minDist);
        // radius es un alias de max_distance
        params.maxDist = props.get_or("max_distance", props.get_or("radius", params.maxDist));
        std::string rolloffName = props.get_or("rolloff", std::string("linear"));
        if (!spatial::parseRolloff(rolloffName, params.rolloff)) {
            std::cerr << "[Audio] emitters_from_map: unknown rolloff '" << rolloffName << "', using linear" << std::endl;
        }

        double x = object->get_or("x", 0.0);
        double y = object->get_or("y", 0.0);
        sol::optional<sol::table> rect = (*object)["rect"];
        if (rect) {
            x = rect->get_or("x", x) + rect->get_or("w", 0.0) / 2.0;
            y = rect->get_or("y", y) + rect->get_or("h", 0.0) / 2.0;
        }

        double volume = props.get_or("volume", 1.0);
        bool loop = props.get_or("loop", true);
        audiobus::Bus bus = readBus(props, "emitters_from_map");
        int handle = Game::getInstance().getAudio()->playSoundAt(sound, volume, loop,
            static_cast<float>(x), static_cast<float>(y), params, -1, bus);
        if (handle != 0) handles[++count] = handle;
    }
    return handles;
}

inline void registerAudioBindings(sol::state& lua) {
  lua.set_function("play_sound", playSound);
  lua.set_function("stop_sound", stopSound);
  lua.set_function("set_sound_volume", setSoundVolume);
  lua.set_function("is_playing", isSoundPlaying);
  lua.set_function("sound_position", soundPosition);
  lua.set_function("sound_duration", soundDuration);
  lua.set_function("play_music", playMusic);
  lua.set_function("stop_music", stopMusic);
  lua.set_function("set_listener", setListener);
  lua.set_function("play_sound_at", playSoundAt);
  lua.set_function("set_emitter_position", setEmitterPosition);
  lua.set_function("set_emitter_distance_override", setEmitterDistanceOverride);
  lua.set_function("emitters_from_map", emittersFromMap);
  lua.set_function("set_bus_volume", setBusVolume);
  lua.set_function("get_bus_volume", getBusVolume);
  lua.set_function("set_ducking", setDucking);
}
