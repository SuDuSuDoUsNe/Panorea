#!/bin/sh
mkdir -p bin

if [ -f "panorea.pas" ]; then
    fpc -O2 -Xt panorea.pas
    if [ $? -eq 0 ]; then
        mv panorea bin/panorea
        rm -f panorea.o
        echo "Compilation successful. Binary created at ./bin/panorea"
    fi
else
    echo "Error: panorea.pas not found in the current directory."
fi

if [ -f "midi2music.pas" ]; then
    fpc -O2 -Xt midi2music.pas
    if [ $? -eq 0 ]; then
        mv midi2music bin/midi2music
        rm -f midi2music.o
        echo "Compilation successful. Binary created at ./bin/midi2music"
    fi
  else
    echo "Error: midi2music.pas not found in the current directory"
fi
