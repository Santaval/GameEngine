CC = g++
STD = -std=c++17

# Suppress Clang warning for GCC pragmas in sol2
COMPILER_NAME := $(shell $(CC) --version 2>&1)

# -Wno-template-body solo existe en GCC >= 15. GCC acepta cualquier -Wno-* que no
# conozca y solo se queja si salta otro diagnostico, asi que se prueba la forma
# positiva del flag, que si se rechaza al instante.
TEMPLATE_BODY_FLAG := $(shell echo 'int main(){}' | $(CC) -Wtemplate-body -Werror -x c++ - -o /dev/null 2>/dev/null && echo -Wno-template-body)

ifeq ($(findstring clang,$(COMPILER_NAME)),clang)
    WARN_FLAGS = -Wall -Wextra -Wno-unknown-warning-option
else
    WARN_FLAGS = -Wall -Wextra $(TEMPLATE_BODY_FLAG)
endif

CFLAGS = $(WARN_FLAGS)

# Detect pkg-config for SDL2
PKG_CONFIG_EXISTS := $(shell command -v pkg-config 2> /dev/null)

ifneq ($(PKG_CONFIG_EXISTS),)
    SDL_CFLAGS := $(shell pkg-config --cflags sdl2 sdl2_image sdl2_ttf 2>/dev/null)
    SDL_LIBS   := $(shell pkg-config --libs sdl2 sdl2_image sdl2_ttf 2>/dev/null)
endif

ifeq ($(SDL_CFLAGS),)
    SDL_CFLAGS := -I/usr/local/include -I/opt/homebrew/include
endif

ifeq ($(SDL_LIBS),)
    SDL_LIBS := -lSDL2 -lSDL2_image -lSDL2_ttf
endif

# Detect Lua via pkg-config (cada paquete por separado: si uno no existe, pkg-config falla con todos)
LUA_PKG := $(firstword $(foreach p,lua5.4 lua-5.4 lua54 lua lua5.3 lua-5.3 lua53,$(shell pkg-config --exists $(p) 2>/dev/null && echo $(p))))

ifneq ($(LUA_PKG),)
    LUA_CFLAGS := $(shell pkg-config --cflags $(LUA_PKG) 2>/dev/null)
    LUA_LIBS   := $(shell pkg-config --libs $(LUA_PKG) 2>/dev/null)
endif

# Fallback: Homebrew Lua 5.4 paths
ifeq ($(LUA_LIBS),)
    LUA_CFLAGS := -I/usr/local/include/lua5.4 -I/usr/local/include -I/usr/local/opt/lua/include -I/opt/homebrew/include
    LUA_LIBS   := -L/usr/local/lib -L/usr/local/opt/lua/lib -L/opt/homebrew/lib -llua
endif

# Sol2 necesita saber la version de Lua, y tiene que ser la del lua.h que de
# verdad abre el compilador: se lee LUA_VERSION_NUM preprocesando un include con
# los mismos flags, y en el mismo orden, que INC_PATH. Deducirla del nombre del
# paquete de pkg-config no vale (un lua.pc puede ser 5.3, y si no hay ninguno se
# acaba usando el 5.3 vendorizado en ./libs/lua/), y al equivocarse sol2 compila
# su codigo de 5.4 -- lua_newuserdatauv, LUA_GCGEN, LUA_GCINC -- contra 5.3.
LUA_INC := $(LUA_CFLAGS) -I./libs/lua/
LUA_VERSION_NUM := $(shell echo '#include <lua.h>' | $(CC) $(LUA_INC) -E -dM -x c++ - 2>/dev/null | sed -n 's/^#define LUA_VERSION_NUM[ \t]*//p')

ifeq ($(LUA_VERSION_NUM),)
    $(warning No se encontro lua.h con $(LUA_INC) -- instala un paquete de desarrollo de Lua (Debian/Ubuntu: liblua5.4-dev o liblua5.3-dev). Se asume 5.4.)
    SOL_LUA_VERSION = 504
else
    SOL_LUA_VERSION = $(LUA_VERSION_NUM)
endif
CFLAGS += -DSOL_LUA_VERSION=$(SOL_LUA_VERSION)

# Cruce de seguridad: si el paquete de pkg-config dice una version y el lua.h
# encontrado dice otra, se enlazaria contra una libreria distinta de los headers
# (fallos raros en tiempo de ejecucion). Normalmente significa que los headers
# vendorizados en ./libs/lua/ estan tapando los del sistema.
LUA_PKG_VERSION := $(strip $(if $(findstring 5.4,$(LUA_PKG)),504,$(if $(findstring 5.3,$(LUA_PKG)),503,)))
ifneq ($(LUA_PKG_VERSION),)
ifneq ($(LUA_PKG_VERSION),$(LUA_VERSION_NUM))
    $(warning pkg-config dio $(LUA_PKG) pero el lua.h encontrado es $(LUA_VERSION_NUM): revisa LUA_CFLAGS y los headers de ./libs/lua/ -- make lua-info)
endif
endif

