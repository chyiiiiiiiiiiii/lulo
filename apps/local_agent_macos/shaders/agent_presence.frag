#version 460 core

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uTimeSeconds;
uniform float uIdleWeight;
uniform float uListeningWeight;
uniform float uThinkingWeight;
uniform float uSpeakingWeight;
uniform float uWorkingWeight;
uniform float uErrorWeight;
uniform float uAmplitude;
uniform float uMotionScale;
uniform float uColorStrength;
uniform float uSeed;

layout(location = 0) out vec4 fragColor;

void main() {
  vec2 normalized = FlutterFragCoord().xy / max(uSize, vec2(1.0));
  vec2 point = (normalized - 0.5) * 2.0;
  point.x *= uSize.x / max(uSize.y, 1.0);

  float radius = length(point);
  float angle = atan(point.y, point.x);
  float time = uTimeSeconds * uMotionScale;
  float tau = 6.28318530718;
  float speakingPhase = tau * fract(time / 2.4);
  float workingPhase = tau * fract(time / 1.6);
  float primaryPhase =
      mix(time * 1.122, workingPhase, uWorkingWeight);
  float secondaryPhase =
      mix(-time * 1.63, -speakingPhase, uSpeakingWeight);
  float tertiaryPhase =
      mix(time * 2.62, speakingPhase * 2.0, uSpeakingWeight);

  // Three fixed, bounded analytic waves. No dynamic loop or sampled input.
  float wave0 = sin(angle * 2.0 + primaryPhase + uSeed * tau);
  float wave1 = sin(angle * 5.0 + secondaryPhase + uSeed * 3.0);
  float wave2 = sin(angle * 8.0 + tertiaryPhase - uSeed * 2.0);

  float idleBreath =
      uIdleWeight * sin(time * tau / 5.6 + uSeed) * 0.012;
  float listeningWave =
      uListeningWeight * wave0 * (0.014 + uAmplitude * 0.036);
  float thinkingWaves =
      uThinkingWeight * (wave0 * 0.020 + wave1 * 0.015);
  float speakingWaves =
      uSpeakingWeight *
      (wave1 * 0.014 + wave2 * (0.018 + uAmplitude * 0.030));
  float workingWave = uWorkingWeight * wave0 * 0.010;
  float fieldRadius =
      0.625 +
      idleBreath +
      listeningWave +
      thinkingWaves +
      speakingWaves +
      workingWave;

  float signedDistance = radius - fieldRadius;
  float bodyAlpha = 1.0 - smoothstep(-0.025, 0.025, signedDistance);
  float haloAlpha =
      (1.0 - smoothstep(fieldRadius + 0.01, 0.98, radius)) *
      (1.0 - bodyAlpha) *
      0.16;
  haloAlpha *=
      0.55 +
      0.30 * uListeningWeight +
      0.25 * uSpeakingWeight +
      uAmplitude * 0.08;
  float alpha = clamp(max(bodyAlpha, haloAlpha), 0.0, 1.0);

  vec3 graphite = vec3(0.025, 0.031, 0.052);
  vec3 idleColor = vec3(0.25, 0.29, 0.50);
  vec3 listeningColor = vec3(0.20, 0.53, 0.50);
  vec3 thinkingColor = vec3(0.34, 0.29, 0.58);
  vec3 speakingColor = vec3(0.20, 0.44, 0.61);
  vec3 workingColor = vec3(0.34, 0.51, 0.47);
  vec3 errorColor = vec3(0.69, 0.31, 0.25);
  vec3 stateColor =
      idleColor * uIdleWeight +
      listeningColor * uListeningWeight +
      thinkingColor * uThinkingWeight +
      speakingColor * uSpeakingWeight +
      workingColor * uWorkingWeight +
      errorColor * uErrorWeight;

  float core = 1.0 - smoothstep(0.04, 0.70, radius);
  float rim = 1.0 - smoothstep(0.018, 0.105, abs(signedDistance));
  float listeningRipple =
      uListeningWeight *
      (1.0 -
       smoothstep(0.018, 0.075, abs(radius - (fieldRadius - 0.075))));
  float thinkingBand =
      uThinkingWeight *
      (1.0 -
       smoothstep(0.018, 0.072, abs(sin(radius * 17.0 + wave1 * 0.35))));
  float speakingBand =
      uSpeakingWeight *
      (1.0 -
       smoothstep(0.025, 0.10, abs(radius - 0.31 - wave2 * 0.018)));
  float seamDirection = cos(angle - workingPhase);
  float workingSeam =
      uWorkingWeight * pow(max(seamDirection, 0.0), 18.0) * rim;
  float errorRim = uErrorWeight * rim;

  vec3 color = mix(graphite, stateColor, (0.34 + core * 0.55));
  color += vec3(0.08, 0.11, 0.16) * rim * 0.50;
  color += vec3(0.10, 0.18, 0.17) * listeningRipple * 0.55;
  color += vec3(0.08, 0.07, 0.16) * thinkingBand * 0.35;
  color += vec3(0.07, 0.14, 0.20) * speakingBand * 0.45;
  color += vec3(0.26, 0.18, 0.07) * workingSeam;
  color += vec3(0.25, 0.09, 0.04) * errorRim * 0.65;
  color = mix(graphite, color, clamp(uColorStrength, 0.0, 1.0));

  vec3 premultiplied = clamp(color, 0.0, 1.0) * alpha;
  fragColor = clamp(vec4(premultiplied, alpha), 0.0, 1.0);
}
