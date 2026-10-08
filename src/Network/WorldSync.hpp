#pragma once

#include <functional>
#include <string>
#include <utility>
#include <vector>
#include <nlohmann/json.hpp>

#include "../ECS/Entity.hpp"
#include "../ECS/Registry.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/NetworkComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "NetworkRegistry.hpp"

// Mundo con dueño host: asteroides, loot y enemigos los simula el host y todos
// los demas los reflejan. Aca vive lo que pasa cuando cambia quien es el host
// (migracion), cuando un jugador se va y cuando un recien llegado pide el mundo.
// No depende de Game ni de NetClient: Game inyecta los callbacks, asi se puede
// probar sin SDL ni red (ver DamageSync).
class WorldSync {
  public:
    using SendFn = std::function<void(const nlohmann::json&)>;
    using OnlineFn = std::function<bool()>;

    // Un mensaje "snapshot" se mantiene bajo esto (el relay corta en 16 KB)
    static constexpr size_t MAX_CHUNK_BYTES = 12000;

  private:
    NetworkRegistry& net;
    Registry& registry;
    SendFn send;
    OnlineFn online;
    std::string hostId;
    std::string lastOwnId;

    bool isHost() const {
      const std::string& me = this->net.getLocalPlayerId();
      return !me.empty() && me == this->hostId;
    }

    // Borrado plano (sin on_death): kill() es diferido, asi que tambien se des-registra ya
    void drop(Entity entity) {
      entity.kill();
      this->net.unregister(entity);
    }

    static bool isWorld(Entity entity) {
      return entity.hasComponent<NetworkComponent>() && entity.getComponent<NetworkComponent>().world;
    }

    // Pasa las entidades de mundo de `from` a `to`; devuelve cuantas
    int reassignWorld(const std::string& from, const std::string& to) {
      if (from == to) return 0;
      int count = 0;
      for (Entity entity : this->net.entitiesOwnedBy(from)) {
        if (!isWorld(entity)) continue;
        entity.getComponent<NetworkComponent>().ownerId = to;
        count++;
      }
      return count;
    }

    void dropWorld(const std::string& owner) {
      for (Entity entity : this->net.entitiesOwnedBy(owner)) {
        if (isWorld(entity)) this->drop(entity);
      }
    }

    // Misma forma que registerLocal: lo anunciado, con la cinematica y vida actuales encima
    nlohmann::json describe(Entity entity) const {
      const auto& netComp = entity.getComponent<NetworkComponent>();
      nlohmann::json state = netComp.spawnState.is_object() ? netComp.spawnState : nlohmann::json::object();
      if (entity.hasComponent<TransformComponent>()) {
        const auto& transform = entity.getComponent<TransformComponent>();
        state["pos"] = {{"x", transform.position.x}, {"y", transform.position.y}};
        state["rot"] = transform.rotation;
      }
      if (entity.hasComponent<RigidBodyComponent>()) {
        const auto& body = entity.getComponent<RigidBodyComponent>();
        state["vel"] = {{"x", body.velocity.x}, {"y", body.velocity.y}};
        state["acc"] = {{"x", body.acceleration.x}, {"y", body.acceleration.y}};
      }
      if (entity.hasComponent<HealthComponent>()) {
        state["hp"] = entity.getComponent<HealthComponent>().health;
      }
      return {
        {"netId", netComp.netId},
        {"owner", netComp.ownerId},
        {"script", netComp.script},
        {"state", state},
      };
    }

  public:
    WorldSync(NetworkRegistry& net, Registry& registry, SendFn send, OnlineFn online)
      : net(net), registry(registry), send(std::move(send)), online(std::move(online)) {}

    // "welcome": lo creado offline o antes de conectar (dueño "") y lo de una
    // conexion anterior (reconexion) se adopta si somos host; si no, vuelve por snapshot
    void onWelcome(const std::string& myId, const std::string& newHostId) {
      std::vector<std::string> stale = {""};
      if (!this->lastOwnId.empty() && this->lastOwnId != myId) stale.push_back(this->lastOwnId);
      for (const std::string& owner : stale) {
        if (myId == newHostId) {
          this->reassignWorld(owner, myId);
        } else {
          this->dropWorld(owner);
        }
      }
      this->hostId = newHostId;
      this->lastOwnId = myId;
    }

