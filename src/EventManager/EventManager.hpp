#pragma once
#include <list>
#include <map>
#include <memory>
#include <typeindex>
#include <iostream>

#include "IEventCallback.hpp"
#include "EventCallback.hpp"


typedef std::list<std::unique_ptr<IEventCallback>> HandlerList;

class EventManager {
  private:
    std::map<std::type_index, std::unique_ptr<HandlerList>> subscribers;

  public:
    EventManager() {
      std::cout << "[EventManager] evenet manager init" << std::endl;
    }

    ~EventManager() {
      std::cout << "[EventManager] evenet manager destroyed" << std::endl;
    }

    void reset() {
      this->subscribers.clear();
    }
    
    template <typename TEvent, typename TOwner>
    void subscribeToEvent(TOwner* ownerInstance, void (TOwner::*callbackFunction)(TEvent&)) {

      const auto subsIndex = typeid(TEvent);

      if (!this->subscribers[subsIndex].get()) {
        this->subscribers[subsIndex] = std::unique_ptr<HandlerList>();
      }

      auto subscriber = std::make_unique<EventCallback<TOwner, TEvent>>(ownerInstance, callbackFunction);
      this->subscribers[subsIndex]->push_back(std::move(subscriber));
    }

    template <typename TEvent, typename... TArgs>
    void emit(TArgs&&... args) {
      auto handlers = subscribers[typeid(TEvent)].get();
      if(handlers) {
        for (auto it = handlers->begin(); it != handlers->end(); it++) {
          auto handler = it->get();
          TEvent event(std::forward<TArgs>(args)...);
          handler->execute(event);
        }
      }
    }
};