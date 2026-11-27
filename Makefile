# Forwarder: el motor vive en engine/ y los juegos en games/<nombre>/.
# El binario es engine/engine y se lanza desde la raiz del repo (las rutas de
# los juegos son relativas a ella).

# Interprete de Lua independiente para games/aval/tests/map_determinism.lua y
# games/quebrada/tests/walker_math.lua, games/quebrada/tests/door_logic.lua,
# games/quebrada/tests/time_of_day_logic.lua, games/quebrada/tests/foco_logic.lua y games/quebrada/tests/save_logic.lua y games/quebrada/tests/tools_logic.lua y games/quebrada/tests/libreta_logic.lua y games/quebrada/tests/tileset_check.lua (opcional)
LUA_BIN := $(firstword $(shell command -v lua5.3 lua5.4 lua 2>/dev/null))

# Node (opcional): generador del tileset del pueblo, games/quebrada/tools/tilegen (issue #55).
# `make tiles` regenera games/quebrada/tilesets/town.{png,tsx} y maps/tiles_demo.tmx;
# `make test` comprueba que lo versionado coincide con lo que genera el codigo.
# games/quebrada/tests/tileset_check.lua tambien valida esos archivos (opcional, con Lua).
NODE_BIN := $(firstword $(shell command -v node 2>/dev/null))
TILEGEN := games/quebrada/tools/tilegen/gen.mjs

.PHONY: build test deps clean clean-deps lua-info run run-quebrada tiles

build deps clean clean-deps lua-info:
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
else
	@echo "Sin interprete de Lua (lua5.3/lua): se omiten games/aval/tests/map_determinism.lua y games/quebrada/tests/walker_math.lua y games/quebrada/tests/door_logic.lua y games/quebrada/tests/time_of_day_logic.lua y games/quebrada/tests/foco_logic.lua y games/quebrada/tests/save_logic.lua y games/quebrada/tests/tools_logic.lua y games/quebrada/tests/libreta_logic.lua y games/quebrada/tests/tileset_check.lua"
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
