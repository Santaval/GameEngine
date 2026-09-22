CC = g++
STD = -std=c++17

# Suppress Clang warning for GCC pragmas in sol2
COMPILER_NAME := $(shell $(CC) --version 2>&1 | head -n 1)
ifeq ($(findstring Free Software Foundation,$(COMPILER_NAME)),Free Software Foundation)
    WARN_FLAGS = -Wall -Wextra -Wno-template-body
else
    WARN_FLAGS = -Wall -Wextra -Wno-unknown-warning-option
endif

# Define SOL_LUA_VERSION=504 for Sol2
CFLAGS = $(WARN_FLAGS) -DSOL_LUA_VERSION=504

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

# Detect Lua via pkg-config or fallback to Homebrew Lua 5.4 paths
LUA_CFLAGS := $(shell pkg-config --cflags lua lua5.4 2>/dev/null)
LUA_LIBS   := $(shell pkg-config --libs lua lua5.4 2>/dev/null)

ifeq ($(LUA_LIBS),)
    LUA_CFLAGS := -I/usr/local/include/lua5.4 -I/usr/local/include -I/usr/local/opt/lua/include -I/opt/homebrew/include
    LUA_LIBS   := -L/usr/local/lib -L/usr/local/opt/lua/lib -L/opt/homebrew/lib -llua
endif

# IMPORTANT: Put LUA_CFLAGS before ./libs/lua/ so Clang picks up Lua 5.4 headers
INC_PATH = $(LUA_CFLAGS) $(SDL_CFLAGS) -I"./libs/" -I"./libs/lua/"
LFLAGS   = $(SDL_LIBS) $(LUA_LIBS)

SRC = src/*.cpp \
      src/Game/*.cpp \
      src/ECS/*.cpp \
      src/AssetManager/*.cpp \
      src/ControllerManager/*.cpp \
      src/SceneManager/*.cpp

build:
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) $(SRC) $(LFLAGS) -o engine

run:
	./engine

clean:
	rm -f engine