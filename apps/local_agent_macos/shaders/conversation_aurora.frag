#version 460 core

// The aurora under the composer while an answer has not begun.
//
// Ported from ChunUI's Aurora.metal (github.com/liseami/ChunUI):
//   Copyright (c) 2026 liseami (赵纯想). MIT License.
// Its simplex noise is Ashima Arts' webgl-noise
// (github.com/ashima/webgl-noise):
//   Copyright (C) 2011 Ashima Arts. MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform float uStrength;
uniform vec3 uStop0;
uniform vec3 uStop1;
uniform vec3 uStop2;

layout(location = 0) out vec4 fragColor;

vec3 permute(vec3 x) {
  return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float simplexNoise(vec2 v) {
  const vec4 C = vec4(
      0.211324865405187, 0.366025403784439,
      -0.577350269189626, 0.024390243902439);
  vec2 i = floor(v + dot(v, C.yy));
  vec2 x0 = v - i + dot(i, C.xx);
  vec2 i1 = (x0.x > x0.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  vec4 x12 = x0.xyxy + C.xxzz;
  x12.xy -= i1;
  i = mod(i, 289.0);
  vec3 p = permute(
      permute(i.y + vec3(0.0, i1.y, 1.0)) + i.x + vec3(0.0, i1.x, 1.0));
  vec3 m = max(
      0.5 - vec3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)),
      0.0);
  m = m * m;
  m = m * m;
  vec3 x = 2.0 * fract(p * C.www) - 1.0;
  vec3 h = abs(x) - 0.5;
  vec3 ox = floor(x + 0.5);
  vec3 a0 = x - ox;
  m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
  vec3 g;
  g.x = a0.x * x0.x + h.x * x0.y;
  g.yz = a0.yz * x12.xz + h.yz * x12.yw;
  return 130.0 * dot(m, g);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uSize, vec2(1.0));

  // Three stops across the width. The original walks an array in a loop;
  // two fixed mixes cost the same every pixel.
  vec3 ramp = uv.x < 0.5
      ? mix(uStop0, uStop1, uv.x * 2.0)
      : mix(uStop1, uStop2, (uv.x - 0.5) * 2.0);

  // CCAuroraLayer's defaults: amplitude 0.7, blend 0.55. A wavelength factor
  // of 1.2 rather than 2.0 keeps the crests broad instead of peaked.
  const float amplitude = 0.7;
  const float blend = 0.55;
  float height =
      exp(simplexNoise(vec2(uv.x * 1.2 + uTime * 0.1, uTime * 0.25)) * 0.5 *
          amplitude);
  float intensity = 0.6 * (uv.y * 2.0 - height + 0.2);
  float alpha =
      smoothstep(0.20 - blend * 0.5, 0.20 + blend * 0.5, intensity) *
      uStrength;

  // Brightness held at 0.85 and above, lifted towards white at the crest,
  // so the thin end never turns into a dark smear.
  float glow = clamp(intensity, 0.0, 1.4);
  vec3 color = ramp * (0.85 + 0.35 * glow);
  color = mix(color, vec3(1.0), 0.22 * smoothstep(0.6, 1.4, glow));

  fragColor = clamp(vec4(color * alpha, alpha), 0.0, 1.0);
}
