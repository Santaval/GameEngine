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

void ControllerManager::mapMouseAction(const std::string& action, int button) {
  this->actionMouseButtonName.emplace(action, button);
  this->mouseButtonPressed.emplace(button, false);
}

void ControllerManager::mouseButtonDown(int button) {
  auto it = this->mouseButtonPressed.find(button);
  if(it != this->mouseButtonPressed.end()) {
    this->mouseButtonPressed[button] = true;
  }
}

void ControllerManager::mouseButtonUp(int button) {
  auto it = this->mouseButtonPressed.find(button);
  if(it != this->mouseButtonPressed.end()) {
    this->mouseButtonPressed[button] = false;
  }
}

bool ControllerManager::isActionActivated(const std::string& action) {
  auto it = this->actionKeyName.find(action);
  if(it != this->actionKeyName.end()) {
    return this->keyPressed[this->actionKeyName[action]];
  }

  auto mouseIt = this->actionMouseButtonName.find(action);
  if(mouseIt != this->actionMouseButtonName.end()) {
    return this->mouseButtonPressed[this->actionMouseButtonName[action]];
  }

  return false;
}

void ControllerManager::setMousePosition(int x, int y) {
  this->mouseX = x;
  this->mouseY = y;
}