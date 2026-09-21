#pragma once

#include <SDL2/SDL.h>
#include <sol/sol.hpp>

#include <memory>
#include <string>

#include "../AssetManager/AssetManager.hpp"
#include "../ControllerManager/ControllerManager.hpp"
#include "../ECS/Registry.hpp"

class SceneLoader {
  private:
    void loadSprites(SDL_Renderer* renderer, const sol::table& sprites, std::unique_ptr<AssetManager>& assetManager);
    void loadFonts(const sol::table& fonts, std::unique_ptr<AssetManager>& assetManager);
    void loadKeys(const sol::table& keys, std::unique_ptr<ControllerManager>& controllerManager);
    void loadMouseActions(const sol::table& mouse, std::unique_ptr<ControllerManager>& controllerManager);
    void loadEntities(sol::state& lua, const sol::table& entities, std::unique_ptr<Registry>& registry);

    void addTransformComponent(Entity entity, const sol::table& components);
    void addRigidBodyComponent(Entity entity, const sol::table& components);
    void addSpriteComponent(Entity entity, const sol::table& components);
    void addCircleColliderComponent(Entity entity, const sol::table& components);
    void addAnimationComponent(Entity entity, const sol::table& components);
    void addTextComponent(Entity entity, const sol::table& components);
    void addScriptComponent(sol::state& lua, Entity entity, const sol::table& components);

  public:
    SceneLoader();
    ~SceneLoader();
    void load(const std::string& scenePath, sol::state& lua,  std::unique_ptr<AssetManager>& assetManager, 
    std::unique_ptr<ControllerManager>& controllerManager, std::unique_ptr<Registry>& registry, SDL_Renderer* renderer);
};