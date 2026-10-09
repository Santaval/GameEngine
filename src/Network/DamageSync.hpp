#pragma once

#include <algorithm>
#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <nlohmann/json.hpp>

#include "../ECS/Entity.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/NetworkComponent.hpp"
#include "NetworkRegistry.hpp"

// Daño y muerte con autoridad del receptor: solo el dueño de una entidad le
// cambia la vida (con su propia colision local) y avisa con "damage" / "death".
// Las demas maquinas solo reflejan lo que dice el dueño.
// No depende de Game ni de NetClient: Game inyecta los callbacks y pasa los
// ticks (`now`), asi se puede probar sin SDL ni red (ver NetSyncSystem).
class DamageSync {
  public:
    // Envia un mensaje por la red (NetClient::send)
    using SendFn = std::function<void(const nlohmann::json&)>;
    using OnlineFn = std::function<bool()>;
    // Solo visual: el resultado del hook on_damage NO debe tocar la vida
    using DamageVisualFn = std::function<void(Entity, int)>;
    using KillFn = std::function<void(Entity)>;
    using DespawnByIdFn = std::function<void(const std::string&)>;

  private:
    NetworkRegistry& net;
    SendFn send;
    OnlineFn online;
    DamageVisualFn onDamageVisual;
    KillFn kill;
    DespawnByIdFn despawnById;
    bool pvp = false;
    // Semilla del mapa (0 = sin fijar); viaja con pvp en los ajustes de la sala
    uint32_t matchSeed = 0;

    // Dueño de una entidad; sin NetworkComponent es del jugador local
    std::string ownerOf(Entity entity) const {
      if (!entity.hasComponent<NetworkComponent>()) return this->net.getLocalPlayerId();
      return entity.getComponent<NetworkComponent>().ownerId;
    }

    // Lee solo los campos presentes: un mensaje sin "seed" no borra la semilla
    // ni uno sin "pvp" cambia el pvp
    void readSettings(const nlohmann::json& settings) {
      if (!settings.is_object()) return;
      auto it = settings.find("pvp");
      if (it != settings.end() && it->is_boolean()) this->pvp = it->get<bool>();
      auto seedIt = settings.find("seed");
      if (seedIt != settings.end() && seedIt->is_number_integer()) {
        const long long value = seedIt->get<long long>();
        if (value > 0 && value <= 0xFFFFFFFFLL) this->matchSeed = static_cast<uint32_t>(value);
      }
    }

    nlohmann::json settingsMessage() const {
      nlohmann::json msg = {{"t", "room_settings"}, {"pvp", this->pvp}};
      if (this->matchSeed != 0) msg["seed"] = this->matchSeed;
      return msg;
    }

  public:
    DamageSync(NetworkRegistry& net, SendFn send, OnlineFn online, DamageVisualFn onDamageVisual,
               KillFn kill, DespawnByIdFn despawnById)
      : net(net), send(std::move(send)), online(std::move(online)),
        onDamageVisual(std::move(onDamageVisual)), kill(std::move(kill)),
        despawnById(std::move(despawnById)) {}

    // Suscripcion "damage": el dueño del blanco informa su nueva vida
    void onDamage(const nlohmann::json& msg, Uint32 now) {
      auto targetIt = msg.find("target");
      if (targetIt == msg.end() || !targetIt->is_string()) return;
      auto hpIt = msg.find("newHp");
      if (hpIt == msg.end() || !hpIt->is_number()) return;
      auto fromIt = msg.find("from");
      if (fromIt == msg.end() || !fromIt->is_string()) return;

      auto entity = this->net.find(targetIt->get<std::string>());
      if (!entity) return;
      // Nadie mas que el dueño decide la vida de una entidad
      if (this->net.isLocallyOwned(*entity)) return;
      if (fromIt->get<std::string>() != entity->getComponent<NetworkComponent>().ownerId) return;
      if (!entity->hasComponent<HealthComponent>()) return;

      auto& health = entity->getComponent<HealthComponent>();
      const int newHp = std::max(hpIt->get<int>(), 0);
      // Esta copia no conoce las mejoras (escudo) del dueño: si su vida supera
      // nuestro tope, el tope subio alla y se sube aca tambien
      if (newHp > health.maxHealth) health.maxHealth = newHp;
      health.health = newHp;
      health.lastDamageTicks = now;

      auto amountIt = msg.find("amount");
      int amount = (amountIt != msg.end() && amountIt->is_number()) ? amountIt->get<int>() : 0;
      // Curaciones (amount < 0) no son un golpe. Hook puramente visual
      if (amount > 0 && this->onDamageVisual) this->onDamageVisual(*entity, amount);

      // Protocolo paso 5: el tirador borra su bala cuando el blanco confirma el impacto
      auto sourceIt = msg.find("source");
      if (sourceIt != msg.end() && sourceIt->is_string()) {
        const std::string source = sourceIt->get<std::string>();
        auto sourceEntity = this->net.find(source);
        bool mine = sourceEntity ? this->net.isLocallyOwned(*sourceEntity)
          // Ya murio localmente (y se des-registro): el prefijo del netId delata al dueño
          : source.rfind(this->net.getLocalPlayerId() + ":", 0) == 0;
        if (mine && !this->net.getLocalPlayerId().empty() && this->despawnById) {
          this->despawnById(source);
        }
      }
    }

