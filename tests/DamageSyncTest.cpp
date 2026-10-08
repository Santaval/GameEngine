#include <iostream>
#include <string>
#include <vector>

#include "../src/ECS/Registry.hpp"
#include "../src/Network/NetworkRegistry.hpp"
#include "../src/Network/DamageSync.hpp"
#include "../src/Components/NetworkComponent.hpp"
#include "../src/Components/HealthComponent.hpp"
#include "../src/Components/DamageComponent.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Escenario: jugador local "me" y un DamageSync con callbacks que solo registran llamadas
struct Fixture {
  Registry registry;
  NetworkRegistry net{&registry};
  std::vector<nlohmann::json> sent;
  bool online = true;
  std::vector<int> visualAmounts;
  std::vector<int> killed;
  std::vector<std::string> despawned;
  DamageSync sync{net,
    [this](const nlohmann::json& m) { sent.push_back(m); },
    [this]() { return online; },
    [this](Entity, int amount) { visualAmounts.push_back(amount); },
    [this](Entity e) { killed.push_back(e.getId()); },
    [this](const std::string& id) { despawned.push_back(id); }};

  Fixture() { net.setLocalPlayerId("me"); }

  // Nave con vida registrada en red
  Entity ship(const std::string& netId, const std::string& owner, bool isPlayer = true) {
    Entity e = registry.createEntity();
    e.addComponent<HealthComponent>(100, -1, 0.0, isPlayer);
    net.registerEntity(e, netId, owner);
    registry.update();
    return e;
  }
  Entity weapon(const std::string& netId, const std::string& owner, bool fromPlayer) {
    Entity e = registry.createEntity();
    e.addComponent<DamageComponent>(20, true, fromPlayer);
    net.registerEntity(e, netId, owner);
    registry.update();
    return e;
  }
};

static nlohmann::json damageMsg(const std::string& target, const std::string& from, int amount, int newHp,
                                const std::string& source = "") {
  nlohmann::json m = {{"t", "damage"}, {"target", target}, {"from", from}, {"amount", amount}, {"newHp", newHp}};
  if (!source.empty()) m["source"] = source;
  return m;
}

static void testDamageFromOwner() {
  Fixture f;
  Entity e = f.ship("bot:1", "bot");
  f.sync.onDamage(damageMsg("bot:1", "bot", 20, 80), 1234);
  auto& h = e.getComponent<HealthComponent>();
  CHECK(h.health == 80);
  CHECK(h.lastDamageTicks == 1234);
  CHECK(f.visualAmounts.size() == 1 && f.visualAmounts[0] == 20);
  // newHp se recorta al rango valido
  f.sync.onDamage(damageMsg("bot:1", "bot", 500, -5), 1);
  CHECK(h.health == 0);
  f.sync.onDamage(damageMsg("bot:1", "bot", -500, 100), 1);
  CHECK(h.health == 100);
  // Mas vida que el tope conocido: el dueño subio su tope (escudo), se sigue
  f.sync.onDamage(damageMsg("bot:1", "bot", -500, 140), 1);
  CHECK(h.health == 140);
  CHECK(h.maxHealth == 140);
}

static void testDamageIgnored() {
  Fixture f;
  Entity other = f.ship("bot:1", "bot");
  Entity mine = f.ship("me:1", "me");
  // No es el dueno
  f.sync.onDamage(damageMsg("bot:1", "mallory", 20, 10), 1);
  CHECK(other.getComponent<HealthComponent>().health == 100);
  // Blanco local: nadie mas decide mi vida
  f.sync.onDamage(damageMsg("me:1", "bot", 20, 10), 1);
  CHECK(mine.getComponent<HealthComponent>().health == 100);
  // Desconocido
  f.sync.onDamage(damageMsg("nope:1", "bot", 20, 10), 1);
  // Mal formado
  f.sync.onDamage({{"t", "damage"}, {"from", "bot"}, {"newHp", 1}}, 1);
  f.sync.onDamage({{"t", "damage"}, {"target", "bot:1"}, {"from", "bot"}, {"newHp", "x"}}, 1);
  f.sync.onDamage({{"t", "damage"}, {"target", "bot:1"}, {"newHp", 1}}, 1);
  CHECK(other.getComponent<HealthComponent>().health == 100);
  CHECK(f.visualAmounts.empty());
}

static void testSourceDespawn() {
  Fixture f;
  f.ship("bot:1", "bot");
  f.weapon("me:5", "me", true);
  f.weapon("bot:7", "bot", true);
  f.sync.onDamage(damageMsg("bot:1", "bot", 20, 80, "bot:7"), 1);
  CHECK(f.despawned.empty());
  f.sync.onDamage(damageMsg("bot:1", "bot", 20, 60, "me:5"), 1);
  CHECK(f.despawned.size() == 1 && f.despawned[0] == "me:5");
  // Mi bala que ya murio localmente (des-registrada): el prefijo la delata
  f.sync.onDamage(damageMsg("bot:1", "bot", 20, 40, "me:99"), 1);
  CHECK(f.despawned.size() == 2 && f.despawned[1] == "me:99");
  f.sync.onDamage(damageMsg("bot:1", "bot", 20, 20, "bot:99"), 1);
  CHECK(f.despawned.size() == 2);
}