    // "peer_left": su nave y sus balas se van; el mundo se queda (el server
    // manda peer_left antes que host_changed, asi esto corre antes de adoptar)
    void onPeerLeft(const std::string& id) {
      if (id.empty()) return;
      for (Entity entity : this->net.entitiesOwnedBy(id)) {
        if (!isWorld(entity)) this->drop(entity);
      }
    }

    // "host_changed": todos pasan el mundo del host viejo al nuevo; si no, los
    // receptores descartarian su state/damage/death (exigen from == dueño)
    void onHostChanged(const std::string& newHost) {
      const std::string old = this->hostId;
      this->hostId = newHost;
      this->reassignWorld(old, newHost);
      if (newHost == this->net.getLocalPlayerId() && !newHost.empty() &&
          this->send && this->online && this->online()) {
        this->send({{"t", "custom"}, {"type", "host_adopt"}, {"data", {{"oldHostId", old}}}});
      }
    }

    // "custom": host_adopt (red de seguridad, idempotente) y world_reset, solo si vienen del host
    void onCustom(const nlohmann::json& msg) {
      auto fromIt = msg.find("from");
      auto typeIt = msg.find("type");
      if (fromIt == msg.end() || !fromIt->is_string()) return;
      if (typeIt == msg.end() || !typeIt->is_string()) return;
      const std::string from = fromIt->get<std::string>();
      if (from.empty() || from != this->hostId) return;

      const std::string type = typeIt->get<std::string>();
      if (type == "host_adopt") {
        auto dataIt = msg.find("data");
        if (dataIt == msg.end() || !dataIt->is_object()) return;
        auto oldIt = dataIt->find("oldHostId");
        if (oldIt == dataIt->end() || !oldIt->is_string()) return;
        this->reassignWorld(oldIt->get<std::string>(), from);
      } else if (type == "world_reset") {
        this->dropWorld(from);
      }
    }

    // El host va a descartar su mundo (cambio de escena): que los demas lo borren tambien
    void announceWorldReset() {
      if (!this->send || !this->online || !this->online() || !this->isHost()) return;
      this->send({{"t", "custom"}, {"type", "world_reset"}, {"data", nlohmann::json::object()}});
    }

    // "snapshot_request": el host describe todo lo suyo con script, en trozos
    void onSnapshotRequest(const nlohmann::json& msg, bool pvp) {
      if (!this->send || !this->online || !this->online() || !this->isHost()) return;
      auto fromIt = msg.find("from");
      if (fromIt == msg.end() || !fromIt->is_string()) return;
      const std::string from = fromIt->get<std::string>();
      if (from.empty() || from == this->net.getLocalPlayerId()) return;

      nlohmann::json chunk = nlohmann::json::array();
      size_t chunkBytes = 0;
      bool sentAny = false;
      auto flush = [&]() {
        this->send({
          {"t", "snapshot"},
          {"to", from},
          {"entities", chunk},
          {"settings", {{"pvp", pvp}}},
        });
        chunk = nlohmann::json::array();
        chunkBytes = 0;
        sentAny = true;
      };

      for (Entity entity : this->net.entitiesOwnedBy(this->net.getLocalPlayerId())) {
        const auto& netComp = entity.getComponent<NetworkComponent>();
        if (netComp.script.empty()) continue;
        if (entity.hasComponent<HealthComponent>() &&
            entity.getComponent<HealthComponent>().health <= 0) continue;

        nlohmann::json entry = this->describe(entity);
        const size_t bytes = entry.dump().size() + 1;
        if (!chunk.empty() && chunkBytes + bytes > MAX_CHUNK_BYTES) flush();
        chunk.push_back(std::move(entry));
        chunkBytes += bytes;
      }
      // Sin entidades igual se responde: lleva los settings (pvp)
      if (!chunk.empty() || !sentAny) flush();
    }
};
