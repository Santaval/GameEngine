#include "NetworkScripting.hpp"

#include <cmath>
#include <iostream>

#include "../Components/CircleColliderComponent.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
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
  this->netClient.subscribe("fire", [this](const json& msg) { this->onFireMessage(msg); });
  this->netClient.subscribe("snapshot", [this](const json& msg) { this->onSnapshotMessage(msg); });
  this->subscribedTypes.insert("spawn");
  this->subscribedTypes.insert("fire");
  this->subscribedTypes.insert("snapshot");
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
  // El script runtime del prefab lee su estado inicial al cargar (spawn_state);
  // los locals del chunk son por entidad porque el SceneLoader lo corre por cada una
  sol::object savedSpawnState = this->lua["spawn_state"];
  this->lua["spawn_state"] = jsonToLua(state, this->lua);
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
  this->lua["spawn_state"] = savedSpawnState;
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
  this->describeEntity(*entity, script, state);

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

std::string NetworkScripting::registerLocal(Entity entity, const std::string& script,
                                            json state) {
  const std::string netId = this->netRegistry.nextNetId();
  const std::string owner = this->netRegistry.getLocalPlayerId();
  this->netRegistry.registerEntity(entity, netId, owner);
  // Sin script nadie la construye por spawn: la anuncia un evento (fire) y cada
  // cliente la simula solo, asi que no gasta presupuesto de "state"
  entity.getComponent<NetworkComponent>().syncState = !script.empty();
  // Entidad ya viva: addComponent no la mete en NetSyncSystem por si solo
  this->registry.refreshEntity(entity);

  if (script.empty()) {
    return netId;
  }

  // La cinematica sale de la entidad; lo que mande Lua (name, max_hp...) se suma
  json merged = json::object();
  if (entity.hasComponent<TransformComponent>()) {
    const auto& transform = entity.getComponent<TransformComponent>();
    merged["pos"] = {{"x", transform.position.x}, {"y", transform.position.y}};
    merged["rot"] = transform.rotation;
  }
  if (entity.hasComponent<RigidBodyComponent>()) {
    const auto& body = entity.getComponent<RigidBodyComponent>();
    merged["vel"] = {{"x", body.velocity.x}, {"y", body.velocity.y}};
    merged["acc"] = {{"x", body.acceleration.x}, {"y", body.acceleration.y}};
  }
  if (entity.hasComponent<HealthComponent>()) {
    merged["hp"] = entity.getComponent<HealthComponent>().health;
  }
  if (state.is_object()) {
    for (auto it = state.begin(); it != state.end(); ++it) {
      merged[it.key()] = it.value();
    }
  }
  fillVec2(merged, "pos");
  fillVec2(merged, "vel");
  fillVec2(merged, "acc");
  if (!merged.contains("rot") || !merged["rot"].is_number()) {
    merged["rot"] = 0;
  }
  // Tambien offline: si luego somos host, el snapshot describe esta entidad
  this->describeEntity(entity, script, merged);

  if (!this->netClient.isOnline()) {
    return netId;
  }
  this->netClient.send({
    {"t", "spawn"},
    {"netId", netId},
    {"owner", owner},
    {"script", script},
    {"state", merged},
  });
  return netId;
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
  json state = msg.contains("state") ? msg["state"] : json::object();
  this->buildRemote(msg, state, msg.value("from", std::string()));
}

// Una entidad de otro jugador, venga de "spawn" o de un "snapshot"
void NetworkScripting::buildRemote(const json& entry, const json& state, const std::string& from) {
  if (!entry.contains("netId") || !entry["netId"].is_string() ||
      !entry.contains("owner") || !entry["owner"].is_string() ||
      !entry.contains("script") || !entry["script"].is_string()) {
    return;
  }

  const std::string netId = entry["netId"].get<std::string>();
  if (from == this->netClient.getMyPlayerId() || this->netRegistry.find(netId)) {
    return;
  }

  std::optional<Entity> entity = this->buildFromPrefab(entry["script"].get<std::string>(), state);
  if (entity) {
    this->netRegistry.registerEntity(*entity, netId, entry["owner"].get<std::string>());
    this->describeEntity(*entity, entry["script"].get<std::string>(), state);
  }
}

// Guarda como se anuncio la entidad para poder describirla en un snapshot
void NetworkScripting::describeEntity(Entity entity, const std::string& script, const json& state) {
  auto& net = entity.getComponent<NetworkComponent>();
  net.script = script;
  net.spawnState = state.is_object() ? state : json::object();
  net.world = net.spawnState.contains("world") && net.spawnState["world"].is_boolean() &&
              net.spawnState["world"].get<bool>();
}

// Respuesta del host a nuestro snapshot_request: cada entidad se construye como un spawn
void NetworkScripting::onSnapshotMessage(const json& msg) {
  if (!msg.contains("entities") || !msg["entities"].is_array()) {
    return;
  }
  const std::string from = msg.value("from", std::string());
  for (const auto& entry : msg["entities"]) {
    if (!entry.is_object()) continue;
    json state = entry.contains("state") ? entry["state"] : json::object();
    this->buildRemote(entry, state, from);
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

void NetworkScripting::onFireMessage(const json& msg) {
  if (!msg.contains("bulletNetId") || !msg["bulletNetId"].is_string() ||
      !msg.contains("shooterNetId") || !msg["shooterNetId"].is_string() ||
      !msg.contains("pos") || !isVec2(msg["pos"]) ||
      !msg.contains("vel") || !isVec2(msg["vel"]) ||
      !msg.contains("dmg") || !msg["dmg"].is_number()) {
    return;
  }

  const std::string from = msg.value("from", std::string());
  const std::string bulletNetId = msg["bulletNetId"].get<std::string>();
  // Mi propia bala ya existe; un netId repetido tampoco se duplica
  if (from.empty() || from == this->netClient.getMyPlayerId() ||
      this->netRegistry.find(bulletNetId)) {
    return;
  }

  const double vx = msg["vel"]["x"].get<double>();
  const double vy = msg["vel"]["y"].get<double>();
  json state = {
    {"pos", msg["pos"]},
    {"vel", msg["vel"]},
    {"rot", std::atan2(vy, vx)},
    {"acc", {{"x", 0}, {"y", 0}}},
  };

  std::optional<Entity> bullet = this->buildFromPrefab("bullet.lua", state);
  if (!bullet) {
    return;
  }

  const int dmg = static_cast<int>(msg["dmg"].get<double>());
  if (bullet->hasComponent<DamageComponent>()) {
    auto& damage = bullet->getComponent<DamageComponent>();
    damage.amount = dmg;
    damage.destroyOnHit = true;
    damage.fromPlayer = true;
  } else {
    bullet->addComponent<DamageComponent>(dmg, true, true);
  }

  // Sin dueño la replica chocaria al instante con la copia de su propio tirador
  std::optional<Entity> shooter = this->netRegistry.find(msg["shooterNetId"].get<std::string>());
  if (shooter && bullet->hasComponent<CircleColliderComponent>()) {
    bullet->getComponent<CircleColliderComponent>().ownerId = shooter->getId();
  }

  this->netRegistry.registerEntity(*bullet, bulletNetId, from);
}
