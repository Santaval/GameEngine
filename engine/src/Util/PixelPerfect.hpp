#pragma once
#include <algorithm>
#include <cmath>

// Calculos del modo pixel-perfect (game.lua: logical_size + pixel_perfect).
// Header-only y sin SDL: lo usan Game, TextRenderSystem, CameraBindings y los tests.
namespace pixelperfect {

// Escala entera y desplazamiento (letterbox) del area logica dentro de la ventana/salida
struct Layout {
    int scale = 1;
    int offsetX = 0;
    int offsetY = 0;
};

// Escala entera maxima que cabe (minimo 1) y centra el area logica.
// Sin area logica (<= 0) devuelve la identidad: el modo esta apagado
inline Layout computeLayout(int outW, int outH, int logW, int logH) {
    Layout layout;
    if (logW <= 0 || logH <= 0) {
        return layout;
    }
    layout.scale = std::max(1, std::min(outW / logW, outH / logH));
    layout.offsetX = (outW - logW * layout.scale) / 2;
    layout.offsetY = (outH - logH * layout.scale) / 2;
    return layout;
}

// Redondeo al entero mas cercano para que la camara no tiemble entre pixeles
inline int snapCamera(double v) {
    return static_cast<int>(std::floor(v + 0.5));
}

// Ventana -> logico: quita el desplazamiento y divide por la escala
inline int windowToLogical(int win, int offset, int scale) {
    if (scale <= 0) {
        return win;
    }
    return static_cast<int>(std::floor(static_cast<double>(win - offset) / scale));
}

// Logico -> nativo (pixeles de la salida)
inline int logicalToNative(int v, int offset, int scale) {
    return offset + v * scale;
}

}  // namespace pixelperfect
