#include <iostream>
#include <set>
#include <string>

#include "../src/ECS/Registry.hpp"
#include "../src/Network/NetworkRegistry.hpp"
#include "../src/Components/NetworkComponent.hpp"
#include "../src/Components/TransformComponent.hpp"
#include "../src/Components/RigidBodyComponent.hpp"
#include "../src/Systems/NetSyncSystem.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Escenario: un jugador local "me" y un registro con el sistema ya agregado
struct Fixture {
  Registry registry;
  NetworkRegistry net{&registry};
  Fixture() {
    registry.addSystem<NetSyncSystem>();
    net.setLocalPlayerId("me");
  }
  NetSyncSystem& sys() { return registry.getSystem<NetSyncSystem>(); }
  Entity spawn(const std::string& netId, const std::string& owner, glm::vec2 pos = glm::vec2(0.0f)) {
    Entity e = registry.createEntity();
    e.addComponent<TransformComponent>(pos);
    e.addComponent<RigidBodyComponent>();
    net.registerEntity(e, netId, owner);
    registry.update();
    return e;
  }
};

static nlohmann::json stateMsg(const std::string& netId, const std::string& from, long long seq,
                               float px = 0, float py = 0, float vx = 0, float vy = 0,
                               double rot = 0, float ax = 0, float ay = 0) {
  return {
    {"t", "state"}, {"netId", netId}, {"from", from}, {"seq", seq},
    {"pos", {{"x", px}, {"y", py}}}, {"vel", {{"x", vx}, {"y", vy}}},
    {"rot", rot}, {"acc", {{"x", ax}, {"y", ay}}},
  };
}

static void testOwnerSendRate() {
  Fixture f;
  Entity e = f.spawn("me:1", "me", glm::vec2(10, 20));
  CHECK(f.sys().update(0.05, f.net, true).empty());
  auto msgs = f.sys().update(0.05, f.net, true);
  CHECK(msgs.size() == 1);
  if (!msgs.empty()) {
    CHECK(msgs[0]["t"] == "state");
    CHECK(msgs[0]["netId"] == "me:1");
    CHECK(msgs[0]["pos"]["x"] == 10.0f);
    CHECK(msgs[0]["pos"]["y"] == 20.0f);
  }
  // Sin cambios no se reenvia
  CHECK(f.sys().update(0.1, f.net, true).empty());
  // Con cambios si
  e.getComponent<TransformComponent>().position.x = 50.0f;
  CHECK(f.sys().update(0.1, f.net, true).size() == 1);
}

static void testOfflineAndNonOwned() {
  Fixture f;
  f.spawn("me:1", "me");
  f.spawn("other:1", "other");
  CHECK(f.sys().update(0.1, f.net, false).empty());
  auto msgs = f.sys().update(0.1, f.net, true);
  CHECK(msgs.size() == 1);
  if (!msgs.empty()) CHECK(msgs[0]["netId"] == "me:1");
}

static void testNoLocalId() {
  Fixture f;
  f.net.setLocalPlayerId("");
  f.spawn("a:1", "");
  CHECK(f.sys().update(0.1, f.net, true).empty());
}

static void testBudget() {
  Fixture f;
  std::vector<Entity> ents;
  for (int i = 0; i < 100; i++) ents.push_back(f.spawn("me:" + std::to_string(i), "me"));
  std::set<std::string> seen;
  int total = 0;
  double dt = 0.08;
  // 2 s simulados (25 ticks); cambiar las entidades en cada tick para que siempre haya candidatas
  for (int tick = 0; tick < 25; tick++) {
    for (auto& e : ents) e.getComponent<TransformComponent>().position.x += 10.0f;
    auto msgs = f.sys().update(dt, f.net, true);
    total += static_cast<int>(msgs.size());
    for (auto& m : msgs) seen.insert(m["netId"].get<std::string>());
  }
  // Rafaga inicial de 60 + 60/s de recarga durante 2 s
  CHECK(total <= 60 + 120 + 1);
  CHECK(total >= 100);
  CHECK(seen.size() == 100);
}