# Dependencias de red (IXWebSocket + nlohmann/json), descargadas por scripts/fetch-deps.sh
DEPS_STAMP = libs/.deps-stamp
IXWS_DIR   = libs/IXWebSocket
IXWS_LIB   = $(IXWS_DIR)/libixwebsocket-tls.a
IXWS_OBJ   = $(IXWS_DIR)/build-tls

# TLS (wss://) con OpenSSL. Los mismos defines van al motor y a la libreria para
# que las clases de IXWebSocket tengan el mismo layout en ambos lados.
OPENSSL_CFLAGS := $(shell pkg-config --cflags openssl 2>/dev/null)
OPENSSL_LIBS   := $(shell pkg-config --libs openssl 2>/dev/null)
ifeq ($(OPENSSL_LIBS),)
    OPENSSL_CFLAGS := -I/usr/local/opt/openssl/include -I/opt/homebrew/opt/openssl/include
    OPENSSL_LIBS   := -L/usr/local/opt/openssl/lib -L/opt/homebrew/opt/openssl/lib -lssl -lcrypto
endif
IXWS_DEFS = -DIXWEBSOCKET_USE_ZLIB -DIXWEBSOCKET_USE_TLS -DIXWEBSOCKET_USE_OPEN_SSL
CFLAGS += $(IXWS_DEFS)

# IMPORTANT: Put LUA_CFLAGS before ./libs/lua/ so Clang picks up Lua 5.4 headers
# -isystem evita que los headers de terceros llenen la salida de -Wall -Wextra
INC_PATH = $(LUA_CFLAGS) $(SDL_CFLAGS) -I"./libs/" -I"./libs/lua/" -isystem $(IXWS_DIR) -isystem ./libs/
LFLAGS   = $(SDL_LIBS) $(LUA_LIBS) $(IXWS_LIB) $(OPENSSL_LIBS) -lz -lpthread

SRC = src/*.cpp \
      src/Game/*.cpp \
      src/ECS/*.cpp \
      src/AssetManager/*.cpp \
      src/ControllerManager/*.cpp \
      src/SceneManager/*.cpp \
      src/Network/*.cpp

.PHONY: build run test clean clean-deps deps lua-info

build: $(DEPS_STAMP) $(IXWS_LIB)
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) $(SRC) $(LFLAGS) -o engine

deps:
	./scripts/fetch-deps.sh

$(DEPS_STAMP):
	./scripts/fetch-deps.sh

# IXWebSocket se compila una sola vez (con TLS via OpenSSL). El wildcard se evalua
# antes del fetch, por eso se recorre el directorio con un bucle de shell.
$(IXWS_LIB): $(DEPS_STAMP)
	mkdir -p $(IXWS_OBJ)
	for f in $(IXWS_DIR)/ixwebsocket/*.cpp; do \
		case "$$(basename $$f)" in IXSocketMbedTLS.cpp|IXSocketAppleSSL.cpp) continue;; esac; \
		$(CC) $(STD) -w -O2 $(IXWS_DEFS) $(OPENSSL_CFLAGS) -I$(IXWS_DIR) -c $$f -o $(IXWS_OBJ)/$$(basename $$f .cpp).o || exit 1; \
	done
	ar rcs $@ $(IXWS_OBJ)/*.o

run:
	./engine

# Tests unitarios: NetworkRegistry, NetSyncSystem, DamageSync, WorldSync e ImpactDamage (solo ECS, sin SDL ni red) y LuaJson (solo sol + nlohmann)
test: $(DEPS_STAMP)
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) -I./src tests/NetworkRegistryTest.cpp src/ECS/*.cpp src/Network/NetworkRegistry.cpp -o tests/network_registry_test
	./tests/network_registry_test
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) tests/NetSyncTest.cpp src/ECS/*.cpp src/Network/NetworkRegistry.cpp -o tests/net_sync_test
	./tests/net_sync_test
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) tests/DamageSyncTest.cpp src/ECS/*.cpp src/Network/NetworkRegistry.cpp -o tests/damage_sync_test
	./tests/damage_sync_test
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) tests/WorldSyncTest.cpp src/ECS/*.cpp src/Network/NetworkRegistry.cpp -o tests/world_sync_test
	./tests/world_sync_test
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) tests/LuaJsonTest.cpp $(LUA_LIBS) -o tests/lua_json_test
	./tests/lua_json_test
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) tests/ImpactDamageTest.cpp -o tests/impact_damage_test
	./tests/impact_damage_test

clean:
	rm -f engine tests/network_registry_test tests/net_sync_test tests/damage_sync_test tests/world_sync_test tests/lua_json_test tests/impact_damage_test

clean-deps:
	rm -rf $(IXWS_OBJ) $(IXWS_LIB) $(IXWS_DIR)/build $(IXWS_DIR)/libixwebsocket.a

# Imprime que Lua se ha detectado, para diagnosticar fallos de version con sol2
lua-info:
	@echo "LUA_PKG         = $(LUA_PKG)"
	@echo "LUA_CFLAGS      = $(LUA_CFLAGS)"
	@echo "LUA_LIBS        = $(LUA_LIBS)"
	@echo "LUA_VERSION_NUM = $(LUA_VERSION_NUM)"
	@echo "SOL_LUA_VERSION = $(SOL_LUA_VERSION)"
