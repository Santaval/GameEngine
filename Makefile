CC=g++
STD=-std=c++17
CFLAGS=-Wall -Wextra -Wno-template-body
INC_PATH=-I"./libs/" -I"./libs/lua/"
SRC=src/*.cpp \
	src/Game/*.cpp \
	src/ECS/*.cpp \
	src/AssetManager/*.cpp \
	src/ControllerManager/*.cpp
LFLAGS=-lSDL2 -lSDL2_image -lSDL2_ttf -llua5.3

build: 
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) $(SRC) $(LFLAGS) -o engine

 run:
	./engine

clean:
	rm engine