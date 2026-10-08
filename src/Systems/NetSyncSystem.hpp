#pragma once

#include <algorithm>
#include <cmath>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <glm/glm.hpp>
#include <nlohmann/json.hpp>
#include "../ECS/System.hpp"
#include "../Components/NetworkComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Network/NetworkRegistry.hpp"

// Replicacion de estado y correccion de deriva.
// El dueno de cada entidad manda su cinematica periodicamente ("state"); las
// demas maquinas siguen simulando localmente y se acercan a la verdad del
// dueno (lerp si el error es chico, snap si es grande).
// No depende de NetClient: Game se encarga de suscribirse y de enviar lo que
// devuelve update(). Asi se puede probar sin red.
class NetSyncSystem : public System {
  private:
    // 12.5 Hz por entidad
    static constexpr double SEND_INTERVAL = 0.08;
    // Presupuesto de envio (token bucket): la mitad del limite del relay
    // (120 msg/s) para dejar sitio a fire/damage/custom
    static constexpr double MAX_STATES_PER_SEC = 60.0;
    // Los relojes no estan sincronizados, asi que `ts` es solo informativo:
    // se asume una latencia fija de ida
    static constexpr double ASSUMED_LATENCY = 0.05;
    // Por encima de esta distancia (px) se teletransporta; por debajo se suaviza
    static constexpr float SNAP_DISTANCE = 200.0f;
    // Tiempo (s) en el que se absorbe un error chico
    static constexpr double LERP_TIME = 0.1;
    // Cambios minimos para considerar que una entidad "cambio" y vale la pena enviarla
    static constexpr float EPS_POS = 0.5f;
    static constexpr float EPS_VEL = 0.5f;
    static constexpr double EPS_ROT = 0.001;
    static constexpr float EPS_ACC = 0.01f;

    struct Kinematics {
      glm::vec2 pos{0.0f};
      glm::vec2 vel{0.0f};
      double rot = 0.0;
      glm::vec2 acc{0.0f};
    };

    struct Correction {
      glm::vec2 remaining{0.0f};
      double timeLeft = 0.0;
    };

    struct Tracked {
      // Dueno
      std::optional<Kinematics> lastSent;
      double lastSentAt = -1.0e9;   // nunca enviada: es la mas "vieja"
      // No dueno
      std::string lastFrom;
      long long lastSeq = -1;
      bool hasSeq = false;
      std::optional<Kinematics> pending;
      Correction correction;
    };

    std::unordered_map<std::string, Tracked> tracked;
    double clock = 0.0;
    double sendAccum = 0.0;
    double tokens = MAX_STATES_PER_SEC;

    static bool readVec2(const nlohmann::json& j, const char* key, glm::vec2& out) {
      auto it = j.find(key);
      if (it == j.end() || !it->is_object()) return false;
      auto x = it->find("x");
      auto y = it->find("y");
      if (x == it->end() || y == it->end() || !x->is_number() || !y->is_number()) return false;
      out = glm::vec2(x->get<float>(), y->get<float>());
      return true;
    }

    static bool differs(const Kinematics& a, const Kinematics& b) {
      return glm::length(a.pos - b.pos) > EPS_POS
        || glm::length(a.vel - b.vel) > EPS_VEL
        || std::abs(a.rot - b.rot) > EPS_ROT
        || glm::length(a.acc - b.acc) > EPS_ACC;
    }

  public:
    NetSyncSystem() {
      this->requireComponent<NetworkComponent>();
      this->requireComponent<TransformComponent>();
      this->requireComponent<RigidBodyComponent>();
    }

    // Llamado desde la suscripcion "state" de NetClient (hilo principal, dentro de poll())
    void onState(const nlohmann::json& msg, const NetworkRegistry& net) {
      auto netIdIt = msg.find("netId");
      if (netIdIt == msg.end() || !netIdIt->is_string()) return;
      Kinematics k;
      if (!readVec2(msg, "pos", k.pos) || !readVec2(msg, "vel", k.vel) || !readVec2(msg, "acc", k.acc)) return;
      auto rotIt = msg.find("rot");
      if (rotIt == msg.end() || !rotIt->is_number()) return;
      k.rot = rotIt->get<double>();
      auto seqIt = msg.find("seq");
      if (seqIt == msg.end() || !seqIt->is_number_integer()) return;
      long long seq = seqIt->get<long long>();
      std::string from = msg.value("from", std::string());

      std::string netId = netIdIt->get<std::string>();
      auto entity = net.find(netId);
      if (!entity) return;
      if (net.isLocallyOwned(*entity)) return;
      // Solo el dueno corrige
      if (from != entity->getComponent<NetworkComponent>().ownerId) return;

      Tracked& t = this->tracked[netId];
      // Otro `from` (migracion de host) reinicia la secuencia
      if (t.hasSeq && from == t.lastFrom && seq <= t.lastSeq) return;
      t.lastFrom = from;
      t.lastSeq = seq;
      t.hasSeq = true;
      t.pending = k;
    }

