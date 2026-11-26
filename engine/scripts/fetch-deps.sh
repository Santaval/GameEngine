#!/usr/bin/env bash
# Descarga las librerias de red que se mantienen fuera de git (libs/ esta ignorado).
# Idempotente: lo que ya existe no se vuelve a bajar. Se puede ejecutar desde cualquier directorio (entra en engine/).
set -euo pipefail

cd "$(dirname "$0")/.."

IXWS_VERSION="v11.4.5"
JSON_VERSION="v3.11.3"
PUGI_VERSION="v1.14"

IXWS_URL="https://github.com/machinezone/IXWebSocket/archive/refs/tags/${IXWS_VERSION}.tar.gz"
JSON_URL="https://github.com/nlohmann/json/releases/download/${JSON_VERSION}/json.hpp"

PUGI_BASE="https://raw.githubusercontent.com/zeux/pugixml/${PUGI_VERSION}/src"

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

# pugixml (parser XML para los mapas TMX de Tiled). Se usa en modo header-only
# (PUGIXML_HEADER_ONLY solo en src/Map/TmxLoader.cpp), pero pugixml.hpp incluye
# pugixml.cpp, asi que se bajan los tres archivos.
if [ ! -f libs/pugixml/pugixml.hpp ] || [ ! -f libs/pugixml/pugixml.cpp ] || [ ! -f libs/pugixml/pugiconfig.hpp ]; then
    echo "[deps] Descargando pugixml ${PUGI_VERSION}"
    mkdir -p libs/pugixml
    for f in pugixml.hpp pugiconfig.hpp pugixml.cpp; do
        curl -fsSL "${PUGI_BASE}/${f}" -o "libs/pugixml/${f}"
    done
else
    echo "[deps] pugixml ya presente"
fi

# El Makefile depende de este archivo para saber que las dependencias estan listas
printf 'IXWebSocket %s\nnlohmann/json %s\npugixml %s\n' "$IXWS_VERSION" "$JSON_VERSION" "$PUGI_VERSION" > libs/.deps-stamp