static void testDeath() {
  Fixture f;
  Entity e = f.ship("bot:1", "bot");
  Entity e2 = f.ship("bot:2", "bot");
  f.sync.onDeath({{"t", "death"}, {"netId", "bot:2"}, {"from", "mallory"}});
  CHECK(f.killed.empty());
  CHECK(f.net.find("bot:2").has_value());
  f.sync.onDeath({{"t", "death"}, {"netId", "bot:1"}, {"from", "bot"}});
  CHECK(f.killed.size() == 1 && f.killed[0] == e.getId());
  CHECK(!f.net.find("bot:1").has_value());
  // Mal formado y propio
  f.sync.onDeath({{"t", "death"}, {"from", "bot"}});
  Entity mine = f.ship("me:1", "me");
  f.sync.onDeath({{"t", "death"}, {"netId", "me:1"}, {"from", "bot"}});
  CHECK(f.killed.size() == 1);
  (void)e2; (void)mine;
}

static void testBlocksPvp() {
  Fixture f;
  Entity myBullet = f.weapon("me:1", "me", true);
  Entity worldBullet = f.weapon("me:2", "me", false);
  Entity theirShip = f.ship("bot:1", "bot", true);
  Entity asteroid = f.ship("me:3", "me", false);
  CHECK(!f.sync.pvpEnabled());
  CHECK(f.sync.blocksPvp(theirShip, myBullet));
  CHECK(!f.sync.blocksPvp(theirShip, worldBullet));
  CHECK(!f.sync.blocksPvp(asteroid, myBullet));
  // Mismo dueno: no es pvp
  Entity myShip = f.ship("me:4", "me", true);
  CHECK(!f.sync.blocksPvp(myShip, myBullet));
  f.sync.onRoomSettings({{"t", "room_settings"}, {"pvp", true}});
  CHECK(f.sync.pvpEnabled());
  CHECK(!f.sync.blocksPvp(theirShip, myBullet));
}

static void testPvpSettings() {
  Fixture f;
  f.sync.onSnapshot({{"t", "snapshot"}, {"settings", {{"pvp", true}}}});
  CHECK(f.sync.pvpEnabled());
  f.sync.onRoomSettings({{"t", "room_settings"}, {"pvp", false}});
  CHECK(!f.sync.pvpEnabled());
  // Valores invalidos se ignoran
  f.sync.onRoomSettings({{"t", "room_settings"}, {"pvp", "yes"}});
  f.sync.onSnapshot({{"t", "snapshot"}});
  CHECK(!f.sync.pvpEnabled());
}

static void testBroadcast() {
  Fixture f;
  Entity mine = f.ship("me:1", "me");
  Entity bullet = f.weapon("bot:5", "bot", true);

  f.online = false;
  f.sync.broadcastDamage(mine, 20, 80, bullet);
  f.sync.broadcastDeath(mine, bullet);
  CHECK(f.sent.empty());

  f.online = true;
  f.sync.broadcastDamage(mine, 20, 80, bullet);
  CHECK(f.sent.size() == 1);
  if (!f.sent.empty()) {
    CHECK(f.sent[0]["t"] == "damage");
    CHECK(f.sent[0]["target"] == "me:1");
    CHECK(f.sent[0]["amount"] == 20);
    CHECK(f.sent[0]["newHp"] == 80);
    CHECK(f.sent[0]["source"] == "bot:5");
  }
  f.sync.broadcastDeath(mine, bullet);
  CHECK(f.sent.size() == 2);
  if (f.sent.size() == 2) {
    CHECK(f.sent[1]["t"] == "death");
    CHECK(f.sent[1]["netId"] == "me:1");
    CHECK(f.sent[1]["killer"] == "bot");
  }
  // Sin fuente: sin source ni killer
  f.sync.broadcastDamage(mine, 5, 75, std::nullopt);
  CHECK(!f.sent.back().contains("source"));

  // Blanco sin NetworkComponent: nada
  Entity local = f.registry.createEntity();
  local.addComponent<HealthComponent>(10);
  f.registry.update();
  size_t before = f.sent.size();
  f.sync.broadcastDamage(local, 1, 9, std::nullopt);
  f.sync.broadcastDeath(local, std::nullopt);
  CHECK(f.sent.size() == before);
}

int main() {
  testDamageFromOwner();
  testDamageIgnored();
  testSourceDespawn();
  testDeath();
  testBlocksPvp();
  testPvpSettings();
  testBroadcast();
  if (failures == 0) std::cout << "DamageSyncTest: all passed" << std::endl;
  return failures == 0 ? 0 : 1;
}
