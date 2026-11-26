#include <iostream>

#include "../src/Util/PixelPerfect.hpp"

using namespace pixelperfect;

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

static void testComputeLayout() {
  // 480x270 logico: escala entera maxima y centrado
  Layout a = computeLayout(1920, 1080, 480, 270);
  CHECK(a.scale == 4 && a.offsetX == 0 && a.offsetY == 0);

  Layout b = computeLayout(1280, 720, 480, 270);
  CHECK(b.scale == 2 && b.offsetX == 160 && b.offsetY == 90);

  Layout c = computeLayout(2560, 1440, 480, 270);
  CHECK(c.scale == 5 && c.offsetX == 80 && c.offsetY == 45);

  // Ventana no multiplo: sobra en X, la escala es la menor de las dos
  Layout d = computeLayout(1366, 768, 480, 270);
  CHECK(d.scale == 2);

  // Ventana menor que el logico: escala 1 (offset negativo, no soportado)
  Layout e = computeLayout(320, 180, 480, 270);
  CHECK(e.scale == 1 && e.offsetX == -80);

  // Sin area logica: identidad
  Layout f = computeLayout(1280, 720, 0, 0);
  CHECK(f.scale == 1 && f.offsetX == 0 && f.offsetY == 0);
}

static void testSnapCamera() {
  CHECK(snapCamera(10.4) == 10);
  CHECK(snapCamera(10.5) == 11);
  CHECK(snapCamera(-0.4) == 0);
  CHECK(snapCamera(-0.6) == -1);
  CHECK(snapCamera(-10.5) == -10);
}

static void testWindowToLogical() {
  CHECK(windowToLogical(160, 160, 2) == 0);
  CHECK(windowToLogical(159, 160, 2) == -1);
  CHECK(windowToLogical(1119, 160, 2) == 479);
  // Escala no positiva: se devuelve la coordenada de ventana tal cual
  CHECK(windowToLogical(77, 0, 0) == 77);
}

static void testLogicalToNative() {
  CHECK(logicalToNative(10, 160, 2) == 180);

  // Ida y vuelta para varias coordenadas logicas
  Layout l = computeLayout(1280, 720, 480, 270);
  const int samples[] = { 0, 1, 10, 239, 479 };
  for (int v : samples) {
    int native = logicalToNative(v, l.offsetX, l.scale);
    CHECK(windowToLogical(native, l.offsetX, l.scale) == v);
  }
}

int main() {
  testComputeLayout();
  testSnapCamera();
  testWindowToLogical();
  testLogicalToNative();

  if (failures == 0) {
    std::cout << "PixelPerfectTest: OK" << std::endl;
    return 0;
  }
  std::cerr << "PixelPerfectTest: " << failures << " fallo(s)" << std::endl;
  return 1;
}
