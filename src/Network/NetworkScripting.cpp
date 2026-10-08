#include "NetworkScripting.hpp"

#include <iostream>

#include "../Components/HealthComponent.hpp"
#include "../Components/NetworkComponent.hpp"
#include "LuaJson.hpp"

using json = nlohmann::json;

namespace {
  const char* PREFAB_DIR = "./assets/scripts/prefabs/";

  // Tipos del protocolo: sus handlers reciben el mensaje completo
  const std::set<std::string> PROTOCOL_TYPES = {
    "welcome", "peer_joined", "peer_left", "host_changed", "hello",
    "spawn", "despawn", "state", "fire", "damage", "death",
    "pickup_request", "loot_taken", "snapshot_request", "snapshot", "room_settings",
  };

  // Tipos que solo el servidor origina, o que no tiene sentido enviar desde Lua
  const std::set<std::string> UNSENDABLE_TYPES = {
    "hello", "welcome", "peer_joined", "peer_left", "host_changed", "custom",
  };

  bool isVec2(const json& v) {
    return v.is_object() && v.contains("x") && v.contains("y") &&
      v["x"].is_number() && v["y"].is_number();
  }

  void fillVec2(json& state, const char* key) {
    if (!state.contains(key) || !isVec2(state[key])) {
      state[key] = {{"x", 0}, {"y", 0}};
    }
  }

  // Devuelve la subtabla, creandola si no existe
  sol::table ensureTable(sol::state& lua, sol::table parent, const char* key) {
    sol::optional<sol::table> existing = parent[key];
    if (existing != sol::nullopt) {
      return *existing;
    }
    sol::table created = lua.create_table();
    parent[key] = created;
    return created;
  }
}

NetworkScripting::NetworkScripting(NetClient& netClient, NetworkRegistry& netRegistry,
                                   Registry& registry, sol::state& lua, SceneLoader& sceneLoader)
  : netClient(netClient), netRegistry(netRegistry), registry(registry), lua(lua),
    sceneLoader(sceneLoader) {
  // Mensajes custom: el handler de Lua recibe (data, from)
  this->netClient.subscribe("custom", [this](const json& msg) {
    if (!msg.contains("type") || !msg["type"].is_string()) {
      return;
    }
    json data = msg.contains("data") ? msg["data"] : json(nullptr);
    this->dispatch(msg["type"].get<std::string>(), jsonToLua(data, this->lua),
                   msg.value("from", std::string()));
  });

  // Handlers por defecto: corren antes que los de Lua porque se suscriben primero
  this->netClient.subscribe("spawn", [this](const json& msg) { this->onSpawnMessage(msg); });
  this->netClient.subscribe("despawn", [this](const json& msg) { this->onDespawnMessage(msg); });
  this->subscribedTypes.insert("spawn");
  this->subscribedTypes.insert("despawn");
}

void NetworkScripting::dispatch(const std::string& type, const sol::object& arg,
                                const std::string& from) {
  auto it = this->luaHandlers.find(type);
  if (it == this->luaHandlers.end()) {
    return;
  }

  // Copia: un handler podria registrar otro o cambiar de escena
  const std::vector<sol::protected_function> handlers = it->second;
  for (const auto& handler : handlers) {
    sol::protected_function_result result = handler(arg, from);
    if (!result.valid()) {
      sol::error err = result;
      std::cout << "[Net] lua handler for '" << type << "' failed: " << err.what() << std::endl;
    }
  }
}

void NetworkScripting::on(const std::string& type, const sol::protected_function& fn) {
  if (PROTOCOL_TYPES.count(type) > 0 && this->subscribedTypes.insert(type).second) {
    this->netClient.subscribe(type, [this, type](const json& msg) {
      this->dispatch(type, jsonToLua(msg, this->lua), msg.value("from", std::string()));
    });
  }
  this->luaHandlers[type].push_back(fn);
}

void NetworkScripting::clearHandlers() {
  this->luaHandlers.clear();
}

bool NetworkScripting::send(const std::string& type, const json& data, const std::string& to) {
  if (!this->netClient.isOnline()) {
    return false;
  }
  if (UNSENDABLE_TYPES.count(type) > 0) {
    std::cout << "[Net] net_send: '" << type << "' cannot be sent from Lua" << std::endl;
    return false;
  }

  json msg;
  if (PROTOCOL_TYPES.count(type) > 0) {
    msg = data.is_object() ? data : json::object();
    msg["t"] = type;
  } else {
    if (type.empty() || type.size() > 64) {
      std::cout << "[Net] net_send: type must be 1-64 characters" << std::endl;
      return false;
    }
    msg = {{"t", "custom"}, {"type", type}, {"data", data}};
  }

  if (!to.empty()) {
    msg["to"] = to;
  }
  return this->netClient.send(std::move(msg));
}