    // Una vez por frame. Devuelve los mensajes "state" a enviar.
    std::vector<nlohmann::json> update(double dt, const NetworkRegistry& net, bool online) {
      std::vector<nlohmann::json> out;

      // 1) Reloj, presupuesto y limpieza
      this->clock += dt;
      this->tokens = std::min(MAX_STATES_PER_SEC, this->tokens + MAX_STATES_PER_SEC * dt);
      this->sendAccum += dt;

      std::unordered_set<std::string> alive;
      auto entities = this->getEntities();
      for (auto& entity : entities) {
        alive.insert(entity.getComponent<NetworkComponent>().netId);
      }
      for (auto it = this->tracked.begin(); it != this->tracked.end();) {
        if (alive.count(it->first) == 0) it = this->tracked.erase(it);
        else ++it;
      }

      const std::string& localId = net.getLocalPlayerId();
      bool sendTick = false;
      if (this->sendAccum >= SEND_INTERVAL) {
        sendTick = true;
        this->sendAccum -= SEND_INTERVAL;
        // Tras un frame muy largo no se acumulan rafagas de ticks
        if (this->sendAccum >= SEND_INTERVAL) this->sendAccum = 0.0;
      }

      struct Candidate {
        Tracked* tracked;
        const std::string* netId;
        Kinematics now;
      };
      std::vector<Candidate> candidates;

      for (auto& entity : entities) {
        const auto& netComp = entity.getComponent<NetworkComponent>();
        auto& transform = entity.getComponent<TransformComponent>();
        auto& body = entity.getComponent<RigidBodyComponent>();

        if (net.isLocallyOwned(entity)) {
          // 3) Dueno: solo online, con id local conocido y siendo el dueno real
          if (!online || !sendTick || localId.empty() || netComp.ownerId != localId) continue;
          Tracked& t = this->tracked[netComp.netId];
          Kinematics now{transform.position, body.velocity, transform.rotation, body.acceleration};
          if (!t.lastSent || differs(*t.lastSent, now)) {
            candidates.push_back({&t, &netComp.netId, now});
          }
          continue;
        }

        // 2) No dueno
        auto found = this->tracked.find(netComp.netId);
        if (found == this->tracked.end()) continue;
        Tracked& t = found->second;
        if (t.pending) {
          const Kinematics& k = *t.pending;
          // vel/rot/acc se asignan directo; la posicion se corrige suave
          body.velocity = k.vel;
          body.acceleration = k.acc;
          transform.rotation = k.rot;
          glm::vec2 target = k.pos + k.vel * static_cast<float>(ASSUMED_LATENCY);
          glm::vec2 error = target - transform.position;
          if (glm::length(error) > SNAP_DISTANCE) {
            transform.position = target;
            t.correction = Correction{};
          } else {
            t.correction = Correction{error, LERP_TIME};
          }
          t.pending.reset();
        }
        if (t.correction.timeLeft > 0.0) {
          double frac = std::min(1.0, dt / t.correction.timeLeft);
          glm::vec2 step = t.correction.remaining * static_cast<float>(frac);
          transform.position += step;
          t.correction.remaining -= step;
          t.correction.timeLeft -= dt;
          if (t.correction.timeLeft <= 0.0) t.correction = Correction{};
        }
      }

      // Las mas antiguas primero; las que no caben siguen "cambiadas" y ganan el proximo tick
      std::sort(candidates.begin(), candidates.end(), [](const Candidate& a, const Candidate& b) {
        return a.tracked->lastSentAt < b.tracked->lastSentAt;
      });
      for (auto& c : candidates) {
        if (this->tokens < 1.0) break;
        this->tokens -= 1.0;
        c.tracked->lastSent = c.now;
        c.tracked->lastSentAt = this->clock;
        out.push_back({
          {"t", "state"},
          {"netId", *c.netId},
          {"pos", {{"x", c.now.pos.x}, {"y", c.now.pos.y}}},
          {"vel", {{"x", c.now.vel.x}, {"y", c.now.vel.y}}},
          {"rot", c.now.rot},
          {"acc", {{"x", c.now.acc.x}, {"y", c.now.acc.y}}},
        });
      }
      return out;
    }

    // Descarta todo el estado (cambio de escena)
    void clear() {
      this->tracked.clear();
      this->clock = 0.0;
      this->sendAccum = 0.0;
      this->tokens = MAX_STATES_PER_SEC;
    }
};
