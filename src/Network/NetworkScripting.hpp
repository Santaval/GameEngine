#pragma once

#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>
#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

#include "../ECS/Entity.hpp"
#include "../ECS/Registry.hpp"
#include "../SceneManager/SceneLoader.hpp"
#include "NetClient.hpp"
#include "NetworkRegistry.hpp"

// Logica de red que se expone a Lua (ver Binding/NetworkBindings.hpp):
// handlers de mensajes, envio, y spawn/despawn de entidades en red.
// Se construye despues de createLuaBiding y debe morir antes que sol::state,
// porque guarda sol::protected_function.
class NetworkScripting {
  private:
    NetClient& netClient;
    NetworkRegistry& netRegistry;
    Registry& registry;
    sol::state& lua;
    SceneLoader& sceneLoader;

    std::map<std::string, std::vector<sol::protected_function>> luaHandlers;
    // Tipos del protocolo a los que ya nos suscribimos en NetClient
    std::set<std::string> subscribedTypes;

    void dispatch(const std::string& type, const sol::object& arg, const std::string& from);
    void onSpawnMessage(const nlohmann::json& msg);
    void onDespawnMessage(const nlohmann::json& msg);

  public:
    NetworkScripting(NetClient& netClient, NetworkRegistry& netRegistry, Registry& registry,
                     sol::state& lua, SceneLoader& sceneLoader);

    // Registra un handler de Lua: fn(data, from)
    void on(const std::string& type, const sol::protected_function& fn);

    // Se llama al cargar una escena: las suscripciones a NetClient se conservan
    void clearHandlers();

    // false si estamos offline o el tipo no se puede enviar
    bool send(const std::string& type, const nlohmann::json& data, const std::string& to);

    // Construye una entidad a partir de un prefab (assets/scripts/prefabs/<script>)
    std::optional<Entity> buildFromPrefab(const std::string& script, const nlohmann::json& state);

    std::optional<Entity> spawn(const std::string& script, nlohmann::json state);
    void despawn(Entity entity);
};
