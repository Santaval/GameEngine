CC = g++
STD = -std=c++17

# Suppress Clang warning for GCC pragmas in sol2
COMPILER_NAME := $(shell $(CC) --version 2>&1)
ifeq ($(findstring clang,$(COMPILER_NAME)),clang)
    WARN_FLAGS = -Wall -Wextra -Wno-unknown-warning-option
else
    WARN_FLAGS = -Wall -Wextra -Wno-template-body
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
LUA_PKG := $(firstword $(foreach p,lua5.4 lua lua5.3,$(shell pkg-config --exists $(p) 2>/dev/null && echo $(p))))

ifneq ($(LUA_PKG),)
    LUA_CFLAGS := $(shell pkg-config --cflags $(LUA_PKG) 2>/dev/null)
    LUA_LIBS   := $(shell pkg-config --libs $(LUA_PKG) 2>/dev/null)
endif

# Fallback: Homebrew Lua 5.4 paths
ifeq ($(LUA_LIBS),)
    LUA_CFLAGS := -I/usr/local/include/lua5.4 -I/usr/local/include -I/usr/local/opt/lua/include -I/opt/homebrew/include
    LUA_LIBS   := -L/usr/local/lib -L/usr/local/opt/lua/lib -L/opt/homebrew/lib -llua
endif

# Sol2 necesita saber la version de Lua: 503 si se detecto 5.3, 504 en el resto de casos
ifeq ($(LUA_PKG),lua5.3)
    SOL_LUA_VERSION = 503
else
    SOL_LUA_VERSION = 504
endif
CFLAGS += -DSOL_LUA_VERSION=$(SOL_LUA_VERSION)

# Dependencias de red (IXWebSocket + nlohmann/json), descargadas por scripts/fetch-deps.sh
DEPS_STAMP = libs/.deps-stamp
IXWS_DIR   = libs/IXWebSocket
IXWS_LIB   = $(IXWS_DIR)/libixwebsocket.a
IXWS_OBJ   = $(IXWS_DIR)/build

# IMPORTANT: Put LUA_CFLAGS before ./libs/lua/ so Clang picks up Lua 5.4 headers
# -isystem evita que los headers de terceros llenen la salida de -Wall -Wextra
INC_PATH = $(LUA_CFLAGS) $(SDL_CFLAGS) -I"./libs/" -I"./libs/lua/" -isystem $(IXWS_DIR) -isystem ./libs/
LFLAGS   = $(SDL_LIBS) $(LUA_LIBS) $(IXWS_LIB) -lz -lpthread

SRC = src/*.cpp \
      src/Game/*.cpp \
      src/ECS/*.cpp \
      src/AssetManager/*.cpp \
      src/ControllerManager/*.cpp \
      src/SceneManager/*.cpp \
      src/Network/*.cpp

.PHONY: build run clean clean-deps deps

build: $(DEPS_STAMP) $(IXWS_LIB)
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) $(SRC) $(LFLAGS) -o engine

deps:
	./scripts/fetch-deps.sh

$(DEPS_STAMP):
	./scripts/fetch-deps.sh

# IXWebSocket se compila una sola vez (sin TLS). El wildcard se evalua antes del
# fetch, por eso se recorre el directorio con un bucle de shell.
$(IXWS_LIB): $(DEPS_STAMP)
	mkdir -p $(IXWS_OBJ)
	for f in $(IXWS_DIR)/ixwebsocket/*.cpp; do \
		case "$$(basename $$f)" in IXSocketOpenSSL.cpp|IXSocketMbedTLS.cpp|IXSocketAppleSSL.cpp) continue;; esac; \
		$(CC) $(STD) -w -O2 -DIXWEBSOCKET_USE_ZLIB -I$(IXWS_DIR) -c $$f -o $(IXWS_OBJ)/$$(basename $$f .cpp).o || exit 1; \
	done
	ar rcs $@ $(IXWS_OBJ)/*.o

run:
	./engine

clean:
	rm -f engine

clean-deps:
	rm -rf $(IXWS_OBJ) $(IXWS_LIB)
