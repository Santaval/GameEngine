#include <iostream>
#include <string>

#include "../src/Animation/AsepriteAtlas.hpp"

static int failures = 0;

#define CHECK(cond) \
  do { \
    if (!(cond)) { \
      std::cerr << __FILE__ << ":" << __LINE__ << " CHECK failed: " #cond << std::endl; \
      failures++; \
    } \
  } while (0)

// Se ejecuta desde engine/ (make test)
static const char* HASH_PATH = "tests/fixtures/aseprite/hash.json";
static const char* ARRAY_PATH = "tests/fixtures/aseprite/array.json";
static const char* BAD_PATH = "tests/fixtures/aseprite/bad.json";

// Frames de los fixtures (indice: x, duracion): 0: 0/100, 1: 16/200, 2: 32/100, 3: 48/50
static aseprite::Atlas loadOk(const char* path) {
  aseprite::Result r = aseprite::loadFile(path);
  CHECK(r.ok);
  return r.atlas;
}

// Arranca el tag y avanza dt de una vez
static aseprite::Playback played(const aseprite::Atlas& atlas, const char* tag, bool loop, double dt) {
  aseprite::Playback p;
  int index = atlas.findTag(tag);
  CHECK(index >= 0);
  p.start(index, loop);
  p.advance(atlas, dt);
  return p;
}

static void testParse() {
  aseprite::Atlas hash = loadOk(HASH_PATH);
  aseprite::Atlas array = loadOk(ARRAY_PATH);

  CHECK(hash.sizeW == 64 && hash.sizeH == 16);
  CHECK(hash.frames.size() == 4);
  CHECK(array.frames.size() == 4);
  // El hash conserva el orden del archivo (sus claves estan en orden alfabetico inverso)
  for (size_t i = 0; i < 4 && i < hash.frames.size() && i < array.frames.size(); i++) {
    CHECK(hash.frames[i].x == static_cast<int>(i) * 16);
    CHECK(hash.frames[i].x == array.frames[i].x);
    CHECK(hash.frames[i].w == 16 && hash.frames[i].h == 16);
    CHECK(hash.frames[i].durationMs == array.frames[i].durationMs);
  }
  CHECK(hash.frames[0].durationMs == 100);
  CHECK(hash.frames[1].durationMs == 200);
  CHECK(hash.frames[3].durationMs == 50);

  CHECK(hash.tags.size() == 3);
  CHECK(array.tags.size() == 3);
  CHECK(hash.findTag("idle") == 0);
  CHECK(hash.findTag("rev") == 1);
  CHECK(hash.findTag("pp") == 2);
  CHECK(hash.findTag("nope") == -1);
  CHECK(hash.tags[0].from == 0 && hash.tags[0].to == 1);
  CHECK(hash.tags[0].dir == aseprite::Direction::Forward);
  CHECK(hash.tags[1].from == 1 && hash.tags[1].to == 3);
  CHECK(hash.tags[1].dir == aseprite::Direction::Reverse);
  CHECK(hash.tags[2].dir == aseprite::Direction::PingPong);
  CHECK(array.tags[2].dir == aseprite::Direction::PingPong);
}

