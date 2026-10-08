#!/usr/bin/env bash
# Descarga las librerias de red que se mantienen fuera de git (libs/ esta ignorado).
# Idempotente: lo que ya existe no se vuelve a bajar. Ejecutar desde la raiz del repo.
set -euo pipefail

cd "$(dirname "$0")/.."

IXWS_VERSION="v11.4.5"
JSON_VERSION="v3.11.3"

IXWS_URL="https://github.com/machinezone/IXWebSocket/archive/refs/tags/${IXWS_VERSION}.tar.gz"
JSON_URL="https://github.com/nlohmann/json/releases/download/${JSON_VERSION}/json.hpp"

mkdir -p libs

if [ ! -f libs/IXWebSocket/ixwebsocket/IXWebSocket.h ]; then
    echo "[deps] Descargando IXWebSocket ${IXWS_VERSION}"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL "$IXWS_URL" -o "$tmp/ixws.tar.gz"
    tar -xzf "$tmp/ixws.tar.gz" -C "$tmp"
    rm -rf libs/IXWebSocket
    mkdir -p libs/IXWebSocket
    cp -r "$tmp"/IXWebSocket-*/ixwebsocket libs/IXWebSocket/
    cp "$tmp"/IXWebSocket-*/LICENSE.txt libs/IXWebSocket/ 2>/dev/null || true
else
    echo "[deps] IXWebSocket ya presente"
fi

if [ ! -f libs/nlohmann/json.hpp ]; then
    echo "[deps] Descargando nlohmann/json ${JSON_VERSION}"
    mkdir -p libs/nlohmann
    curl -fsSL "$JSON_URL" -o libs/nlohmann/json.hpp
else
    echo "[deps] nlohmann/json ya presente"
fi

# El Makefile depende de este archivo para saber que las dependencias estan listas
printf 'IXWebSocket %s\nnlohmann/json %s\n' "$IXWS_VERSION" "$JSON_VERSION" > libs/.deps-stamp
