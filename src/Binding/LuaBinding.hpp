#pragma once

// Agrupa todos los módulos de bindings de Lua. Cada dominio de gameplay
// (input, movimiento, sprites, ...) vive en su propio archivo con su
// función register*Bindings(lua) — agregar aquí el include del nuevo
// archivo alcanza para exponerlo al motor.

#include "InputBindings.hpp"
#include "MovementBindings.hpp"
#include "SpriteBindings.hpp"