std::optional<Entity> NetworkScripting::buildFromPrefab(const std::string& script,
                                                        const json& state) {
  // El path puede venir de la red: nada de salirse de la carpeta de prefabs
  if (script.empty() || script.find("..") != std::string::npos || script[0] == '/' ||
      script.find('\\') != std::string::npos) {
    std::cout << "[Net] invalid prefab path '" << script << "'" << std::endl;
    return std::nullopt;
  }
  const std::string path = std::string(PREFAB_DIR) + script;

  // addScriptComponent redefine los globals de scripts; "this" se conserva para
  // que el update() que nos llamo siga viendo su propia entidad
  sol::object savedThis = this->lua["this"];
  std::optional<Entity> built;

  try {
    sol::protected_function_result result =
      this->lua.safe_script_file(path, sol::script_pass_on_error);
    if (!result.valid()) {
      sol::error err = result;
      std::cout << "[Net] prefab '" << script << "' failed: " << err.what() << std::endl;
    } else {
      sol::object returned = result;
      if (returned.get_type() == sol::type::function) {
        sol::protected_function factory = returned.as<sol::protected_function>();
        sol::protected_function_result made = factory(jsonToLua(state, this->lua));
        if (made.valid()) {
          returned = made;
        } else {
          sol::error err = made;
          std::cout << "[Net] prefab '" << script << "' failed: " << err.what() << std::endl;
          returned = sol::make_object(this->lua, sol::lua_nil);
        }
      }

      if (returned.get_type() != sol::type::table) {
        std::cout << "[Net] prefab '" << script << "' must return a table" << std::endl;
      } else {
        sol::table def = returned.as<sol::table>();
        sol::table components = ensureTable(this->lua, def, "components");

        // El estado sobreescribe lo que declara el prefab
        if (state.is_object()) {
          if (state.contains("pos") && isVec2(state["pos"])) {
            sol::table transform = ensureTable(this->lua, components, "transform");
            transform["position"] = jsonToLua(state["pos"], this->lua);
          }
          if (state.contains("rot") && state["rot"].is_number()) {
            sol::table transform = ensureTable(this->lua, components, "transform");
            transform["rotation"] = state["rot"].get<double>();
          }
          if (state.contains("vel") && isVec2(state["vel"])) {
            sol::table body = ensureTable(this->lua, components, "rigid_body");
            body["velocity"] = jsonToLua(state["vel"], this->lua);
          }
          if (state.contains("acc") && isVec2(state["acc"])) {
            sol::table body = ensureTable(this->lua, components, "rigid_body");
            body["acceleration"] = jsonToLua(state["acc"], this->lua);
          }
        }

        Entity entity = this->sceneLoader.buildEntity(this->lua, def, this->registry);
        if (state.is_object() && state.contains("hp") && state["hp"].is_number() &&
            entity.hasComponent<HealthComponent>()) {
          entity.getComponent<HealthComponent>().health = state["hp"].get<int>();
        }
        built = entity;
      }
    }
  } catch (const std::exception& e) {
    std::cout << "[Net] prefab '" << script << "' failed: " << e.what() << std::endl;
  }

  this->lua["this"] = savedThis;
  return built;
}

std::optional<Entity> NetworkScripting::spawn(const std::string& script, json state) {
  if (!state.is_object()) {
    state = json::object();
  }
  // El servidor exige cinematica completa en spawn.state
  fillVec2(state, "pos");
  fillVec2(state, "vel");
  fillVec2(state, "acc");
  if (!state.contains("rot") || !state["rot"].is_number()) {
    state["rot"] = 0;
  }

  std::optional<Entity> entity = this->buildFromPrefab(script, state);
  if (!entity) {
    return std::nullopt;
  }

  const std::string netId = this->netRegistry.nextNetId();
  const std::string owner = this->netRegistry.getLocalPlayerId();
  this->netRegistry.registerEntity(*entity, netId, owner);

  if (this->netClient.isOnline()) {
    this->netClient.send({
      {"t", "spawn"},
      {"netId", netId},
      {"owner", owner},
      {"script", script},
      {"state", state},
    });
  }
  return entity;
}

void NetworkScripting::despawn(Entity entity) {
  if (!entity.hasComponent<NetworkComponent>()) {
    entity.kill();
    return;
  }

  const bool online = this->netClient.isOnline();
  if (online && !this->netRegistry.isLocallyOwned(entity)) {
    std::cout << "[Net] net_despawn: entity is owned by another player, ignored" << std::endl;
    return;
  }

  if (online) {
    const std::string netId = entity.getComponent<NetworkComponent>().netId;
    this->netClient.send({{"t", "despawn"}, {"netId", netId}});
  }
  // Kill plano, sin on_death: las copias remotas no deben repetir hooks de gameplay
  entity.kill();
}

void NetworkScripting::onSpawnMessage(const json& msg) {
  if (!msg.contains("netId") || !msg["netId"].is_string() ||
      !msg.contains("owner") || !msg["owner"].is_string() ||
      !msg.contains("script") || !msg["script"].is_string()) {
    return;
  }

  const std::string netId = msg["netId"].get<std::string>();
  if (msg.value("from", std::string()) == this->netClient.getMyPlayerId() ||
      this->netRegistry.find(netId)) {
    return;
  }

  json state = msg.contains("state") ? msg["state"] : json::object();
  std::optional<Entity> entity = this->buildFromPrefab(msg["script"].get<std::string>(), state);
  if (entity) {
    this->netRegistry.registerEntity(*entity, netId, msg["owner"].get<std::string>());
  }
}

void NetworkScripting::onDespawnMessage(const json& msg) {
  if (!msg.contains("netId") || !msg["netId"].is_string()) {
    return;
  }
  std::optional<Entity> entity = this->netRegistry.find(msg["netId"].get<std::string>());
  if (!entity) {
    return;
  }
  // Regla 3: solo el duenio puede borrar la entidad
  const std::string& owner = entity->getComponent<NetworkComponent>().ownerId;
  if (msg.value("from", std::string()) != owner) {
    std::cout << "[Net] despawn of " << msg["netId"].get<std::string>()
              << " from non-owner, ignored" << std::endl;
    return;
  }
  entity->kill();
}
