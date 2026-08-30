#pragma once
#include "Event.hpp"

class IEventCallback {
private:
    virtual void call(Event &e) = 0;

public:
    virtual ~IEventCallback() = default;
    void execute(Event &e) {
        this->call(e);
    }
};