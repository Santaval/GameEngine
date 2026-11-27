#include <iostream>

#include "../src/Util/Lighting.hpp"

using namespace lighting;

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

static void testFalloff() {
  CHECK(falloff(0.0f) == 1.0f);
  CHECK(falloff(1.0f) == 0.0f);
  CHECK(falloff(2.0f) == 0.0f);
  float prev = 1.0f;
  for (int i = 1; i <= 100; i++) {
    float v = falloff(i / 100.0f);
    CHECK(v <= prev);
    prev = v;
  }
}

static void testGradient() {
  CHECK(gradientAlpha(128, 128, GRADIENT_SIZE) >= 254);
  CHECK(gradientAlpha(0, 0, GRADIENT_SIZE) == 0);
  CHECK(gradientAlpha(128, 0, GRADIENT_SIZE) == 0);
}

static void testFlicker() {
  CHECK(flickerFactor(0.0f, 1.234, 5) == 1.0f);
  for (int i = 0; i < 1000; i++) {
    float f = flickerFactor(0.4f, i * 0.033, 3);
    CHECK(f >= 0.6f - 1e-4f && f <= 1.0f + 1e-4f);
  }
}

static void testTween() {
  Tween t(0.0f);
  CHECK(!t.active());
  t.start(10.0f, 0.0f);  // instantaneo
  CHECK(t.value == 10.0f && !t.active());

  t.start(20.0f, 2.0f);
  CHECK(t.active());
  t.step(1.0f);
  CHECK(std::fabs(t.value - 15.0f) < 1e-4f);
  t.step(1.5f);
  CHECK(t.value == 20.0f && !t.active());
}

static void testCircleVisible() {
  CHECK(circleVisible(100, 100, 10, 0, 0, 480, 270));
  CHECK(!circleVisible(-20, 100, 10, 0, 0, 480, 270));
  CHECK(circleVisible(-5, 100, 10, 0, 0, 480, 270));
  CHECK(!circleVisible(500, 100, 10, 0, 0, 480, 270));
  CHECK(!circleVisible(100, 300, 10, 0, 0, 480, 270));
}

static void testIsWhite() {
  CHECK(isWhite(255, 255, 255));
  CHECK(!isWhite(255, 255, 200));
  CHECK(!isWhite(20, 26, 51));
}

int main() {
  testFalloff();
  testGradient();
  testFlicker();
  testTween();
  testCircleVisible();
  testIsWhite();
  if (failures == 0) std::cout << "LightingTest: OK" << std::endl;
  return failures == 0 ? 0 : 1;
}
