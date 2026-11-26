# Forwarder: el motor vive en engine/ y los juegos en games/<nombre>/.
# El binario es engine/engine y se lanza desde la raiz del repo (las rutas de
# los juegos son relativas a ella).

# Interprete de Lua independiente para games/aval/tests/map_determinism.lua (opcional)
LUA_BIN := $(firstword $(shell command -v lua5.3 lua5.4 lua 2>/dev/null))

.PHONY: build test deps clean clean-deps lua-info run run-quebrada

build deps clean clean-deps lua-info:
	$(MAKE) -C engine $@

test:
	$(MAKE) -C engine test
ifneq ($(LUA_BIN),)
	$(LUA_BIN) games/aval/tests/map_determinism.lua
else
	@echo "Sin interprete de Lua (lua5.3/lua): se omite games/aval/tests/map_determinism.lua"
endif

run:
	./engine/engine-bin

run-quebrada:
	./engine/engine-bin --game quebrada
