#pragma once

#include <algorithm>
#include <iostream>
#include <string>
#include <sol/sol.hpp>

#include "../Game/Game.hpp"
#include "../ECS/Entity.hpp"
#include "../ECS/Registry.hpp"
#include "../Components/LightComponent.hpp"
#include "../Systems/LightingSystem.hpp"

inline LightingSystem& lightingSystem() {
    return Game::getInstance().getRegistry()->getSystem<LightingSystem>();
}

// Lee r, g, b (o color = { r, g, b }) de una tabla de opciones; lo que falte queda como estaba
inline void readLightColor(const sol::table& t, int& r, int& g, int& b) {
    r = t.get_or("r", r);
    g = t.get_or("g", g);
    b = t.get_or("b", b);
    sol::optional<sol::table> color = t["color"];
    if (color) {
        r = color->get_or("r", r);
        g = color->get_or("g", g);
        b = color->get_or("b", b);
    }
}

// Crea una luz libre. Devuelve su id (> 0) o 0 si el radio no es valido
inline int addLight(double x, double y, double radius, int r, int g, int b, sol::optional<double> intensity) {
    int id = lightingSystem().addLight(static_cast<float>(x), static_cast<float>(y),
        static_cast<float>(radius), r, g, b, static_cast<float>(intensity.value_or(1.0)));
    if (id == 0) std::cerr << "[Light] add_light: radius must be > 0" << std::endl;
    return id;
}

// Un id desconocido se ignora en silencio: se llama cada frame y no debe llenar la consola
inline void moveLight(int id, double x, double y) {
    lightingSystem().moveLight(id, static_cast<float>(x), static_cast<float>(y));
}

// Campos opcionales: x, y, radius, intensity (cancela el fade), flicker, r, g, b o color = { r, g, b }
inline void setLight(int id, const sol::table& opts) {
    LightingSystem::FreeLight* l = lightingSystem().getLight(id);
    if (!l) return;
    l->x = opts.get_or("x", l->x);
    l->y = opts.get_or("y", l->y);
    float radius = opts.get_or("radius", l->radius);
    if (radius > 0.0f) l->radius = radius;
    l->flicker = opts.get_or("flicker", l->flicker);
    sol::optional<float> intensity = opts["intensity"];
    if (intensity) l->intensity.set(*intensity);
    readLightColor(opts, l->r, l->g, l->b);
}

inline void fadeLight(int id, double to, double seconds) {
    lightingSystem().fadeLight(id, static_cast<float>(to), static_cast<float>(seconds));
}

inline void removeLight(int id) {
    lightingSystem().removeLight(id);
}

inline void setAmbient(int r, int g, int b, sol::optional<double> seconds) {
    lightingSystem().setAmbient(r, g, b, static_cast<float>(seconds.value_or(0.0)));
}

// Pone (o reemplaza) un LightComponent en la entidad. Mismos campos que `light` en la escena
inline void attachLight(Entity e, sol::optional<sol::table> opts) {
    if (!e.hasComponent<LightComponent>()) {
        e.addComponent<LightComponent>();
        // addComponent no re-evalua los sistemas: sin esto el LightingSystem no ve la entidad
        e.registry->refreshEntity(e);
    }
    LightComponent& lc = e.getComponent<LightComponent>();
    if (!opts) return;
    lc.radius = opts->get_or("radius", lc.radius);
    lc.intensity = opts->get_or("intensity", lc.intensity);
    lc.flicker = opts->get_or("flicker", lc.flicker);
    readLightColor(*opts, lc.r, lc.g, lc.b);
    sol::optional<sol::table> offset = (*opts)["offset"];
    if (offset) {
        lc.offset.x = offset->get_or("x", lc.offset.x);
        lc.offset.y = offset->get_or("y", lc.offset.y);
    }
}

inline void detachLight(Entity e) {
    if (!e.hasComponent<LightComponent>()) return;
    e.removeComponent<LightComponent>();
    e.registry->refreshEntity(e);
}

// Crea una luz por cada objeto de la clase opts.class ("light" por defecto) del mapa de
// load_tmx. Propiedades: radius (obligatoria), r, g, b (255), intensity (1), flicker (0).
// La posicion es el centro del rectangulo del objeto. Devuelve la lista de ids
inline sol::table lightsFromMap(sol::table map, sol::optional<sol::table> opts, sol::this_state s) {
    sol::state_view lua(s);
    sol::table ids = lua.create_table();

    std::string className = "light";
    if (opts) className = opts->get_or("class", className);

    sol::optional<sol::table> objects = map["objects"];
    if (!objects) return ids;

    int count = 0;
    size_t total = objects->size();
    for (size_t i = 1; i <= total; i++) {
        sol::optional<sol::table> object = (*objects)[i];
        if (!object) continue;
        if (object->get_or("type", std::string()) != className) continue;

        sol::optional<sol::table> hasProps = (*object)["properties"];
        if (!hasProps) continue;
        sol::table props = *hasProps;

        double radius = props.get_or("radius", 0.0);
        if (radius <= 0.0) {
            std::cerr << "[Light] lights_from_map: light without 'radius' property, ignored" << std::endl;
            continue;
        }

        double x = object->get_or("x", 0.0);
        double y = object->get_or("y", 0.0);
        sol::optional<sol::table> rect = (*object)["rect"];
        if (rect) {
            x = rect->get_or("x", x) + rect->get_or("w", 0.0) / 2.0;
            y = rect->get_or("y", y) + rect->get_or("h", 0.0) / 2.0;
        }

        LightingSystem& system = lightingSystem();
        int id = system.addLight(static_cast<float>(x), static_cast<float>(y), static_cast<float>(radius),
            props.get_or("r", 255), props.get_or("g", 255), props.get_or("b", 255),
            props.get_or("intensity", 1.0f));
        if (id == 0) continue;
        LightingSystem::FreeLight* l = system.getLight(id);
        if (l) l->flicker = props.get_or("flicker", 0.0f);
        ids[++count] = id;
    }
    return ids;
}

inline void registerLightBindings(sol::state& lua) {
    lua.set_function("add_light", addLight);
    lua.set_function("move_light", moveLight);
    lua.set_function("set_light", setLight);
    lua.set_function("fade_light", fadeLight);
    lua.set_function("remove_light", removeLight);
    lua.set_function("set_ambient", setAmbient);
    lua.set_function("attach_light", attachLight);
    lua.set_function("detach_light", detachLight);
    lua.set_function("lights_from_map", lightsFromMap);
}
