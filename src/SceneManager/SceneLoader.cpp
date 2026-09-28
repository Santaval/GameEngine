#include "SceneLoader.hpp"

#include <algorithm>
#include <glm/glm.hpp>
#include <iostream>

#include "../Components/CircleColliderComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/ScriptComponent.hpp"
#include "../Components/TextComponent.hpp"
#include "../Components/PathComponent.hpp"
#include "../Components/HealthComponent.hpp"
#include "../Components/DamageComponent.hpp"
#include "../Components/EquipmentComponent.hpp"
#include "../Components/InventoryComponent.hpp"
#include "../Components/LootComponent.hpp"


namespace {
  glm::vec2 getVec2(const sol::table& table, const std::string& key, glm::vec2 defaultValue) {
    sol::optional<sol::table> vec = table[key];
    if (vec == sol::nullopt) return defaultValue;

    return glm::vec2((*vec)["x"], (*vec)["y"]);
  }
}

SceneLoader::SceneLoader() {
  std::cout << "[SceneLoader] Scehene loader init" << std::endl;
}

SceneLoader::~SceneLoader() {
  std::cout << "[SceneLoader] Scehene loader destroyed" << std::endl;

}

void SceneLoader::loadSprites(SDL_Renderer* renderer, const sol::table& sprites, std::unique_ptr<AssetManager>& assetManager) {
  int index = 0;

  while(true) {
    sol::optional<sol::table> hasSprite = sprites[index];

    if(hasSprite == sol::nullopt) break;

    sol::table sprite = sprites[index];

    std::string assetId = sprite["assetId"];
    std::string filePath = sprite["filePath"];

    assetManager->addTexture(renderer, assetId, filePath);
    index++;

  }
}

void SceneLoader::loadFonts(const sol::table& fonts, std::unique_ptr<AssetManager>& assetManager) {
  int index = 0;

  while(true) {
    sol::optional<sol::table> hasFont = fonts[index];

    if(hasFont == sol::nullopt) break;

    sol::table font = fonts[index];

    std::string fontId = font["fontId"];
    std::string filePath = font["filePath"];
    int fontSize = static_cast<int>(font["fontSize"].get<double>());

    assetManager->addFont(fontId, filePath, fontSize);
    index++;

  }
}

void SceneLoader::loadKeys(const sol::table& keys, std::unique_ptr<ControllerManager>& controllerManager) {
  int index = 0;

  while(true) {
    sol::optional<sol::table> hasKey = keys[index];

    if(hasKey == sol::nullopt) break;

    sol::table sprite = keys[index];
    std::string name = sprite["name"];
    int key = sprite["key"];
    controllerManager->mapAction(name, key);
    index++;

  }
}

void SceneLoader::loadMouseActions(const sol::table& mouse, std::unique_ptr<ControllerManager>& controllerManager) {
  int index = 0;

  while(true) {
    sol::optional<sol::table> hasAction = mouse[index];

    if(hasAction == sol::nullopt) break;

    sol::table action = mouse[index];
    std::string name = action["name"];
    int button = action["button"];
    controllerManager->mapMouseAction(name, button);
    index++;

  }
}

void SceneLoader::addTransformComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasTransform = components["transform"];
  if (hasTransform == sol::nullopt) return;

  sol::table transform = *hasTransform;
  glm::vec2 position = getVec2(transform, "position", glm::vec2(0.0, 0.0));
  glm::vec2 scale = getVec2(transform, "scale", glm::vec2(1.0, 1.0));
  double rotation = transform["rotation"].get_or(0.0);

  entity.addComponent<TransformComponent>(position, scale, rotation);
}

void SceneLoader::addRigidBodyComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasRigidBody = components["rigid_body"];
  if (hasRigidBody == sol::nullopt) return;

  glm::vec2 velocity = getVec2(*hasRigidBody, "velocity", glm::vec2(0.0, 0.0));
  glm::vec2 acceleration = getVec2(*hasRigidBody, "acceleration", glm::vec2(0.0, 0.0));
  float maxSpeed = (*hasRigidBody)["max_speed"].get_or(0.0f);

  entity.addComponent<RigidBodyComponent>(velocity, acceleration, maxSpeed);
}

