#include <iostream>
#include <set>
#include <utility>
#include <vector>

#include "../src/Physics/Geometry.hpp"
#include "../src/Physics/MoveAndSlide.hpp"
#include "../src/Physics/SpatialGrid.hpp"
#include "../src/Physics/StaticWorld.hpp"
#include "../src/Physics/TriggerTracker.hpp"

using namespace physics;

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

static bool near(double a, double b, double eps = 1e-6) {
  return a > b - eps && a < b + eps;
}

static void testGeometry() {
  Aabb a = { 0, 0, 10, 10 };
  CHECK(aabbOverlap(a, { 5, 5, 10, 10 }));
  // Pegadas (flush) no solapan
  CHECK(!aabbOverlap(a, { 10, 0, 10, 10 }));
  CHECK(!aabbOverlap(a, { 0, 10, 10, 10 }));
  // Solape menor que SKIN no cuenta
  CHECK(!aabbOverlap(a, { 10 - SKIN / 2, 0, 10, 10 }));
  CHECK(aabbOverlap(a, { 9, 0, 10, 10 }));

  // Circulo contra caja: lado, esquina y dentro
  Aabb box = { 10, 10, 10, 10 };
  CHECK(circleAabbOverlap(5, 15, 5, box));      // tangente al borde izquierdo
  CHECK(!circleAabbOverlap(4, 15, 5, box));
  CHECK(circleAabbOverlap(15, 15, 1, box));     // centro dentro
  // Esquina: distancia a (10, 10) desde (7, 6) es 5
  CHECK(circleAabbOverlap(7, 6, 5, box));
  CHECK(!circleAabbOverlap(6.9, 6, 5, box));

  Aabb r = boxWorldRect(100, 50, 2, 3, 4, 5, 10, 6);
  CHECK(near(r.x, 108) && near(r.y, 65) && near(r.w, 20) && near(r.h, 18));
  Aabb neg = boxWorldRect(100, 50, -1, 1, 0, 0, 10, 6);
  CHECK(near(neg.x, 90) && near(neg.w, 10));
}

static void testGridPairs() {
  SpatialGrid grid(256.0);
  // 0 y 1 comparten varias celdas, 2 esta lejos, 3 comparte una con 0
  grid.insert(0, grid.rangeOf(0, 0, 600, 100));
  grid.insert(1, grid.rangeOf(300, 0, 700, 100));
  grid.insert(2, grid.rangeOf(5000, 5000, 5010, 5010));
  grid.insert(3, grid.rangeOf(10, 10, 20, 20));

  std::multiset<std::pair<int, int>> seen;
  grid.forEachPair([&](int a, int b) { seen.insert({ std::min(a, b), std::max(a, b) }); });
  CHECK(seen.count({ 0, 1 }) == 1);  // dedup por celda duena
  CHECK(seen.count({ 0, 3 }) == 1);
  CHECK(seen.count({ 1, 3 }) == 0);
  CHECK(seen.count({ 0, 2 }) == 0 && seen.count({ 2, 3 }) == 0);
  CHECK(seen.size() == 2);

  // Reset conserva el funcionamiento
  grid.resetDynamic(4);
  grid.insert(0, grid.rangeOf(0, 0, 10, 10));
  grid.insert(1, grid.rangeOf(5, 5, 15, 15));
  int pairs = 0;
  grid.forEachPair([&](int, int) { pairs++; });
  CHECK(pairs == 1);
}

static void testStaticWorld() {
  StaticWorld w;
  int a = w.add({ 0, 0, 16, 16 });
  int b = w.add({ 300, 300, 16, 16 });
  CHECK(w.count() == 2);
  CHECK(w.overlaps({ 8, 8, 4, 4 }));
  CHECK(!w.overlaps({ 16, 0, 4, 4 }));  // flush
  CHECK(w.remove(a));
  CHECK(!w.remove(a));
  CHECK(w.count() == 1);
  CHECK(!w.overlaps({ 8, 8, 4, 4 }));
  CHECK(w.overlaps({ 305, 305, 2, 2 }));
  (void)b;
  w.clear();
  CHECK(w.count() == 0 && !w.overlaps({ 305, 305, 2, 2 }));
}