static void testOnStateFilters() {
  Fixture f;
  Entity remote = f.spawn("other:1", "other");
  f.spawn("me:1", "me");

  f.sys().onState(stateMsg("other:1", "other", 5, 100, 0), f.net);
  f.sys().update(0.016, f.net, false);
  float x1 = remote.getComponent<TransformComponent>().position.x;
  CHECK(x1 > 0.0f);

  // seq igual o menor: descartado
  f.sys().onState(stateMsg("other:1", "other", 5, 1000, 0), f.net);
  f.sys().onState(stateMsg("other:1", "other", 4, 1000, 0), f.net);
  for (int i = 0; i < 20; i++) f.sys().update(0.016, f.net, false);
  CHECK(remote.getComponent<TransformComponent>().position.x < 150.0f);

  // from distinto del dueno: descartado
  Entity r2 = f.spawn("other:2", "other");
  f.sys().onState(stateMsg("other:2", "intruder", 1, 100, 0), f.net);
  for (int i = 0; i < 20; i++) f.sys().update(0.016, f.net, false);
  CHECK(r2.getComponent<TransformComponent>().position.x == 0.0f);

  // entidad local: descartado
  f.sys().onState(stateMsg("me:1", "me", 1, 100, 0), f.net);
  f.sys().onState(stateMsg("me:1", "other", 2, 100, 0), f.net);
  Entity m = *f.net.find("me:1");
  for (int i = 0; i < 20; i++) f.sys().update(0.016, f.net, false);
  CHECK(m.getComponent<TransformComponent>().position.x == 0.0f);

  // netId desconocido y mensajes mal formados: se ignoran sin romper
  f.sys().onState(stateMsg("nope:1", "other", 1), f.net);
  f.sys().onState(nlohmann::json{{"t", "state"}, {"netId", 3}}, f.net);
  f.sys().onState(nlohmann::json{{"t", "state"}, {"netId", "other:1"}}, f.net);

  // Nuevo `from` (migracion): la secuencia se reinicia
  f.net.reassignOwner("other", "other2");
  f.sys().onState(stateMsg("other:1", "other2", 1, 0, 0), f.net);
  f.sys().update(0.016, f.net, false);
}

static void testLerpAndSnap() {
  Fixture f;
  Entity e = f.spawn("other:1", "other");
  auto& tr = e.getComponent<TransformComponent>();

  // Error chico (100 px): converge en ~0.1 s, no instantaneo
  f.sys().onState(stateMsg("other:1", "other", 1, 100, 0), f.net);
  f.sys().update(0.02, f.net, false);
  CHECK(tr.position.x > 0.0f);
  CHECK(tr.position.x < 100.0f);
  for (int i = 0; i < 4; i++) f.sys().update(0.02, f.net, false);
  CHECK(std::abs(tr.position.x - 100.0f) < 0.01f);

  // Error grande (1000 px): snap en el mismo frame
  f.sys().onState(stateMsg("other:1", "other", 2, 1100, 0), f.net);
  f.sys().update(0.016, f.net, false);
  CHECK(tr.position.x == 1100.0f);

  // Extrapolacion por latencia: target = pos + vel * 0.05
  f.sys().onState(stateMsg("other:1", "other", 3, 1100, 0, 200, 0), f.net);
  for (int i = 0; i < 10; i++) f.sys().update(0.02, f.net, false);
  CHECK(tr.position.x >= 1110.0f);
}

static void testDirectFields() {
  Fixture f;
  Entity e = f.spawn("other:1", "other");
  f.sys().onState(stateMsg("other:1", "other", 1, 0, 0, 30, 40, 1.5, 2.0f, 3.0f), f.net);
  f.sys().update(0.016, f.net, false);
  auto& rb = e.getComponent<RigidBodyComponent>();
  CHECK(rb.velocity == glm::vec2(30, 40));
  CHECK(rb.acceleration == glm::vec2(2, 3));
  CHECK(e.getComponent<TransformComponent>().rotation == 1.5);
}

static void testClear() {
  Fixture f;
  Entity e = f.spawn("other:1", "other");
  f.sys().onState(stateMsg("other:1", "other", 5, 100, 0), f.net);
  f.sys().clear();
  f.sys().update(0.016, f.net, false);
  // El pendiente se descarto
  CHECK(e.getComponent<TransformComponent>().position.x == 0.0f);
  // La secuencia se reinicio: seq 1 vuelve a aceptarse
  f.sys().onState(stateMsg("other:1", "other", 1, 100, 0), f.net);
  f.sys().update(0.016, f.net, false);
  CHECK(e.getComponent<TransformComponent>().position.x > 0.0f);

  // El dueno tambien reenvia todo tras clear()
  Fixture g;
  g.spawn("me:1", "me");
  CHECK(g.sys().update(0.1, g.net, true).size() == 1);
  CHECK(g.sys().update(0.1, g.net, true).empty());
  g.sys().clear();
  CHECK(g.sys().update(0.1, g.net, true).size() == 1);
}

// Entidades anunciadas por evento (balas): el dueno no manda "state"
static void testNoSyncState() {
  Fixture f;
  Entity e = f.spawn("me:1", "me", glm::vec2(10, 20));
  e.getComponent<NetworkComponent>().syncState = false;
  CHECK(f.sys().update(0.05, f.net, true).empty());
  CHECK(f.sys().update(0.05, f.net, true).empty());
}

int main() {
  testOwnerSendRate();
  testNoSyncState();
  testOfflineAndNonOwned();
  testNoLocalId();
  testBudget();
  testOnStateFilters();
  testLerpAndSnap();
  testDirectFields();
  testClear();

  if (failures > 0) {
    std::cerr << failures << " check(s) failed" << std::endl;
    return 1;
  }
  std::cout << "All NetSync checks passed" << std::endl;
  return 0;
}
