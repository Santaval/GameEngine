#pragma once

class Entity
{
private:
  int id;

public:
  Entity(int id) : id(id) {}
  int getId() const;

  bool operator==(const Entity& other) const { return this->id == other.id; }
  bool operator!=(const Entity& other) const { return this->id != other.id; }
  bool operator>(const Entity& other) const { return this->id > other.id; }
  bool operator<(const Entity& other) const { return this->id < other.id; }

  template <typename TComponent, typename... TArgs>
  void addComponent(TArgs&&... args);

  template <typename TComponent>
  void removeComponent();

  template <typename TComponent>
  bool hasComponent() const;

  template <typename TComponent>
  TComponent& getComponent() const;

  class Registry* registry;
};
