#include <iostream>

#include "../src/Util/ImpactDamage.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

int main() {
  // Por debajo (o justo en) el minimo: sin daño
  CHECK(impactDamage(20, 10.0f, 40.0f, 200.0f) == 0);
  CHECK(impactDamage(20, 40.0f, 40.0f, 200.0f) == 0);

  // En el tope o por encima: el daño entero, nunca mas
  CHECK(impactDamage(20, 200.0f, 40.0f, 200.0f) == 20);
  CHECK(impactDamage(20, 900.0f, 40.0f, 200.0f) == 20);

  // Punto medio: la mitad
  CHECK(impactDamage(20, 120.0f, 40.0f, 200.0f) == 10);
  CHECK(impactDamage(10, 120.0f, 40.0f, 200.0f) == 5);

  // Separandose o sin cierre: sin daño
  CHECK(impactDamage(20, -50.0f, 40.0f, 200.0f) == 0);
  CHECK(impactDamage(20, 0.0f, 0.0f, 200.0f) == 0);

  // Un impacto flojo que redondea a 0 no cuenta (el llamador lo descarta)
  CHECK(impactDamage(10, 45.0f, 40.0f, 200.0f) == 0);

  // full == 0: escala desactivada, daño plano
  CHECK(impactDamage(20, 0.0f, 0.0f, 0.0f) == 20);
  CHECK(impactDamage(20, -10.0f, 40.0f, 0.0f) == 20);

  if (failures == 0) std::cout << "ImpactDamageTest: all checks passed" << std::endl;
  return failures == 0 ? 0 : 1;
}
