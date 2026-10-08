#include <iostream>

#include "../src/ECS/Registry.hpp"
#include "../src/Network/NetworkRegistry.hpp"
#include "../src/Components/NetworkComponent.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

static void testNextNetId() {
  Registry registry;
  NetworkRegistry net(&registry);
  CHECK(net.nextNetId() == "local:1");
  CHECK(net.nextNetId() == "local:2");
  net.setLocalPlayerId("k3f9");
  CHECK(net.nextNetId() == "k3f9:3");
}

static void testFindBeforeUpdate() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity e = registry.createEntity();
  net.registerEntity(e, "a:1", "a");
  CHECK(net.find("a:1").has_value());
  CHECK(*net.find("a:1") == e);
  CHECK(net.netIdOf(e) == std::optional<std::string>("a:1"));
  registry.update();
  CHECK(net.find("a:1").has_value());
}

static void testKill() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity e = registry.createEntity();
  net.registerEntity(e, "a:1", "a");
  registry.update();
  e.kill();
  registry.update();
  CHECK(!net.find("a:1").has_value());
  CHECK(!net.netIdOf(e).has_value());
  CHECK(net.size() == 0);
}

static void testRecycling() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity a = registry.createEntity();
  net.registerEntity(a, "a:1", "a");
  registry.update();
  int idA = a.getId();
  a.kill();
  registry.update();

  Entity b = registry.createEntity();
  CHECK(b.getId() == idA);
  net.registerEntity(b, "b:2", "b");
  registry.update();
  CHECK(!net.find("a:1").has_value());
  CHECK(net.find("b:2").has_value() && *net.find("b:2") == b);

  b.kill();
  registry.update();
  Entity c = registry.createEntity();
  CHECK(c.getId() == idA);
  registry.update();
  CHECK(!net.find("b:2").has_value());
  CHECK(net.isLocallyOwned(c));
  CHECK(!net.netIdOf(c).has_value());
}

static void testKillSameFrame() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity e = registry.createEntity();
  net.registerEntity(e, "a:1", "a");
  e.kill();
  registry.update();
  CHECK(!net.find("a:1").has_value());
  CHECK(net.size() == 0);
}

static void testOwnership() {
  Registry registry;
  NetworkRegistry net(&registry);
  net.setLocalPlayerId("me");
  Entity plain = registry.createEntity();
  Entity mine = registry.createEntity();
  Entity theirs = registry.createEntity();
  net.registerEntity(mine, "me:1", "me");
  net.registerEntity(theirs, "x:1", "x");
  CHECK(net.isLocallyOwned(plain));
  CHECK(net.isLocallyOwned(mine));
  CHECK(!net.isLocallyOwned(theirs));
}

static void testReassign() {
  Registry registry;
  NetworkRegistry net(&registry);
  net.setLocalPlayerId("me");
  Entity e1 = registry.createEntity();
  Entity e2 = registry.createEntity();
  Entity e3 = registry.createEntity();
  net.registerEntity(e1, "host:1", "host");
  net.registerEntity(e2, "host:2", "host");
  net.registerEntity(e3, "x:1", "x");
  CHECK(net.entitiesOwnedBy("host").size() == 2);
  CHECK(!net.isLocallyOwned(e1));
  CHECK(net.reassignOwner("host", "me") == 2);
  CHECK(net.entitiesOwnedBy("host").empty());
  CHECK(net.entitiesOwnedBy("me").size() == 2);
  CHECK(net.isLocallyOwned(e1));
  CHECK(net.isLocallyOwned(e2));
  CHECK(!net.isLocallyOwned(e3));
}

static void testClear() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity e = registry.createEntity();
  net.registerEntity(e, "a:1", "a");
  CHECK(net.nextNetId() == "local:1");
  registry.clear();
  net.clear();
  CHECK(net.size() == 0);
  CHECK(!net.find("a:1").has_value());
  CHECK(net.nextNetId() == "local:2");
}

static void testDuplicate() {
  Registry registry;
  NetworkRegistry net(&registry);
  Entity e1 = registry.createEntity();
  Entity e2 = registry.createEntity();
  net.registerEntity(e1, "a:1", "a");
  net.registerEntity(e2, "a:1", "a");
  CHECK(net.size() == 1);
  CHECK(*net.find("a:1") == e2);
  CHECK(!net.netIdOf(e1).has_value());
  CHECK(net.netIdOf(e2).has_value());
}

int main() {
  testNextNetId();
  testFindBeforeUpdate();
  testKill();
  testRecycling();
  testKillSameFrame();
  testOwnership();
  testReassign();
  testClear();
  testDuplicate();

  if (failures > 0) {
    std::cerr << failures << " check(s) failed" << std::endl;
    return 1;
  }
  std::cout << "All NetworkRegistry checks passed" << std::endl;
  return 0;
}