static void testImplicitTagAndDefaults() {
  // Sin frameTags: un tag "" con todos los frames. Duracion 0 o ausente -> 100
  aseprite::Result r = aseprite::parse(R"J({
    "frames": [
      {"frame": {"x": 0, "y": 0, "w": 8, "h": 8}, "duration": 0},
      {"frame": {"x": 8, "y": 0, "w": 8, "h": 8}}
    ],
    "meta": {"size": {"w": 16, "h": 8}}
  })J");
  CHECK(r.ok);
  CHECK(r.atlas.tags.size() == 1);
  CHECK(r.atlas.findTag("") == 0);
  CHECK(r.atlas.tags[0].from == 0 && r.atlas.tags[0].to == 1);
  CHECK(r.atlas.frames[0].durationMs == 100);
  CHECK(r.atlas.frames[1].durationMs == 100);

  // pingpong_reverse
  r = aseprite::parse(R"J({
    "frames": [
      {"frame": {"x": 0, "y": 0, "w": 8, "h": 8}},
      {"frame": {"x": 8, "y": 0, "w": 8, "h": 8}},
      {"frame": {"x": 16, "y": 0, "w": 8, "h": 8}}
    ],
    "meta": {"frameTags": [{"name": "t", "from": 0, "to": 2, "direction": "pingpong_reverse"}]}
  })J");
  CHECK(r.ok);
  CHECK(r.atlas.tags[0].dir == aseprite::Direction::PingPongReverse);
  // 2,1,0,1 y vuelta
  aseprite::Playback p;
  p.start(0, true);
  CHECK(p.frameIndex(r.atlas) == 2);
  p.advance(r.atlas, 100);
  CHECK(p.frameIndex(r.atlas) == 1);
  p.advance(r.atlas, 100);
  CHECK(p.frameIndex(r.atlas) == 0);
  p.advance(r.atlas, 100);
  CHECK(p.frameIndex(r.atlas) == 1);
  p.advance(r.atlas, 100);
  CHECK(p.frameIndex(r.atlas) == 2);
}

static void testErrors() {
  aseprite::Result r = aseprite::loadFile(BAD_PATH);
  CHECK(!r.ok && !r.error.empty());

  r = aseprite::loadFile("tests/fixtures/aseprite/missing.json");
  CHECK(!r.ok && !r.error.empty());

  r = aseprite::parse("{ not json");
  CHECK(!r.ok && !r.error.empty());

  r = aseprite::parse("[1, 2]");
  CHECK(!r.ok);

  r = aseprite::parse(R"J({"frames": {}})J");
  CHECK(!r.ok);

  r = aseprite::parse(R"J({"frames": [{"duration": 100}]})J");
  CHECK(!r.ok);

  // Tag fuera de rango
  r = aseprite::parse(R"J({
    "frames": [{"frame": {"x": 0, "y": 0, "w": 8, "h": 8}}],
    "meta": {"frameTags": [{"name": "t", "from": 0, "to": 3}]}
  })J");
  CHECK(!r.ok);
}

static void testForwardTiming() {
  aseprite::Atlas atlas = loadOk(HASH_PATH);

  // idle: frame 0 (100 ms), frame 1 (200 ms), total 300
  CHECK(played(atlas, "idle", true, 0).frameIndex(atlas) == 0);
  CHECK(played(atlas, "idle", true, 99).frameIndex(atlas) == 0);
  CHECK(played(atlas, "idle", true, 100).frameIndex(atlas) == 1);
  CHECK(played(atlas, "idle", true, 299).frameIndex(atlas) == 1);
  CHECK(played(atlas, "idle", true, 300).frameIndex(atlas) == 0);
  // Acumulando en varios pasos
  aseprite::Playback p = played(atlas, "idle", true, 50);
  p.advance(atlas, 49);
  CHECK(p.frameIndex(atlas) == 0);
  p.advance(atlas, 1);
  CHECK(p.frameIndex(atlas) == 1);
}

static void testLoopAndOnce() {
  aseprite::Atlas atlas = loadOk(HASH_PATH);

  // Loop: vuelve a empezar
  aseprite::Playback p = played(atlas, "idle", true, 350);
  CHECK(p.frameIndex(atlas) == 0);
  CHECK(!p.finished);
  p.advance(atlas, 50);  // 400 en total
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(!p.finished);

  // Sin loop: se queda en el ultimo frame y termina al agotar su duracion
  p = played(atlas, "idle", false, 100);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(!p.finished);
  p.advance(atlas, 199);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(!p.finished);
  p.advance(atlas, 1);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(p.finished);
  p.advance(atlas, 1000);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(p.finished);

  CHECK(played(atlas, "idle", false, 5000).finished);
}

