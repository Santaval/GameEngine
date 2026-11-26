#pragma once

#include <SDL2/SDL.h>
#include <map>
#include <string>

class ControllerManager {
private:
  std::map<std::string, int> actionKeyName;
  std::map<int, bool> keyPressed;
  std::map<std::string, int> actionMouseButtonName;
  std::map<int, bool> mouseButtonPressed;
  int mouseX = 0;
  int mouseY = 0;

  void clear();
public:
  ControllerManager();
  ~ControllerManager();

  void mapAction(const std::string& action, int keyCode);
  void keyDown(int keyCode);
  void keyUp(int keyCode);
  void mapMouseAction(const std::string& action, int button);
  void mouseButtonDown(int button);
  void mouseButtonUp(int button);
  bool isActionActivated(const std::string& action);
  void setMousePosition(int x, int y);
  int getMouseX() const { return mouseX; }
  int getMouseY() const { return mouseY; }
};


