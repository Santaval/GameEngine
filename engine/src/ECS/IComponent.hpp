#pragma once

struct IComponent
{
protected:
  inline static int nextId = 0;
};

template <typename T>
class Component : public IComponent {
  public:
    static int getId() {
      static int id = nextId++;
      return id;
    }
};
