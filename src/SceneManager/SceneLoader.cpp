#include "SceneLoader.hpp"

#include <glm/glm.hpp>
#include <iostream>

#include "../Components/CircleColliderComponent.hpp"
#include "../Components/RigidBodyComponent.hpp"
#include "../Components/SpriteComponent.hpp"
#include "../Components/TransformComponent.hpp"
#include "../Components/AnimationComponent.hpp"
#include "../Components/ScriptComponent.hpp"


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

  entity.addComponent<RigidBodyComponent>(velocity);
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

void SceneLoader::addScriptComponent(sol::state& lua, Entity entity, const sol::table& components) {
  sol::optional<sol::table> hasScript = components["script"];
  if (hasScript == sol::nullopt) return;

  std::string path = (*hasScript)["path"];
  lua.script_file(path);
  sol::function update = lua["update"];

  entity.addComponent<ScriptComponent>(update);
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

    sol::table keys = scene["keys"];
    this->loadKeys(keys, controllerManager);

    sol::optional<sol::table> mouse = scene["mouse"];
    if (mouse != sol::nullopt) {
      this->loadMouseActions(*mouse, controllerManager);
    }

    sol::table entities = scene["entities"];
    this->loadEntities(lua, entities, registry);
  }