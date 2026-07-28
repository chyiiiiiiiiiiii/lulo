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

// Hash-based value noise. There is no sampler and no dynamic loop: the octaves
// below are unrolled by hand so the cost per pixel stays fixed and the 120 Hz
// raster budget stays predictable.
float hash21(vec2 p) {
  vec3 mixed = fract(vec3(p.x, p.y, p.x) * vec3(0.1031, 0.1030, 0.0973));
  mixed += dot(mixed, vec3(mixed.y, mixed.z, mixed.x) + 33.33);
  return fract((mixed.x + mixed.y) * mixed.z);
}

float valueNoise(vec2 p) {
  vec2 cell = floor(p);
  vec2 offset = fract(p);
  vec2 smoothed = offset * offset * (3.0 - 2.0 * offset);
  float corner00 = hash21(cell);
  float corner10 = hash21(cell + vec2(1.0, 0.0));
  float corner01 = hash21(cell + vec2(0.0, 1.0));
  float corner11 = hash21(cell + vec2(1.0, 1.0));
  return mix(
      mix(corner00, corner10, smoothed.x),
      mix(corner01, corner11, smoothed.x),
      smoothed.y);
}

// Four fixed octaves: amplitudes halve as frequencies double, the fractional
// Brownian sum that reads as drifting cloud.
float mistField(vec2 p) {
  float total = valueNoise(p) * 0.5;
  total += valueNoise(p * 2.02 + 11.3) * 0.25;
  total += valueNoise(p * 4.06 + 27.1) * 0.135;
  total += valueNoise(p * 8.11 + 43.7) * 0.065;
  return total / 0.95;
}

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

  // Three fixed, bounded analytic waves. No dynamic loop or sampled input.
  float wave0 =
      mix(
          sin(angle * 2.0 + time * 1.122 + uSeed * tau),
          sin(angle * 2.0 + workingPhase + uSeed * tau),
          uWorkingWeight);
  float wave1 =
      mix(
          sin(angle * 5.0 - time * 1.63 + uSeed * 3.0),
          sin(angle * 5.0 - speakingPhase + uSeed * 3.0),
          uSpeakingWeight);
  float wave2 =
      mix(
          sin(angle * 8.0 + time * 2.62 - uSeed * 2.0),
          sin(angle * 8.0 + speakingPhase * 2.0 - uSeed * 2.0),
          uSpeakingWeight);

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
      0.575 +
      idleBreath +
      listeningWave +
      thinkingWaves +
      speakingWaves +
      workingWave;

  // How hard the agent is working, used to drive both the speed and the reach
  // of the mist. Computed before the drift so it can scale it.
  float activity =
      clamp(
          uListeningWeight * 0.55 +
          uThinkingWeight * 0.85 +
          uSpeakingWeight +
          uWorkingWeight * 0.7,
          0.0,
          1.0);

  // The mist must repeat exactly once per state period, like the analytic
  // waves above. A linear drift would never repeat and its input would grow
  // without bound, which loses float precision in an always-on presence. So the
  // noise domain is moved around a circle whose phase is the state's own phase.
  //
  // Each state carries its own phase, so the vapour already travels faster
  // while the agent is busy: 2.4 seconds per turn while speaking against 5.6
  // while resting. Thinking has no phase of its own, so it doubles the resting
  // one rather than drifting as slowly as an idle agent.
  float idlePhase = tau * fract(time / 5.6);
  vec2 idleDrift = vec2(sin(idlePhase), cos(idlePhase));
  vec2 thinkingDrift = vec2(sin(idlePhase * 2.0), cos(idlePhase * 2.0));
  vec2 speakingDrift = vec2(sin(speakingPhase), cos(speakingPhase));
  vec2 workingDrift = vec2(sin(workingPhase), cos(workingPhase));
  vec2 mistDrift = mix(idleDrift, thinkingDrift, uThinkingWeight);
  mistDrift = mix(mistDrift, speakingDrift, uSpeakingWeight);
  mistDrift = mix(mistDrift, workingDrift, uWorkingWeight);

  // Busy states also sweep a wider arc, so the movement reads as more than a
  // change of tempo.
  float driftReach = 0.42 + activity * 0.30;
  vec2 mistDomain = point * 1.85 + mistDrift * driftReach + uSeed * 1.7;
  float cloud = mistField(mistDomain);
  vec2 swirl =
      vec2(point.x * 0.9 + point.y * 0.42, point.y * 0.9 - point.x * 0.42);
  float cloudDetail =
      mistField(swirl * 3.4 - vec2(mistDrift.y, mistDrift.x) * driftReach * 1.3);
  float cloudField = mix(cloud, cloudDetail, 0.38);
  // Raise the contrast of the field so individual puffs read as volume rather
  // than as a single soft blur.
  cloudField = clamp((cloudField - 0.5) * 1.55 + 0.5, 0.0, 1.0);
  cloudField = cloudField * cloudField * (3.0 - 2.0 * cloudField);

  // Faster turbulence that only appears while the agent is active, so motion
  // reads as effort rather than as constant noise. It completes two turns per
  // period so it stays periodic while moving faster than the base mist.
  vec2 fastDrift = vec2(sin(idlePhase * 2.0), cos(idlePhase * 2.0));
  fastDrift = mix(
      fastDrift,
      vec2(sin(idlePhase * 4.0), cos(idlePhase * 4.0)),
      uThinkingWeight);
  fastDrift = mix(
      fastDrift,
      vec2(sin(speakingPhase * 2.0), cos(speakingPhase * 2.0)),
      uSpeakingWeight);
  fastDrift = mix(
      fastDrift,
      vec2(sin(workingPhase * 2.0), cos(workingPhase * 2.0)),
      uWorkingWeight);
  float turbulence = mistField(swirl * 5.6 + fastDrift * 0.8);
  cloudField =
      mix(cloudField, turbulence, activity * (0.16 + uAmplitude * 0.20));

  // The mist displaces the boundary rather than the boundary being an edge,
  // which is what makes the silhouette read as vapour.
  float wisp = (cloudField - 0.5) * (0.085 + activity * 0.05);
  float signedDistance = radius - (fieldRadius + wisp);

  // A wide, mist-modulated falloff. The body never resolves to a crisp outline.
  float density = 1.0 - smoothstep(-0.17, 0.11, signedDistance);
  density *= 0.34 + cloudField * 0.88;
  // A solid inner body keeps the silhouette reading as one presence instead of
  // a torn puff, while the mist above still softens its edge.
  float coreDensity = 1.0 - smoothstep(-0.50, -0.05, signedDistance);
  density = max(density, coreDensity * (0.80 + cloudField * 0.20));

  float haloAlpha =
      (1.0 - smoothstep(fieldRadius - 0.05, 1.02, radius)) *
      (0.10 + cloudField * 0.13);
  haloAlpha *=
      0.55 +
      0.30 * uListeningWeight +
      0.25 * uSpeakingWeight +
      uAmplitude * 0.08;

  float alpha = clamp(max(density, haloAlpha), 0.0, 1.0);
  // Fade the outermost ring to nothing so there is no window-shaped seam.
  alpha *= 1.0 - smoothstep(0.86, 1.04, radius);

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

  // Volume comes from a light direction combined with the mist field, so
  // denser puffs catch more light and the far side stays in shadow. Fragment
  // coordinates run downwards, so a negative y places the light above.
  vec3 lightDirection = normalize(vec3(-0.42, -0.58, 0.70));
  vec3 surface = normalize(vec3(point, max(0.32, 1.0 - radius)));
  float lambert = clamp(dot(surface, lightDirection), 0.0, 1.0);

  float depth = 1.0 - smoothstep(0.0, 0.92, radius);
  vec3 deep = stateColor * 0.16;
  // Keep the highlight inside the state's own hue family: a neutral white
  // addition here reads as a warm, dirty patch against the cool body.
  vec3 lit = stateColor * 1.62 + vec3(0.10, 0.14, 0.22);
  vec3 color =
      mix(deep, lit, clamp(cloudField * 0.72 + lambert * 0.52, 0.0, 1.0));
  color = mix(color, lit, depth * 0.26);

  // A soft interior glow keeps the centre from going flat, and the rim traces
  // where the vapour thins out.
  float glow = 1.0 - smoothstep(0.0, 0.58, radius);
  color += stateColor * glow * 0.42;
  float rim =
      smoothstep(0.30, 0.62, radius) * (1.0 - smoothstep(0.62, 0.95, radius));
  color += (stateColor + vec3(0.12)) * rim * cloudField * 0.42;
  color += vec3(0.28, 0.09, 0.05) * uErrorWeight * rim * 0.55;

  color = mix(graphite, color, clamp(uColorStrength, 0.0, 1.0));

  vec3 premultiplied = clamp(color, 0.0, 1.0) * alpha;
  fragColor = clamp(vec4(premultiplied, alpha), 0.0, 1.0);
}