void SceneLoader::addSpriteComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasSprite = components["sprite"];
  if (hasSprite == sol::nullopt) return;

  sol::table sprite = *hasSprite;
  std::string assetId = sprite["assetId"];
  int width = static_cast<int>(sprite["width"].get<double>());
  int height = static_cast<int>(sprite["height"].get<double>());

  sol::optional<sol::table> hasSrcRect = sprite["src_rect"];
  int srcRectX = 0;
  int srcRectY = 0;
  if (hasSrcRect != sol::nullopt) {
    srcRectX = (*hasSrcRect)["x"].get_or(0);
    srcRectY = (*hasSrcRect)["y"].get_or(0);
  }

  entity.addComponent<SpriteComponent>(assetId, width, height, srcRectX, srcRectY);
}

void SceneLoader::addCircleColliderComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasCircleCollider = components["circle_collider"];
  if (hasCircleCollider == sol::nullopt) return;

  sol::table circleCollider = *hasCircleCollider;
  entity.addComponent<CircleColliderComponent>(
    circleCollider["radius"],
    circleCollider["width"],
    circleCollider["heigth"]
  );
}

void SceneLoader::addAnimationComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasAnimation = components["animation"];
  if (hasAnimation == sol::nullopt) return;

  sol::table animation = *hasAnimation;
  int numFrames = animation["numFrames"].get_or(1);
  int frameSpeedRate = animation["frameSpeedRate"].get_or(1);
  bool isLoop = animation["isLoop"].get_or(true);

  entity.addComponent<AnimationComponent>(numFrames, frameSpeedRate, isLoop);
}

void SceneLoader::addTextComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasText = components["text"];
  if (hasText == sol::nullopt) return;

  sol::table text = *hasText;
  std::string content = text["content"].get_or(std::string(""));
  std::string fontId = text["fontId"].get_or(std::string("default"));
  bool isWorldSpace = text["is_world_space"].get_or(true);

  int r = 255, g = 255, b = 255, a = 255;
  sol::optional<sol::table> hasColor = text["color"];
  if (hasColor != sol::nullopt) {
    r = (*hasColor)["r"].get_or(255);
    g = (*hasColor)["g"].get_or(255);
    b = (*hasColor)["b"].get_or(255);
    a = (*hasColor)["a"].get_or(255);
  }

  glm::vec2 offset = getVec2(text, "offset", glm::vec2(0.0, 0.0));

  entity.addComponent<TextComponent>(content, fontId, r, g, b, a, isWorldSpace,
    static_cast<int>(offset.x), static_cast<int>(offset.y));
}

void SceneLoader::addPathComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasPath = components["path"];
  if (hasPath == sol::nullopt) return;

  sol::table path = *hasPath;
  bool active = path["active"].get_or(true);

  entity.addComponent<PathComponent>(active);
}

void SceneLoader::addHealthComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasHealth = components["health"];
  if (hasHealth == sol::nullopt) return;

  sol::table health = *hasHealth;
  int maxHealth = health["max"].get_or(1);
  // current es opcional: -1 significa "empieza a tope"
  int current = health["current"].get_or(-1);
  double invulnerability = health["invulnerability"].get_or(0.0);

  entity.addComponent<HealthComponent>(maxHealth, current, invulnerability);
}

void SceneLoader::addDamageComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasDamage = components["damage"];
  if (hasDamage == sol::nullopt) return;

  sol::table damage = *hasDamage;
  int amount = damage["amount"].get_or(0);
  bool destroyOnHit = damage["destroy_on_hit"].get_or(false);

  entity.addComponent<DamageComponent>(amount, destroyOnHit);
}

void SceneLoader::addEquipmentComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasEquipment = components["equipment"];
  if (hasEquipment == sol::nullopt) return;

  EquipmentList equipment;
  for (const auto& pair : *hasEquipment) {
    if (pair.first.get_type() != sol::type::string) continue;
    if (!pair.second.is<int>()) continue;
    equipment.emplace_back(pair.first.as<std::string>(), pair.second.as<int>());
  }

  // recorrer una tabla Lua con claves no garantiza orden: se ordena por nombre
  // para que el HUD pinte siempre igual
  std::sort(equipment.begin(), equipment.end());

  entity.addComponent<EquipmentComponent>(equipment);
}

