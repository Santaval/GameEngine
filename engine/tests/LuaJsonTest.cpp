#include <iostream>
#include <string>

#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

#include "../src/Network/LuaJson.hpp"

using json = nlohmann::json;

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Evalua una expresion Lua y la convierte a JSON
static json eval(sol::state& lua, const std::string& expr) {
  sol::object o = lua.script("return " + expr);
  return luaToJson(o);
}

static void testScalars() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  CHECK(eval(lua, "nil").is_null());
  CHECK(eval(lua, "true") == json(true));
  CHECK(eval(lua, "false") == json(false));
  CHECK(eval(lua, "'hola'") == json("hola"));
  CHECK(eval(lua, "42").is_number_integer());
  CHECK(eval(lua, "42") == json(42));
  CHECK(eval(lua, "3.5").is_number_float());
  CHECK(eval(lua, "3.5") == json(3.5));
  // un float integral se guarda como entero
  CHECK(eval(lua, "2.0").is_number_integer());
  CHECK(eval(lua, "0/0").is_null());
  CHECK(eval(lua, "math.huge").is_null());
  CHECK(eval(lua, "print").is_null());
}

static void testArrayVsObject() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  CHECK(eval(lua, "{10, 20, 30}") == json::parse("[10,20,30]"));
  CHECK(eval(lua, "{a = 1, b = 'x'}") == json::parse("{\"a\":1,\"b\":\"x\"}"));
  CHECK(eval(lua, "{}") == json::object());
  // claves 1..n con huecos o mezcladas -> objeto
  CHECK(eval(lua, "{[1] = 'a', [3] = 'c'}").is_object());
  CHECK(eval(lua, "{1, 2, x = 3}").is_object());
  CHECK(eval(lua, "{[0] = 'a', 'b'}").is_object());
  CHECK(eval(lua, "{[1] = 'a', [3] = 'c'}")["3"] == json("c"));
  // claves no string se vuelven texto
  CHECK(eval(lua, "{[true] = 1}")["true"] == json(1));
  CHECK(eval(lua, "{[1.5] = 1}").is_object());
}

static void testNested() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  json j = eval(lua, "{ pos = {x = 1, y = 2.5}, tags = {'a', 'b'}, alive = true, empty = {} }");
  CHECK(j["pos"]["x"] == json(1));
  CHECK(j["pos"]["y"] == json(2.5));
  CHECK(j["tags"] == json::parse("[\"a\",\"b\"]"));
  CHECK(j["alive"] == json(true));
  CHECK(j["empty"].is_object() && j["empty"].empty());
  // las funciones dentro de una tabla se vuelven null
  CHECK(eval(lua, "{ f = print }")["f"].is_null());
}

static void testCycle() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  sol::object o = lua.script("local t = {} t.self = t return t");
  json j = luaToJson(o);
  CHECK(j.is_object());
  CHECK(j.dump().size() > 0);
}

static void testJsonToLua() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  json j = json::parse("{\"n\":3,\"f\":1.5,\"s\":\"x\",\"b\":false,\"z\":null,\"a\":[1,2,3],\"o\":{\"k\":\"v\"}}");
  lua["data"] = jsonToLua(j, lua);
  CHECK(lua.script("return data.n == 3 and math.type(data.n) == 'integer'").get<bool>());
  CHECK(lua.script("return data.f == 1.5 and math.type(data.f) == 'float'").get<bool>());
  CHECK(lua.script("return data.s == 'x'").get<bool>());
  CHECK(lua.script("return data.b == false").get<bool>());
  CHECK(lua.script("return data.z == nil").get<bool>());
  CHECK(lua.script("return #data.a == 3 and data.a[1] == 1 and data.a[3] == 3").get<bool>());
  CHECK(lua.script("return data.o.k == 'v'").get<bool>());
  CHECK(jsonToLua(json(nullptr), lua).get_type() == sol::type::lua_nil);
}

static void testRoundTrip() {
  sol::state lua;
  lua.open_libraries(sol::lib::base, sol::lib::math);
  json original = json::parse(
      "{\"netId\":\"a:1\",\"pos\":{\"x\":10,\"y\":-2.25},\"list\":[1,[2,3],{\"deep\":[true,false]}],"
      "\"name\":\"nave\",\"hp\":100,\"empty\":{}}");
  json back = luaToJson(jsonToLua(original, lua));
  CHECK(back == original);
}

int main() {
  testScalars();
  testArrayVsObject();
  testNested();
  testCycle();
  testJsonToLua();
  testRoundTrip();

  if (failures > 0) {
    std::cerr << failures << " check(s) failed" << std::endl;
    return 1;
  }
  std::cout << "All LuaJson checks passed" << std::endl;
  return 0;
}
