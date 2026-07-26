#version 460 core

#include <flutter/runtime_effect.glsl>

precision mediump float;

layout(location = 0) out vec4 fragColor;

void main() {
  fragColor = vec4(0.12, 0.14, 0.24, 1.0);
}
