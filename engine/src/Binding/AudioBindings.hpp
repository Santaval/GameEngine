#pragma once

#include <algorithm>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"

// opts = { volume = 0..1 (1 por defecto), loop = bool (false por defecto) }
// Devuelve un handle > 0, o 0 si el sonido no existe o no hay canal libre
inline int playSound(const std::string& soundId, sol::optional<sol::table> opts) {
    double volume = 1.0;
    bool loop = false;
    if (opts) {
        volume = opts->get_or("volume", 1.0);
        loop = opts->get_or("loop", false);
    }
    return Game::getInstance().getAudio()->playSound(soundId, volume, loop);
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

inline void registerAudioBindings(sol::state& lua) {
  lua.set_function("play_sound", playSound);
  lua.set_function("stop_sound", stopSound);
  lua.set_function("set_sound_volume", setSoundVolume);
  lua.set_function("is_playing", isSoundPlaying);
  lua.set_function("sound_position", soundPosition);
  lua.set_function("sound_duration", soundDuration);
  lua.set_function("play_music", playMusic);
  lua.set_function("stop_music", stopMusic);
}
