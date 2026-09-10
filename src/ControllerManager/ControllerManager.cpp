#include "ControllerManager.hpp"

#include <iostream>

ControllerManager::ControllerManager() {
  std::cout << "[ControllerManager] Controller manager init" << std::endl;

}
ControllerManager::~ControllerManager() {
  std::cout << "[ControllerManager] Controller manager destroyed" << std::endl;
}

void ControllerManager::clear() {
  this->actionKeyName.clear();
  this->keyPressed.clear();
}


void ControllerManager::mapAction(const std::string& action, int keyCode) {
  this->actionKeyName.emplace(action, keyCode);
  this->keyPressed.emplace(keyCode, false);
}

void ControllerManager::keyDown(int keyCode) {
  auto it = this->keyPressed.find(keyCode);
  if(it != this->keyPressed.end()) {
    this->keyPressed[keyCode] = true;
  }
}

void ControllerManager::keyUp(int keyCode) {
  auto it = this->keyPressed.find(keyCode);
  if(it != this->keyPressed.end()) {
    this->keyPressed[keyCode] = false;
  }
}

bool ControllerManager::isActionActivated(const std::string& action) {
  auto it = this->actionKeyName.find(action);
  if(it != this->actionKeyName.end()) {
    return this->keyPressed[this->actionKeyName[action]];
  }
  return false;
}