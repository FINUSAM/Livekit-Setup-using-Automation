#!/bin/bash

# Generate a random 32-character hexadecimal key (16 bytes)
API_KEY=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 32)

# Generate a random 64-character hexadecimal secret (32 bytes)
API_SECRET=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 64)

echo "Key: ${API_KEY}"
echo "Secret: ${API_SECRET}"