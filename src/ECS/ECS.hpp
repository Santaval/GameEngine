#pragma once

#include <vector>
#include <memory>
#include "../Util/Pool.hpp"

struct IComponent
{
protected:
  static int nextId;
};

template <typename T>
class Component : public  IComponent {
  public:
    static int getId() {
      static int id = nextId++;
      return id;
    }
};

class Entity
{
private:
  int id;

public:
  Entity(int id) : id(id) {}
  int getId() const;
};

class Registry
{
private:
  int numEntity = 0;
  std::vector<std::shared_ptr<IPool>> componentsPool;
};