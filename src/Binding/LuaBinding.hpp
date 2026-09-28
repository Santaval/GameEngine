#pragma once

// Agrupa todos los módulos de bindings de Lua. Cada dominio de gameplay
// (input, movimiento, sprites, ...) vive en su propio archivo con su
// función register*Bindings(lua) — agregar aquí el include del nuevo
// archivo alcanza para exponerlo al motor.

#include "CameraBindings.hpp"
#include "ColliderBindings.hpp"
#include "EntityBindings.hpp"
#include "EquipmentBindings.hpp"
#include "HealthBindings.hpp"
#include "InputBindings.hpp"
#include "InventoryBindings.hpp"
#include "MovementBindings.hpp"
#include "PathBindings.hpp"
#include "ScriptBindings.hpp"
#include "SpriteBindings.hpp"
#include "TextBindings.hpp"
