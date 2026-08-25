#pragma once
#include <vector>


class IPool {
  public:
    virtual ~IPool() = default;
};

template <typename TComponent>
class Pool : public IPool {
  private:
    std::vector<TComponent> data;

  public:
    Pool(int size = 1000) {
      this->data.resize(size);
    }
  
    virtual ~Pool() = default;

    bool isEmpty() const {
      return this->data.empty();
    }

    int getSize() const {
      return this->data.size();
    }

    void resize(int n) {
      this->data.resize(n);
    }

    void clear() {
      this->data.clear();
    }

    void add(TComponent object) {
      this->data.push_back(object);
    }

    void set(unsigned  index, TComponent object) {
      this->data[index] = object;
    }

    TComponent& get(unsigned int index) {
      return static_cast<TComponent&>(this->data[index]);
    }

    TComponent& operator[](unsigned int index) {
      return static_cast<TComponent&>(this->data[index]);
    }

};