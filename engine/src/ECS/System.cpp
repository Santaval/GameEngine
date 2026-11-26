#include "System.hpp"
#include <algorithm>

void System::addEntity(Entity entity) {
    this->entities.push_back(entity);
}

void System::removeEntity(Entity entity) {
    auto it = std::remove_if(this->entities.begin(), this->entities.end(), [&entity](Entity other) {return entity == other;});
    this->entities.erase(it, this->entities.end());
}

void System::clearEntities() {
    this->entities.clear();
}

std::vector<Entity> System::getEntities() const {
    return this->entities;
}

const Signature& System::getComponentSignature() const {
    return this->componentSignature;
}