void SceneLoader::addInventoryComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasInventory = components["inventory"];
  if (hasInventory == sol::nullopt) return;

  // ambos son opcionales: sin capacity el inventario queda sin limite, sin
  // items arranca vacio
  int capacity = (*hasInventory)["capacity"].get_or(0);

  InventoryList items;
  sol::optional<sol::table> hasItems = (*hasInventory)["items"];
  if (hasItems != sol::nullopt) {
    for (const auto& pair : *hasItems) {
      if (pair.first.get_type() != sol::type::string) continue;
      if (!pair.second.is<int>()) continue;

      int quantity = pair.second.as<int>();
      if (quantity <= 0) continue;  // igual que InventoryComponent: nunca entradas en 0

      items.emplace_back(pair.first.as<std::string>(), quantity);
    }
  }

  // mismo motivo que addEquipmentComponent: el orden de iteracion de una
  // tabla Lua no esta garantizado, asi que se ordena por nombre. Nota: los
  // items de escena no se recortan contra capacity, confiamos en el autor
  // de la escena (ver docs/inventory.md)
  std::sort(items.begin(), items.end());

  entity.addComponent<InventoryComponent>(items, capacity);
}

void SceneLoader::addLootComponent(Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasLoot = components["loot"];
  if (hasLoot == sol::nullopt) return;

  LootList items;
  for (const auto& pair : *hasLoot) {
    if (pair.first.get_type() != sol::type::string) continue;
    if (!pair.second.is<int>()) continue;

    int quantity = pair.second.as<int>();
    if (quantity <= 0) continue;  // igual que LootComponent: nunca entradas en 0

    items.emplace_back(pair.first.as<std::string>(), quantity);
  }

  // mismo motivo que addEquipmentComponent: orden estable por nombre
  std::sort(items.begin(), items.end());

  entity.addComponent<LootComponent>(items);
}

void SceneLoader::addScriptComponent(sol::state& lua, Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasScript = components["script"];
  if (hasScript == sol::nullopt) return;

  std::string path = (*hasScript)["path"];

  // Los scripts definen globals: sin limpiar antes, un archivo que no declara
  // on_death heredaria la del archivo cargado justo antes
  lua["update"] = sol::lua_nil;
  lua["on_damage"] = sol::lua_nil;
  lua["on_death"] = sol::lua_nil;
  lua["on_collision"] = sol::lua_nil;

  lua.script_file(path);

  sol::function update = lua["update"];
  sol::function onDamage = lua["on_damage"];
  sol::function onDeath = lua["on_death"];
  sol::function onCollision = lua["on_collision"];

  entity.addComponent<ScriptComponent>(update, onDamage, onDeath, onCollision);
}

void SceneLoader::loadEntities(sol::state& lua, const sol::table& entities, std::unique_ptr<Registry>& registry) {
  int index = 0;

  while(true) {
    sol::optional<sol::table> hasEntity = entities[index];

    if(hasEntity == sol::nullopt) break;
    sol::table entity = entities[index];

    Entity newEntity = registry->createEntity();

    sol::optional<sol::table> hasComponents = entity["components"];
    if(hasComponents != sol::nullopt) {
      sol::table components = *hasComponents;

      addTransformComponent(newEntity, components);
      addRigidBodyComponent(newEntity, components);
      addSpriteComponent(newEntity, components);
      addCircleColliderComponent(newEntity, components);
      addAnimationComponent(newEntity, components);
      addTextComponent(newEntity, components);
      addPathComponent(newEntity, components);
      addHealthComponent(newEntity, components);
      addDamageComponent(newEntity, components);
      addEquipmentComponent(newEntity, components);
      addInventoryComponent(newEntity, components);
      addLootComponent(newEntity, components);
      addScriptComponent(lua, newEntity, components);
    }

    index++;

  }
}

void SceneLoader::load(const std::string& scenePath, sol::state& lua,  std::unique_ptr<AssetManager>& assetManager, 
  std::unique_ptr<ControllerManager>& controllerManager, std::unique_ptr<Registry>& registry, SDL_Renderer* renderer) {
    sol::load_result script_result = lua.load_file(scenePath);
    if(!script_result.valid()) {
      sol::error err = script_result;
      std::string eMessage = err.what();
      std::cerr << "[SceneLoader]" << eMessage << std::endl;
      return;
    }
    lua.script_file(scenePath);
    sol::table scene = lua["scene"];
    sol::table sprites = scene["sprites"];

    this->loadSprites(renderer, sprites, assetManager);

    sol::optional<sol::table> fonts = scene["fonts"];
    if (fonts != sol::nullopt) {
      this->loadFonts(*fonts, assetManager);
    }

    sol::table keys = scene["keys"];
    this->loadKeys(keys, controllerManager);

    sol::optional<sol::table> mouse = scene["mouse"];
    if (mouse != sol::nullopt) {
      this->loadMouseActions(*mouse, controllerManager);
    }

    sol::table entities = scene["entities"];
    this->loadEntities(lua, entities, registry);
  }