    // Suscripcion "death": el dueño informa que su entidad murio
    void onDeath(const nlohmann::json& msg) {
      auto netIdIt = msg.find("netId");
      if (netIdIt == msg.end() || !netIdIt->is_string()) return;
      auto fromIt = msg.find("from");
      if (fromIt == msg.end() || !fromIt->is_string()) return;

      auto entity = this->net.find(netIdIt->get<std::string>());
      if (!entity) return;
      if (this->net.isLocallyOwned(*entity)) return;
      if (fromIt->get<std::string>() != entity->getComponent<NetworkComponent>().ownerId) return;

      if (this->kill) this->kill(*entity);
      this->net.unregister(*entity);
    }

    // El host se valida en Game (el relay no filtra roles ni DamageSync conoce al host)
    void onRoomSettings(const nlohmann::json& msg) {
      this->readSettings(msg);
    }

    void onSnapshot(const nlohmann::json& msg) {
      auto it = msg.find("settings");
      if (it != msg.end()) this->readSettings(*it);
    }

    bool pvpEnabled() const { return this->pvp; }

    // Solo el host llama a esto (se valida fuera). El relay no nos devuelve el
    // mensaje, asi que el valor local se fija aqui.
    void setPvp(bool value) {
      this->pvp = value;
      if (!this->send || !this->online || !this->online()) return;
      this->send(this->settingsMessage());
    }

    uint32_t getMatchSeed() const { return this->matchSeed; }

    // Fija la semilla del mapa (host u offline; se valida fuera). Igual que
    // setPvp, el valor local se fija aqui y online se avisa a los demas.
    void setMatchSeed(uint32_t seed) {
      this->matchSeed = seed;
      if (!this->send || !this->online || !this->online()) return;
      this->send(this->settingsMessage());
    }

    // Sesion nueva: vuelve al valor cooperativo y sin semilla. Solo corre al
    // desconectar, asi que reiniciar la escena (host) conserva la semilla
    void resetSettings() {
      this->pvp = false;
      this->matchSeed = 0;
    }

    // Con pvp apagado, un arma de jugador no lastima a la nave de otro jugador.
    // Se necesitan las marcas explicitas porque el host es jugador y a la vez
    // dueño de entidades del mundo (asteroides): "dueño distinto" no basta.
    bool blocksPvp(Entity target, Entity source) const {
      if (this->pvp) return false;
      if (!source.hasComponent<DamageComponent>() || !target.hasComponent<HealthComponent>()) return false;
      if (!source.getComponent<DamageComponent>().fromPlayer) return false;
      if (!target.getComponent<HealthComponent>().isPlayer) return false;
      return this->ownerOf(source) != this->ownerOf(target);
    }

    // Solo el dueño llama a esto (applyDamage ya filtro). Sin red, no hace nada.
    void broadcastDamage(Entity target, int amount, int newHp, std::optional<Entity> source) {
      if (!this->send || !this->online || !this->online()) return;
      if (!target.hasComponent<NetworkComponent>()) return;

      nlohmann::json msg = {
        {"t", "damage"},
        {"target", target.getComponent<NetworkComponent>().netId},
        {"amount", amount},
        {"newHp", newHp},
      };
      if (source && source->hasComponent<NetworkComponent>()) {
        msg["source"] = source->getComponent<NetworkComponent>().netId;
      }
      this->send(msg);
    }

    void broadcastDeath(Entity target, std::optional<Entity> source) {
      if (!this->send || !this->online || !this->online()) return;
      if (!target.hasComponent<NetworkComponent>()) return;

      nlohmann::json msg = {
        {"t", "death"},
        {"netId", target.getComponent<NetworkComponent>().netId},
      };
      if (source && source->hasComponent<NetworkComponent>()) {
        msg["killer"] = source->getComponent<NetworkComponent>().ownerId;
      }
      this->send(msg);
    }
};