static void testSlide() {
  StaticWorld w;
  w.add({ 100, 0, 16, 200 });  // pared vertical de 16px

  // Choca de frente
  SlideResult r = moveAndSlide({ 0, 50, 10, 10 }, 200, 0, w);
  CHECK(near(r.dx, 90) && near(r.dy, 0));
  CHECK((r.contacts & CONTACT_RIGHT) != 0);

  // Diagonal: se desliza en Y
  r = moveAndSlide({ 0, 50, 10, 10 }, 200, 30, w);
  CHECK(near(r.dx, 90) && near(r.dy, 30));
  CHECK((r.contacts & CONTACT_RIGHT) != 0 && (r.contacts & CONTACT_BOTTOM) == 0);

  // Sin tunel a ninguna velocidad (16px de pared, dx enorme)
  r = moveAndSlide({ 0, 50, 10, 10 }, 10000, 0, w);
  CHECK(near(r.dx, 90));
  r = moveAndSlide({ 200, 50, 10, 10 }, -10000, 0, w);
  CHECK(near(r.dx, -84));  // 200 -> 116 (borde derecho de la pared)
  CHECK((r.contacts & CONTACT_LEFT) != 0);

  // Pegada a la pared: no se mueve hacia ella pero si a lo largo
  r = moveAndSlide({ 90, 50, 10, 10 }, 5, 5, w);
  CHECK(near(r.dx, 0) && near(r.dy, 5));

  // Costura entre dos rectangulos alineados: se desliza sin engancharse
  StaticWorld seam;
  seam.add({ 0, 100, 16, 16 });
  seam.add({ 16, 100, 16, 16 });
  r = moveAndSlide({ 0, 90, 10, 10 }, 15, 0, seam);  // flush encima de ambos
  CHECK(near(r.dx, 15) && r.contacts == 0);
  r = moveAndSlide({ 0, 90, 10, 10 }, 15, 5, seam);  // apoyada: Y bloqueada
  CHECK(near(r.dx, 15) && near(r.dy, 0) && (r.contacts & CONTACT_BOTTOM) != 0);

  // Techo
  StaticWorld ceil;
  ceil.add({ 0, 0, 100, 10 });
  r = moveAndSlide({ 10, 20, 10, 10 }, 0, -100, ceil);
  CHECK(near(r.dy, -10) && (r.contacts & CONTACT_TOP) != 0);

  // Solidos extra (otras entidades)
  std::vector<Aabb> extra = { { 50, 0, 10, 100 } };
  StaticWorld empty;
  r = moveAndSlide({ 0, 10, 10, 10 }, 100, 0, empty, &extra);
  CHECK(near(r.dx, 40));

  // NaN no mueve
  r = moveAndSlide({ 0, 0, 10, 10 }, std::nan(""), 0, empty);
  CHECK(near(r.dx, 0));
}

static void testDepenetration() {
  StaticWorld w;
  w.add({ 100, 0, 16, 200 });
  // Metida 4px por la izquierda de la pared: sale por el lado mas cercano
  SlideResult r = moveAndSlide({ 94, 50, 10, 10 }, 0, 0, w);
  CHECK(r.depenetrated);
  CHECK(near(r.dx, -4) && near(r.dy, 0));
  // Metida por la derecha
  r = moveAndSlide({ 112, 50, 10, 10 }, 0, 0, w);
  CHECK(r.depenetrated && near(r.dx, 4));
  // Fuera: no hay empuje
  r = moveAndSlide({ 50, 50, 10, 10 }, 0, 0, w);
  CHECK(!r.depenetrated && near(r.dx, 0));
}

static void testTriggerTracker() {
  TriggerTracker t;
  std::vector<TriggerPair> en, st, ex;

  // Frame 1: entra
  t.mark(5, 2);
  t.diff(en, st, ex);
  CHECK(en.size() == 1 && st.empty() && ex.empty());
  CHECK(en[0].first == 2 && en[0].second == 5);  // normalizado
  t.beginFrame();

  // Frame 2: sigue (marcado en orden inverso: misma clave)
  t.mark(2, 5);
  t.diff(en, st, ex);
  CHECK(en.empty() && st.size() == 1 && ex.empty());
  t.beginFrame();

  // Frame 3: sale
  t.diff(en, st, ex);
  CHECK(en.empty() && st.empty() && ex.size() == 1);
  t.beginFrame();

  // Frame 4: nada mas
  t.diff(en, st, ex);
  CHECK(en.empty() && st.empty() && ex.empty());
  t.beginFrame();

  // forget: sin exit
  t.mark(1, 2);
  t.mark(3, 4);
  t.diff(en, st, ex);
  t.beginFrame();
  t.forget(2);
  t.mark(3, 4);
  t.diff(en, st, ex);
  CHECK(en.empty() && st.size() == 1 && ex.empty());
  t.beginFrame();

  // Determinismo: orden ordenado sin importar el de marcado
  t.clear();
  t.mark(9, 8);
  t.mark(1, 2);
  t.mark(5, 6);
  t.diff(en, st, ex);
  CHECK(en.size() == 3);
  CHECK(en[0].first == 1 && en[1].first == 5 && en[2].first == 8);
}

int main() {
  testGeometry();
  testGridPairs();
  testStaticWorld();
  testSlide();
  testDepenetration();
  testTriggerTracker();

  if (failures == 0) {
    std::cout << "PhysicsTest: OK" << std::endl;
    return 0;
  }
  std::cerr << "PhysicsTest: " << failures << " fallo(s)" << std::endl;
  return 1;
}
