#pragma once
#include <functional>
#include "IEventCallback.hpp"

template <typename TOwner, typename TEvent>
class EventCallback : public IEventCallback {
  private:
    typedef void (TOwner::*CallbackFunction) (TEvent&);
  
    TOwner* ownerInstance;
    CallbackFunction callbackFunction;

    virtual void call(Event& e) override {
      std::invoke(callbackFunction, ownerInstance, static_cast<TEvent&>(E));
    }

  public: 
    EventCallback(TOwner* ownerInstance, CallbackFunction callbackFunction) {
      this->callbackFunction = callbackFunction;
      this->ownerInstance = ownerInstance;
    }
};