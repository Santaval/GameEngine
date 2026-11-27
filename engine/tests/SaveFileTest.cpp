#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>

#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

#include "../src/Network/LuaJson.hpp"
#include "../src/Util/SaveFile.hpp"

using json = nlohmann::json;
namespace fs = std::filesystem;

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Carpeta temporal limpia para cada prueba
static std::string freshDir(const std::string& name) {
  fs::path p = fs::temp_directory_path() / ("savefile_test_" + name);
  fs::remove_all(p);
  return p.string();
}

static void writeRaw(const std::string& path, const std::string& text) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  out << text;
}

static void testSlotNames() {
  CHECK(savefile::validSlot("slot1"));
  CHECK(savefile::validSlot("auto_save-2"));
  CHECK(!savefile::validSlot(""));
  CHECK(!savefile::validSlot("../evil"));
  CHECK(!savefile::validSlot("a/b"));
  CHECK(!savefile::validSlot("con espacio"));
  CHECK(!savefile::validSlot(std::string(65, 'a')));
}

static void testMissing() {
  std::string dir = freshDir("missing");
  CHECK(!savefile::read(dir, "slot1").has_value());
  CHECK(!savefile::exists(dir, "slot1"));
  CHECK(!savefile::write(dir, "../x", json::object()));   // ranura invalida
  CHECK(!savefile::write(dir, "slot1", json::array()));   // no es un objeto
}

// Tabla de Lua -> JSON -> disco -> JSON -> tabla de Lua, sin perder nada
static void testRoundTrip() {
  std::string dir = freshDir("roundtrip");
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  sol::object original = lua.script(R"(return {
    version = 1,
    name = "Quebrada: ñandú, canción, ¡Hola! 日本",
    flags = { ["mission.chequelo.state"] = "accepted", ["house.chayo.open"] = true, closed = false },
    day = 3, ratio = 0.25, big = 9007199254740993, neg = -7,
    list = { "a", "b", { deep = { deeper = { 1, 2, 3 } } } },
    empty = {},
  })");

  CHECK(savefile::write(dir, "slot1", luaToJson(original)));
  auto back = savefile::read(dir, "slot1");
  CHECK(back.has_value());
  if (!back) return;

  sol::table t = jsonToLua(*back, lua);
  CHECK(t["version"].get<int>() == 1);
  CHECK(t["name"].get<std::string>() == "Quebrada: ñandú, canción, ¡Hola! 日本");
  CHECK(t["flags"]["mission.chequelo.state"].get<std::string>() == "accepted");
  CHECK(t["flags"]["house.chayo.open"].get<bool>() == true);
  CHECK(t["flags"]["closed"].get<bool>() == false);
  CHECK(t["day"].get<int>() == 3);
  CHECK(t["ratio"].get<double>() == 0.25);
  CHECK(t["big"].get<long long>() == 9007199254740993LL);
  CHECK(t["neg"].get<int>() == -7);
  CHECK(t["list"][1].get<std::string>() == "a");
  CHECK(t["list"][3]["deep"]["deeper"][3].get<int>() == 3);
  CHECK(luaToJson(t) == luaToJson(original));
}

// Un segundo guardado deja el primero como respaldo
static void testBackupKept() {
  std::string dir = freshDir("backup");
  CHECK(savefile::write(dir, "s", json{{"n", 1}}));
  CHECK(!fs::exists(savefile::backupPath(dir, "s")));  // aun no hay anterior
  CHECK(savefile::write(dir, "s", json{{"n", 2}}));
  CHECK(fs::exists(savefile::backupPath(dir, "s")));
  CHECK((*savefile::readFile(savefile::backupPath(dir, "s")))["n"] == 1);
  CHECK((*savefile::read(dir, "s"))["n"] == 2);
  CHECK(!fs::exists(savefile::tempPath(dir, "s")));    // el temporal no queda
}

// Corte a mitad de guardado: el temporal queda a medias, el guardado bueno sigue
static void testCrashLeavesPreviousSave() {
  std::string dir = freshDir("crash");
  CHECK(savefile::write(dir, "s", json{{"n", 1}}));
  writeRaw(savefile::tempPath(dir, "s"), "{\"n\": 99, \"roto\": [1, 2");  // proceso muerto
  auto j = savefile::read(dir, "s");
  CHECK(j.has_value() && (*j)["n"] == 1);

  // el siguiente guardado se recupera del temporal sobrante
  CHECK(savefile::write(dir, "s", json{{"n", 2}}));
  CHECK((*savefile::read(dir, "s"))["n"] == 2);
  CHECK(!fs::exists(savefile::tempPath(dir, "s")));
}

// Archivo principal corrupto: se usa el respaldo, y el corrupto no pisa al respaldo
static void testCorruptMainFallsBack() {
  std::string dir = freshDir("corrupt");
  CHECK(savefile::write(dir, "s", json{{"n", 1}}));
  CHECK(savefile::write(dir, "s", json{{"n", 2}}));  // main = 2, bak = 1
  writeRaw(savefile::slotPath(dir, "s"), "{ esto no es json");

  auto j = savefile::read(dir, "s");
  CHECK(j.has_value() && (*j)["n"] == 1);

  CHECK(savefile::write(dir, "s", json{{"n", 3}}));
  CHECK((*savefile::read(dir, "s"))["n"] == 3);
  // el respaldo no se sobrescribio con el archivo roto
  CHECK((*savefile::readFile(savefile::backupPath(dir, "s")))["n"] == 1);

  // sin respaldo ni principal -> nada
  fs::remove(savefile::slotPath(dir, "s"));
  fs::remove(savefile::backupPath(dir, "s"));
  CHECK(!savefile::read(dir, "s").has_value());
}

static void testSlotsAreIndependent() {
  std::string dir = freshDir("slots");
  CHECK(savefile::write(dir, "a", json{{"who", "a"}}));
  CHECK(savefile::write(dir, "b", json{{"who", "b"}}));
  CHECK((*savefile::read(dir, "a"))["who"] == "a");
  CHECK((*savefile::read(dir, "b"))["who"] == "b");
}

int main() {
  testSlotNames();
  testMissing();
  testRoundTrip();
  testBackupKept();
  testCrashLeavesPreviousSave();
  testCorruptMainFallsBack();
  testSlotsAreIndependent();

  for (const char* n : {"missing", "roundtrip", "backup", "crash", "corrupt", "slots"}) {
    fs::remove_all(fs::temp_directory_path() / (std::string("savefile_test_") + n));
  }

  if (failures > 0) {
    std::cerr << failures << " check(s) failed" << std::endl;
    return 1;
  }
  std::cout << "SaveFileTest: OK" << std::endl;
  return 0;
}
