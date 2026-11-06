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
