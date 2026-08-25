#pragma once

#include <vector>
#include <memory>
#include "../Util/Pool.hpp"

class Registry
{
private:
  int numEntity = 0;
  std::vector<std::shared_ptr<IPool>> componentsPool;
};
