#pragma once

#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "../ECS/Registry.hpp"

// Mapa netId <-> Entity. No depende de NetClient: Game le pasa el id del
// jugador local con setLocalPlayerId().
// Los ids locales de Entity nunca van por la red (se reciclan); se usa netId.
class NetworkRegistry {
  private:
    Registry* registry;
    std::string localPlayerId;   // "" offline / antes del welcome
    uint64_t counter = 0;        // nunca se reinicia, ni al cambiar de escena
    std::unordered_map<std::string, Entity> byNetId;
    std::unordered_map<int, std::string> byEntityId;

  public:
    explicit NetworkRegistry(Registry* registry);

    void setLocalPlayerId(const std::string& id);
    const std::string& getLocalPlayerId() const;

    // "<localPlayerId>:<++counter>", con prefijo "local" si estamos offline
    std::string nextNetId();

    // Agrega el NetworkComponent y el mapeo de inmediato: sirve en el mismo
    // frame, antes de que Registry::update() procese el spawn
    void registerEntity(Entity entity, const std::string& netId, const std::string& ownerId);

    // Borra ambas direcciones; no hace nada si la entidad no esta registrada
    void unregister(Entity entity);

    std::optional<Entity> find(const std::string& netId) const;
    std::optional<std::string> netIdOf(Entity entity) const;

    // true si no tiene NetworkComponent o ownerId == localPlayerId
    bool isLocallyOwned(Entity entity) const;

    std::vector<Entity> entitiesOwnedBy(const std::string& playerId) const;

    // Reescribe ownerId de from a to (migracion de host); devuelve cuantas
    int reassignOwner(const std::string& from, const std::string& to);

    // Descarta todos los mapeos (el contador se conserva)
    void clear();
    size_t size() const;
};
