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
};
