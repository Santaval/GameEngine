CC=g++
STD=-std=c++17
CFLAGS=-Wall -Wno-template-body
INC_PATH=-I"./libs/" -I"./libs/lua/"
SRC=src/*.cpp
LFLAGS=-llua5.3

build: 
	$(CC) $(CFLAGS) $(STD) $(INC_PATH) $(SRC) $(LFLAGS) -o luatest

 run:
	./luatest

clean:
	rm luatest