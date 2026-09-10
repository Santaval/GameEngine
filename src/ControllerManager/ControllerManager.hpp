#pragma once

#include <SDL2/SDL.h>
#include <map>
#include <string>

class ControllerManager {
private:
  std::map<std::string, int> actionKeyName;
  std::map<int, bool> keyPressed;

  void clear();
public:
  ControllerManager();
  ~ControllerManager();

  void mapAction(const std::string& action, int keyCode);
  void keyDown(int keyCode);
  void keyUp(int keyCode);
  bool isActionActivated(const std::string& action);
};


