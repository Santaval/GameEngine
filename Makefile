# Forwarder: el motor vive en engine/ y los juegos en games/<nombre>/.
# El binario es engine/engine y se lanza desde la raiz del repo (las rutas de
# los juegos son relativas a ella).

# Interprete de Lua independiente para games/aval/tests/map_determinism.lua y
# games/quebrada/tests/walker_math.lua, games/quebrada/tests/door_logic.lua,
# games/quebrada/tests/time_of_day_logic.lua, games/quebrada/tests/foco_logic.lua y games/quebrada/tests/save_logic.lua y games/quebrada/tests/tools_logic.lua y games/quebrada/tests/libreta_logic.lua y games/quebrada/tests/tileset_check.lua y games/quebrada/tests/roofs_logic.lua y games/quebrada/tests/buildings_check.lua y games/quebrada/tests/park_check.lua y games/quebrada/tests/school_check.lua y games/quebrada/tests/ebais_check.lua y games/quebrada/tests/monte_check.lua y games/quebrada/tests/rio_check.lua y games/quebrada/tests/triggers_logic.lua y games/quebrada/tests/zona1_check.lua (opcional)
LUA_BIN := $(firstword $(shell command -v lua5.3 lua5.4 lua 2>/dev/null))

# Node (opcional): generador del tileset del pueblo y de los edificios, games/quebrada/tools/tilegen (issues #55, #71).
# `make tiles` regenera games/quebrada/tilesets/town.{png,tsx}, maps/tiles_demo.tmx,
# tilesets/buildings.{png,tsx}, tilesets/park.{png,tsx} (parque), tilesets/school.{png,tsx} (escuela), tilesets/ebais.{png,tsx} (Ebais), tilesets/monte.{png,tsx} (el monte y los aerogeneradores), tilesets/rio.{png,tsx} (la quebrada y el puente), maps/buildings_demo.tmx, maps/house_mama.tmx y maps/zona1.tmx (issue #78);
# `make test` comprueba que lo versionado coincide con lo que genera el codigo.
# games/quebrada/tests/tileset_check.lua, buildings_check.lua, park_check.lua, school_check.lua, ebais_check.lua, monte_check.lua y rio_check.lua tambien validan esos archivos (opcional, con Lua).
NODE_BIN := $(firstword $(shell command -v node 2>/dev/null))
TILEGEN := games/quebrada/tools/tilegen/gen.mjs

.PHONY: build release test deps clean clean-deps lua-info run run-quebrada tiles

# `make release`: engine-bin compilado con -O2 (ver engine/Makefile)
build release deps clean clean-deps lua-info:
	$(MAKE) -C engine $@

test:
	$(MAKE) -C engine test
ifneq ($(LUA_BIN),)
	$(LUA_BIN) games/aval/tests/map_determinism.lua
	$(LUA_BIN) games/quebrada/tests/walker_math.lua
	$(LUA_BIN) games/quebrada/tests/door_logic.lua
	$(LUA_BIN) games/quebrada/tests/time_of_day_logic.lua
	$(LUA_BIN) games/quebrada/tests/foco_logic.lua
	$(LUA_BIN) games/quebrada/tests/save_logic.lua
	$(LUA_BIN) games/quebrada/tests/tools_logic.lua
	$(LUA_BIN) games/quebrada/tests/libreta_logic.lua
	$(LUA_BIN) games/quebrada/tests/tileset_check.lua
	$(LUA_BIN) games/quebrada/tests/roofs_logic.lua
	$(LUA_BIN) games/quebrada/tests/buildings_check.lua
	$(LUA_BIN) games/quebrada/tests/park_check.lua
	$(LUA_BIN) games/quebrada/tests/school_check.lua
	$(LUA_BIN) games/quebrada/tests/ebais_check.lua
	$(LUA_BIN) games/quebrada/tests/monte_check.lua
	$(LUA_BIN) games/quebrada/tests/rio_check.lua
	$(LUA_BIN) games/quebrada/tests/triggers_logic.lua
	$(LUA_BIN) games/quebrada/tests/zona1_check.lua
else
	@echo "Sin interprete de Lua (lua5.3/lua): se omiten games/aval/tests/map_determinism.lua y games/quebrada/tests/walker_math.lua y games/quebrada/tests/door_logic.lua y games/quebrada/tests/time_of_day_logic.lua y games/quebrada/tests/foco_logic.lua y games/quebrada/tests/save_logic.lua y games/quebrada/tests/tools_logic.lua y games/quebrada/tests/libreta_logic.lua y games/quebrada/tests/tileset_check.lua y games/quebrada/tests/roofs_logic.lua y games/quebrada/tests/buildings_check.lua y games/quebrada/tests/park_check.lua y games/quebrada/tests/school_check.lua y games/quebrada/tests/ebais_check.lua y games/quebrada/tests/monte_check.lua y games/quebrada/tests/rio_check.lua y games/quebrada/tests/triggers_logic.lua y games/quebrada/tests/zona1_check.lua"
endif
ifneq ($(NODE_BIN),)
	$(NODE_BIN) $(TILEGEN) --check
else
	@echo "Sin node: se omite la comprobacion del generador del tileset ($(TILEGEN) --check)"
endif

tiles:
ifneq ($(NODE_BIN),)
	$(NODE_BIN) $(TILEGEN)
else
	@echo "Hace falta node para regenerar el tileset ($(TILEGEN))"; exit 1
endif

run:
	./engine/engine-bin

run-quebrada:
	./engine/engine-bin --game quebrada
