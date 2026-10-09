#pragma once

#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../Components/NetworkComponent.hpp"
#include "../Network/LuaJson.hpp"
#include "../Network/NetClient.hpp"
#include "../Network/NetworkRegistry.hpp"
#include "../Network/NetworkScripting.hpp"

// Red multijugador. Offline todo devuelve un valor seguro (sin sesion, host,
// todo local) para que los scripts de un jugador corran sin cambios.
// La logica pesada vive en NetworkScripting; aqui solo se adapta a Lua.

inline bool netIsOnline() {
  return Game::getInstance().getNetClient()->isOnline();
}

inline std::string netMyId() {
  auto& net = *Game::getInstance().getNetClient();
  return net.isOnline() ? net.getMyPlayerId() : std::string();
}

inline bool netIsHost() {
  auto& net = *Game::getInstance().getNetClient();
  return net.isOnline() ? net.isHost() : true;
}

inline sol::table netPeers(sol::this_state s) {
  sol::state_view lua(s);
  sol::table peers = lua.create_table();
  auto& net = *Game::getInstance().getNetClient();
  if (net.isOnline()) {
    int index = 1;
    for (const auto& id : net.getPeers()) {
      peers[index++] = id;
    }
  }
  return peers;
}

inline sol::table netRoomSettings(sol::this_state s) {
  sol::state_view lua(s);
  sol::table settings = lua.create_table();
  settings["pvp"] = Game::getInstance().getDamageSync()->pvpEnabled();
  // nil mientras no hay semilla (0 = sin fijar)
  const uint32_t seed = Game::getInstance().getDamageSync()->getMatchSeed();
  if (seed != 0) settings["seed"] = static_cast<int64_t>(seed);
  return settings;
}

// Semilla del mapa. A diferencia de net_set_pvp tambien vale offline (sin red
// solo cambia el valor local); online solo el host. 0 se rechaza (= sin fijar)
inline bool netSetMatchSeed(int64_t seed) {
  auto& net = *Game::getInstance().getNetClient();
  if (net.isOnline() && !net.isHost()) return false;
  if (seed <= 0 || seed > 0xFFFFFFFFLL) return false;
  Game::getInstance().getDamageSync()->setMatchSeed(static_cast<uint32_t>(seed));
  return true;
}

// Id del host actual ("" offline o sin welcome)
inline std::string netHostId() {
  auto& net = *Game::getInstance().getNetClient();
  return net.isOnline() ? net.getHostId() : std::string();
}

// Solo el host puede cambiar los ajustes de la sala
inline bool netSetPvp(bool enabled) {
  auto& net = *Game::getInstance().getNetClient();
  if (!net.isOnline() || !net.isHost()) return false;
  Game::getInstance().getDamageSync()->setPvp(enabled);
  return true;
}

inline bool netSend(const std::string& type, sol::object data, sol::optional<std::string> to) {
  return Game::getInstance().getNetworkScripting()->send(type, luaToJson(data), to.value_or(""));
}

inline void netOn(const std::string& type, sol::protected_function fn) {
  Game::getInstance().getNetworkScripting()->on(type, fn);
}

// Entidad local construida desde un prefab: igual que net_spawn pero sin
// identidad ni anuncio de red (cada cliente la construye por su cuenta, p. ej.
// las rocas de los chunks a partir de la semilla). nil si el prefab falla.
inline sol::object spawnLocal(const std::string& scriptPath, sol::object state, sol::this_state s) {
  auto entity = Game::getInstance().getNetworkScripting()->buildFromPrefab(scriptPath, luaToJson(state));
  if (!entity) {
    return sol::make_object(s, sol::lua_nil);
  }
  return sol::make_object(s, *entity);
}

inline sol::object netSpawn(const std::string& scriptPath, sol::object state, sol::this_state s) {
  auto entity = Game::getInstance().getNetworkScripting()->spawn(scriptPath, luaToJson(state));
  if (!entity) {
    return sol::make_object(s, sol::lua_nil);
  }
  return sol::make_object(s, *entity);
}

// Da identidad de red a una entidad ya existente (la nave del jugador, una bala).
// Con script no vacio y online, ademas anuncia un spawn a los demas.
inline sol::object netRegister(Entity e, sol::optional<std::string> script, sol::object state,
                               sol::this_state s) {
  auto netId = Game::getInstance().getNetworkScripting()->registerLocal(
    e, script.value_or(""), luaToJson(state));
  return sol::make_object(s, netId);
}

// Online solo el duenio puede despawnear; la copia local muere sin on_death
inline void netDespawn(Entity e) {
  Game::getInstance().getNetworkScripting()->despawn(e);
}

inline bool isLocal(Entity e) {
  if (!netIsOnline()) return true;
  return Game::getInstance().getNetworkRegistry()->isLocallyOwned(e);
}

inline sol::object getNetId(Entity e, sol::this_state s) {
  auto netId = Game::getInstance().getNetworkRegistry()->netIdOf(e);
  if (!netId) return sol::make_object(s, sol::lua_nil);
  return sol::make_object(s, *netId);
}

inline sol::object findByNetId(const std::string& netId, sol::this_state s) {
  auto entity = Game::getInstance().getNetworkRegistry()->find(netId);
  if (!entity) return sol::make_object(s, sol::lua_nil);
  return sol::make_object(s, *entity);
}

inline sol::object getOwner(Entity e, sol::this_state s) {
  if (!e.hasComponent<NetworkComponent>()) return sol::make_object(s, sol::lua_nil);
  return sol::make_object(s, e.getComponent<NetworkComponent>().ownerId);
}

// Solo reescribe el duenio local, no avisa a la red
inline void setOwner(Entity e, const std::string& playerId) {
  if (!e.hasComponent<NetworkComponent>()) return;
  e.getComponent<NetworkComponent>().ownerId = playerId;
}

// Devuelve false si no hay URL configurada (--server / GAME_SERVER)
inline bool netConnect() {
  return Game::getInstance().connectToServer();
}

inline void netDisconnect() {
  Game::getInstance().disconnectFromServer();
}

// "offline" (sin conexion iniciada), "connecting" (iniciada pero sin welcome) u "online"
inline std::string netStatus() {
  auto& net = *Game::getInstance().getNetClient();
  if (net.isOnline()) return "online";
  return net.isStarted() ? "connecting" : "offline";
}

inline std::string netServerUrl() {
  return Game::getInstance().getServerUrl();
}

inline void registerNetworkBindings(sol::state& lua) {
  lua.set_function("net_connect", netConnect);
  lua.set_function("net_disconnect", netDisconnect);
  lua.set_function("net_status", netStatus);
  lua.set_function("net_server_url", netServerUrl);
  lua.set_function("net_is_online", netIsOnline);
  lua.set_function("net_my_id", netMyId);
  lua.set_function("net_is_host", netIsHost);
  lua.set_function("net_peers", netPeers);
  lua.set_function("net_room_settings", netRoomSettings);
  lua.set_function("net_set_pvp", netSetPvp);
  lua.set_function("net_set_match_seed", netSetMatchSeed);
  lua.set_function("net_host_id", netHostId);
  lua.set_function("net_send", netSend);
  lua.set_function("net_on", netOn);
  lua.set_function("net_spawn", netSpawn);
  lua.set_function("spawn_local", spawnLocal);
  lua.set_function("net_register", netRegister);
  lua.set_function("net_despawn", netDespawn);
  lua.set_function("is_local", isLocal);
  lua.set_function("get_net_id", getNetId);
  lua.set_function("find_by_net_id", findByNetId);
  lua.set_function("get_owner", getOwner);
  lua.set_function("set_owner", setOwner);
}