static void testReverse() {
  aseprite::Atlas atlas = loadOk(HASH_PATH);

  // rev: frames 3 (50 ms), 2 (100 ms), 1 (200 ms)
  aseprite::Playback p = played(atlas, "rev", true, 0);
  CHECK(p.frameIndex(atlas) == 3);
  p.advance(atlas, 50);
  CHECK(p.frameIndex(atlas) == 2);
  p.advance(atlas, 100);
  CHECK(p.frameIndex(atlas) == 1);
  p.advance(atlas, 199);
  CHECK(p.frameIndex(atlas) == 1);
  p.advance(atlas, 1);
  CHECK(p.frameIndex(atlas) == 3);  // vuelta al principio

  p = played(atlas, "rev", false, 350);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(p.finished);
}

static void testPingPong() {
  aseprite::Atlas atlas = loadOk(HASH_PATH);

  // pp: 0,1,2,3,2,1 y vuelta; duraciones 100,200,100,50,100,200 (total 750)
  const int expected[] = {0, 1, 2, 3, 2, 1, 0, 1};
  const double waits[] = {0, 100, 200, 100, 50, 100, 200, 100};
  aseprite::Playback p;
  p.start(atlas.findTag("pp"), true);
  for (size_t i = 0; i < 8; i++) {
    p.advance(atlas, waits[i]);
    CHECK(p.frameIndex(atlas) == expected[i]);
    CHECK(!p.finished);
  }

  // Sin loop termina de vuelta en el primer frame: 0,1,2,3,2,1,0
  p.start(atlas.findTag("pp"), false);
  p.advance(atlas, 750);
  CHECK(p.frameIndex(atlas) == 0);
  CHECK(!p.finished);
  p.advance(atlas, 99);
  CHECK(!p.finished);
  p.advance(atlas, 1);
  CHECK(p.frameIndex(atlas) == 0);
  CHECK(p.finished);
}

static void testLargeDtAndRestart() {
  aseprite::Atlas atlas = loadOk(HASH_PATH);

  // 1e9 ms = 3333333 ciclos de 300 ms + 100 ms
  aseprite::Playback p = played(atlas, "idle", true, 1e9);
  CHECK(p.frameIndex(atlas) == 1);
  CHECK(!p.finished);

  // Reiniciar con otro tag arranca en su primer frame y descarta el tiempo
  p.start(atlas.findTag("rev"), true);
  CHECK(p.frameIndex(atlas) == 3);
  CHECK(!p.finished);
  p.advance(atlas, 49);
  CHECK(p.frameIndex(atlas) == 3);

  // dt <= 0 no mueve nada
  p.advance(atlas, 0);
  p.advance(atlas, -5);
  CHECK(p.frameIndex(atlas) == 3);
}

static void testSingleFrameTag() {
  aseprite::Result r = aseprite::parse(R"J({
    "frames": [
      {"frame": {"x": 0, "y": 0, "w": 8, "h": 8}, "duration": 100},
      {"frame": {"x": 8, "y": 0, "w": 8, "h": 8}, "duration": 100}
    ],
    "meta": {"frameTags": [{"name": "one", "from": 1, "to": 1, "direction": "pingpong"}]}
  })J");
  CHECK(r.ok);

  aseprite::Playback p = played(r.atlas, "one", true, 1000000);
  CHECK(p.frameIndex(r.atlas) == 1);
  CHECK(!p.finished);

  p = played(r.atlas, "one", false, 99);
  CHECK(p.frameIndex(r.atlas) == 1);
  CHECK(!p.finished);
  p.advance(r.atlas, 1);
  CHECK(p.frameIndex(r.atlas) == 1);
  CHECK(p.finished);
}

int main() {
  testParse();
  testImplicitTagAndDefaults();
  testErrors();
  testForwardTiming();
  testLoopAndOnce();
  testReverse();
  testPingPong();
  testLargeDtAndRestart();
  testSingleFrameTag();

  if (failures == 0) {
    std::cout << "AsepriteAtlasTest: OK" << std::endl;
    return 0;
  }
  std::cerr << "AsepriteAtlasTest: " << failures << " fallo(s)" << std::endl;
  return 1;
}
