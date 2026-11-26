#include "NetworkRegistry.hpp"

#include <iostream>

#include "../Components/NetworkComponent.hpp"

NetworkRegistry::NetworkRegistry(Registry* registry) : registry(registry) {
  // Limpieza determinista: el mapeo se borra antes de que el id local se recicle
  this->registry->onEntityKilled([this](Entity entity) {
    this->unregister(entity);
  });
}

void NetworkRegistry::setLocalPlayerId(const std::string& id) {
  if (this->localPlayerId != id) {
    this->localPlayerId = id;
  }
}

const std::string& NetworkRegistry::getLocalPlayerId() const {
  return this->localPlayerId;
}

std::string NetworkRegistry::nextNetId() {
  const std::string prefix = this->localPlayerId.empty() ? "local" : this->localPlayerId;
  return prefix + ":" + std::to_string(++this->counter);
}

void NetworkRegistry::registerEntity(Entity entity, const std::string& netId,
                                     const std::string& ownerId) {
  // Si la entidad ya tenia otro netId, se quita el viejo
  this->unregister(entity);

  auto existing = this->byNetId.find(netId);
  if (existing != this->byNetId.end()) {
    std::cout << "[Net] duplicate netId " << netId << ", replacing old mapping" << std::endl;
    this->unregister(existing->second);
  }

  entity.addComponent<NetworkComponent>(netId, ownerId);
  this->byNetId.insert_or_assign(netId, entity);
  this->byEntityId[entity.getId()] = netId;
}

void NetworkRegistry::unregister(Entity entity) {
  auto it = this->byEntityId.find(entity.getId());
  if (it == this->byEntityId.end()) {
    return;
  }
  this->byNetId.erase(it->second);
  this->byEntityId.erase(it);
}

std::optional<Entity> NetworkRegistry::find(const std::string& netId) const {
  auto it = this->byNetId.find(netId);
  if (it == this->byNetId.end()) {
    return std::nullopt;
  }
  return it->second;
}

std::optional<std::string> NetworkRegistry::netIdOf(Entity entity) const {
  auto it = this->byEntityId.find(entity.getId());
  if (it == this->byEntityId.end()) {
    return std::nullopt;
  }
  return it->second;
}

bool NetworkRegistry::isLocallyOwned(Entity entity) const {
  if (!this->registry->hasComponent<NetworkComponent>(entity)) {
    return true;
  }
  return this->registry->getComponent<NetworkComponent>(entity).ownerId == this->localPlayerId;
}

std::vector<Entity> NetworkRegistry::entitiesOwnedBy(const std::string& playerId) const {
  std::vector<Entity> result;
  for (const auto& [netId, entity] : this->byNetId) {
    if (this->registry->getComponent<NetworkComponent>(entity).ownerId == playerId) {
      result.push_back(entity);
    }
  }
  return result;
}

int NetworkRegistry::reassignOwner(const std::string& from, const std::string& to) {
  int count = 0;
  for (const auto& [netId, entity] : this->byNetId) {
    NetworkComponent& net = this->registry->getComponent<NetworkComponent>(entity);
    if (net.ownerId == from) {
      net.ownerId = to;
      count++;
    }
  }
  return count;
}

void NetworkRegistry::clear() {
  this->byNetId.clear();
  this->byEntityId.clear();
}

size_t NetworkRegistry::size() const {
  return this->byNetId.size();
}
