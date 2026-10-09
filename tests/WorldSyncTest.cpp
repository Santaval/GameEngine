#include <iostream>
#include <string>
#include <vector>

#include "../src/ECS/Registry.hpp"
#include "../src/Network/NetworkRegistry.hpp"
#include "../src/Network/WorldSync.hpp"
#include "../src/Components/NetworkComponent.hpp"
#include "../src/Components/TransformComponent.hpp"
#include "../src/Components/RigidBodyComponent.hpp"
#include "../src/Components/HealthComponent.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Escenario: jugador local "me" y un WorldSync con callbacks que solo registran llamadas
struct Fixture {
  Registry registry;
  NetworkRegistry net{&registry};
  std::vector<nlohmann::json> sent;
  bool online = true;
  WorldSync sync{net, registry,
    [this](const nlohmann::json& m) { sent.push_back(m); },
    [this]() { return online; }};

  explicit Fixture(const std::string& me = "me") { net.setLocalPlayerId(me); }

  // Entidad de mundo (con script) o nave (sin world)
  Entity make(const std::string& netId, const std::string& owner, bool world, const std::string& script = "asteroid.lua") {
    Entity e = registry.createEntity();
    net.registerEntity(e, netId, owner);
    auto& n = e.getComponent<NetworkComponent>();
    n.script = script;
    n.world = world;
    registry.update();
    return e;
  }
  bool alive(const std::string& netId) { return net.find(netId).has_value(); }
  std::string ownerOf(const std::string& netId) {
    return net.find(netId)->getComponent<NetworkComponent>().ownerId;
  }
};

static nlohmann::json custom(const std::string& from, const std::string& type, nlohmann::json data = nlohmann::json::object()) {
  return {{"t", "custom"}, {"from", from}, {"type", type}, {"data", data}};
}

static void testWelcomeAsHostAdopts() {
  Fixture f("me");
  f.make("local:1", "", true);
  f.make("local:2", "", false, "ship.lua");
  f.sync.onWelcome("me", "me");
  CHECK(f.ownerOf("local:1") == "me");
  CHECK(f.ownerOf("local:2") == "");
}

static void testWelcomeAsClientKills() {
  Fixture f("me");
  f.make("local:1", "", true);
  f.make("old:1", "", true);
  f.sync.onWelcome("me", "host");
  CHECK(!f.alive("local:1"));
  CHECK(!f.alive("old:1"));
}

static void testReconnectReconcilesPreviousId() {
  Fixture f("a");
  f.sync.onWelcome("a", "a");
  f.make("a:1", "a", true);
  // Reconexion con otro id y otro host: lo del id anterior vuelve por snapshot
  f.net.setLocalPlayerId("b");
  f.sync.onWelcome("b", "h");
  CHECK(!f.alive("a:1"));
}

static void testPeerLeft() {
  Fixture f;
  f.sync.onWelcome("me", "host");
  f.make("p:1", "p", false, "ship.lua");
  f.make("p:2", "p", false, "");
  f.make("p:3", "p", true);
  f.make("q:1", "q", false, "ship.lua");
  f.sync.onPeerLeft("p");
  CHECK(!f.alive("p:1"));
  CHECK(!f.alive("p:2"));
  CHECK(f.alive("p:3"));
  CHECK(f.alive("q:1"));
}

static void testHostChangedNewHost() {
  Fixture f("me");
  f.sync.onWelcome("me", "old");
  f.make("old:1", "old", true);
  f.make("old:2", "old", false, "ship.lua");
  f.make("x:1", "x", true);
  f.sync.onHostChanged("me");
  CHECK(f.ownerOf("old:1") == "me");
  CHECK(f.ownerOf("old:2") == "old");
  CHECK(f.ownerOf("x:1") == "x");
  CHECK(f.sent.size() == 1);
  CHECK(f.sent[0]["t"] == "custom");
  CHECK(f.sent[0]["type"] == "host_adopt");
  CHECK(f.sent[0]["data"]["oldHostId"] == "old");
}

static void testHostChangedThirdClient() {
  Fixture f("me");
  f.sync.onWelcome("me", "old");
  f.make("old:1", "old", true);
  f.make("old:2", "old", false, "ship.lua");
  f.sync.onHostChanged("new");
  CHECK(f.ownerOf("old:1") == "new");
  CHECK(f.ownerOf("old:2") == "old");
  CHECK(f.sent.empty());
}

static void testCustomOnlyFromHost() {
  Fixture f("me");
  f.sync.onWelcome("me", "host");
  f.make("gone:1", "gone", true);
  f.make("host:1", "host", true);

  // Un impostor no mueve ni borra nada
  f.sync.onCustom(custom("evil", "host_adopt", {{"oldHostId", "gone"}}));
  f.sync.onCustom(custom("evil", "world_reset"));
  CHECK(f.ownerOf("gone:1") == "gone");
  CHECK(f.alive("host:1"));

  f.sync.onCustom(custom("host", "host_adopt", {{"oldHostId", "gone"}}));
  CHECK(f.ownerOf("gone:1") == "host");
  // Idempotente
  f.sync.onCustom(custom("host", "host_adopt", {{"oldHostId", "gone"}}));
  CHECK(f.ownerOf("gone:1") == "host");

  f.sync.onCustom(custom("host", "world_reset"));
  CHECK(!f.alive("host:1"));
  CHECK(!f.alive("gone:1"));
}

