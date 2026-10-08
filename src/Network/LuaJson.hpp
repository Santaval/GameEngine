#pragma once

#include <cmath>
#include <cstdint>
#include <limits>
#include <string>
#include <sol/sol.hpp>
#include <nlohmann/json.hpp>

// Conversion Lua <-> JSON para los mensajes de red. Solo depende de sol y nlohmann.
//
// Lua -> JSON:
//   - tabla con claves exactamente 1..n (n > 0) -> arreglo; cualquier otra -> objeto
//     (las claves que no son string se convierten a texto). Tabla vacia -> {}
//   - numeros: entero si Lua lo guarda como entero o si es integral y cabe en int64;
//     si no, double. NaN/inf -> null
//   - funciones, userdata y demas -> null. Mas de MAX_DEPTH niveles -> null (ciclos)
namespace luajson {

constexpr int MAX_DEPTH = 32;

inline bool isLuaInteger(const sol::object& o) {
  lua_State* L = o.lua_state();
  o.push();
  bool result = lua_isinteger(L, -1) != 0;
  lua_pop(L, 1);
  return result;
}

inline nlohmann::json numberToJson(const sol::object& o) {
  if (isLuaInteger(o)) {
    return static_cast<int64_t>(o.as<lua_Integer>());
  }

  double value = o.as<double>();
  if (!std::isfinite(value)) {
    return nullptr;
  }
  // 2^63 no cabe en int64: el limite superior es exclusivo
  if (value == std::floor(value) && value >= -9223372036854775808.0 && value < 9223372036854775808.0) {
    return static_cast<int64_t>(value);
  }
  return value;
}

inline std::string keyToString(const sol::object& key) {
  switch (key.get_type()) {
    case sol::type::string:
      return key.as<std::string>();
    case sol::type::number: {
      nlohmann::json n = numberToJson(key);
      return n.is_null() ? std::string("null") : n.dump();
    }
    case sol::type::boolean:
      return key.as<bool>() ? "true" : "false";
    default:
      return "";
  }
}

}  // namespace luajson

inline nlohmann::json luaToJson(const sol::object& o, int depth = 0) {
  using luajson::MAX_DEPTH;

  switch (o.get_type()) {
    case sol::type::boolean:
      return o.as<bool>();
    case sol::type::string:
      return o.as<std::string>();
    case sol::type::number:
      return luajson::numberToJson(o);
    case sol::type::table: {
      if (depth >= MAX_DEPTH) {
        return nullptr;
      }

      sol::table table = o.as<sol::table>();

      // Es arreglo si las claves son exactamente 1..n
      size_t count = 0;
      bool isArray = true;
      for (const auto& pair : table) {
        count++;
        const sol::object& key = pair.first;
        if (key.get_type() != sol::type::number || !luajson::isLuaInteger(key)) {
          isArray = false;
        }
      }
      if (isArray && count > 0) {
        for (const auto& pair : table) {
          lua_Integer k = pair.first.as<lua_Integer>();
          if (k < 1 || static_cast<size_t>(k) > count) {
            isArray = false;
            break;
          }
        }
      }

      if (isArray && count > 0) {
        nlohmann::json array = nlohmann::json::array();
        for (size_t i = 1; i <= count; i++) {
          sol::object value = table[i];
          array.push_back(luaToJson(value, depth + 1));
        }
        return array;
      }

      nlohmann::json object = nlohmann::json::object();
      for (const auto& pair : table) {
        sol::object key = pair.first;
        sol::object value = pair.second;
        object[luajson::keyToString(key)] = luaToJson(value, depth + 1);
      }
      return object;
    }
    default:
      // nil, funciones, userdata, threads
      return nullptr;
  }
}

inline sol::object jsonToLua(const nlohmann::json& j, sol::state_view lua) {
  switch (j.type()) {
    case nlohmann::json::value_t::boolean:
      return sol::make_object(lua, j.get<bool>());
    case nlohmann::json::value_t::number_integer:
      return sol::make_object(lua, static_cast<lua_Integer>(j.get<int64_t>()));
    case nlohmann::json::value_t::number_unsigned:
      return sol::make_object(lua, static_cast<lua_Integer>(j.get<uint64_t>()));
    case nlohmann::json::value_t::number_float:
      return sol::make_object(lua, j.get<double>());
    case nlohmann::json::value_t::string:
      return sol::make_object(lua, j.get<std::string>());
    case nlohmann::json::value_t::array: {
      sol::table table = lua.create_table();
      lua_Integer index = 1;
      for (const auto& item : j) {
        table[index++] = jsonToLua(item, lua);
      }
      return sol::make_object(lua, table);
    }
    case nlohmann::json::value_t::object: {
      sol::table table = lua.create_table();
      for (auto it = j.begin(); it != j.end(); ++it) {
        table[it.key()] = jsonToLua(it.value(), lua);
      }
      return sol::make_object(lua, table);
    }
    default:
      return sol::make_object(lua, sol::lua_nil);
  }
}
