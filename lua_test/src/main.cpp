#include <iostream>
#include <sol/sol.hpp>
#include <string>


int Pow(int a, int b) {
  int result = 1;
    for (int i = 0; i < b; ++i) {
        result *= a;
    }
    return result;
}

void luaTest() {
  sol::state lua;
  lua.open_libraries(sol::lib::base);

  lua["pow"] = Pow;

  lua.script_file("./scripts/script01.lua");

  std::string nombre = lua["var_nombre"];
  int edad = lua["var_edad"];

  std::cout << "[C++] Nombre: " << nombre << std::endl;
  std::cout << "[C++] Edad: " << edad << std::endl;

  sol::table config = lua["table_config"];
  std::cout << "[C++] Título: " << config["title"].get<std::string>() << std::endl;
  std::cout << "[C++] Pantalla completa: " << config["fullscreen"].get<bool>() << std::endl;
  std::cout << "[C++] Resolución: " << config["resolution"]["width"].get<int>() << "x" << config["resolution"]["height"].get<int>() << std::endl;

  int factResult = lua["factorial"](5);
  std::cout << "[C++] Factorial de 5: " << factResult << std::endl;
}

int main(int argc, char* argv[]) {
    std::cout << "Lua y sol" << std::endl;

    luaTest();
    return 0;
}
