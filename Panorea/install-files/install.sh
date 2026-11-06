#!/bin/sh

if [ ! -f "bin/panorea" ]; then
    echo "Error: Binary not found. Please run build.sh first."
    exit 1
fi

echo "Installing Panorea to system binary path..."
sudo cp bin/panorea /usr/local/bin/panorea
sudo chmod +x /usr/local/bin/panorea

echo "Installation ended"