static void testAnnounceWorldReset() {
  Fixture f("me");
  f.sync.onWelcome("me", "host");
  f.sync.announceWorldReset();
  CHECK(f.sent.empty());
  f.sync.onHostChanged("me");
  f.sent.clear();
  f.online = false;
  f.sync.announceWorldReset();
  CHECK(f.sent.empty());
  f.online = true;
  f.sync.announceWorldReset();
  CHECK(f.sent.size() == 1 && f.sent[0]["type"] == "world_reset");
}

static void testSnapshot() {
  Fixture f("me");
  f.sync.onWelcome("me", "me");
  nlohmann::json req = {{"t", "snapshot_request"}, {"from", "late"}};

  Entity rock = f.make("me:1", "me", true);
  rock.addComponent<TransformComponent>(glm::vec2(5, 6), glm::vec2(1, 1), 1.5);
  rock.addComponent<RigidBodyComponent>(glm::vec2(1, 2), glm::vec2(0, 0));
  rock.addComponent<HealthComponent>(100, 40);
  rock.getComponent<NetworkComponent>().spawnState = {{"kind", 3}, {"pos", {{"x", 0}, {"y", 0}}}};
  Entity dead = f.make("me:2", "me", true);
  dead.addComponent<HealthComponent>(100, 0);
  f.make("me:3", "me", false, "");        // bala sin script
  f.make("other:1", "other", true);       // ajena

  f.sync.onSnapshotRequest(req, true);
  CHECK(f.sent.size() == 1);
  CHECK(f.sent[0]["t"] == "snapshot");
  CHECK(f.sent[0]["to"] == "late");
  CHECK(f.sent[0]["settings"]["pvp"] == true);
  CHECK(!f.sent[0]["settings"].contains("seed"));
  CHECK(f.sent[0]["entities"].size() == 1);
  auto& e = f.sent[0]["entities"][0];
  CHECK(e["netId"] == "me:1");
  CHECK(e["owner"] == "me");
  CHECK(e["script"] == "asteroid.lua");
  CHECK(e["state"]["kind"] == 3);
  CHECK(e["state"]["pos"]["x"] == 5);
  CHECK(e["state"]["hp"] == 40);
  CHECK(e["state"]["vel"]["y"] == 2);

  // Peticion propia u offline: sin respuesta
  f.sent.clear();
  f.sync.onSnapshotRequest({{"from", "me"}}, false);
  f.online = false;
  f.sync.onSnapshotRequest(req, false);
  CHECK(f.sent.empty());
}

static void testSnapshotSeed() {
  Fixture f("me");
  f.sync.onWelcome("me", "me");
  // Sin entidades igual se responde, y lleva la semilla del mapa
  f.sync.onSnapshotRequest({{"from", "late"}}, true, 12345);
  CHECK(f.sent.size() == 1);
  CHECK(f.sent[0]["settings"]["pvp"] == true);
  CHECK(f.sent[0]["settings"]["seed"] == 12345);
}

static void testSnapshotNonHost() {
  Fixture f("me");
  f.sync.onWelcome("me", "host");
  f.make("me:1", "me", true);
  f.sync.onSnapshotRequest({{"from", "late"}}, false);
  CHECK(f.sent.empty());
}

static void testSnapshotChunks() {
  Fixture f("me");
  f.sync.onWelcome("me", "me");
  for (int i = 0; i < 400; i++) {
    Entity e = f.make("me:" + std::to_string(i), "me", true);
    e.getComponent<NetworkComponent>().spawnState = {{"kind", i}, {"note", std::string(40, 'x')}};
  }
  f.sync.onSnapshotRequest({{"from", "late"}}, false);
  CHECK(f.sent.size() > 1);
  size_t total = 0;
  for (const auto& m : f.sent) {
    CHECK(m.dump().size() < 12288);
    CHECK(m["to"] == "late");
    total += m["entities"].size();
  }
  CHECK(total == 400);
}

int main() {
  testWelcomeAsHostAdopts();
  testWelcomeAsClientKills();
  testReconnectReconcilesPreviousId();
  testPeerLeft();
  testHostChangedNewHost();
  testHostChangedThirdClient();
  testCustomOnlyFromHost();
  testAnnounceWorldReset();
  testSnapshot();
  testSnapshotSeed();
  testSnapshotNonHost();
  testSnapshotChunks();
  if (failures == 0) std::cout << "WorldSyncTest: all tests passed" << std::endl;
  return failures == 0 ? 0 : 1;
}
