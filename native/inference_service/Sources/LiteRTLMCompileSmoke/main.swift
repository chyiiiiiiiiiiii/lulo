import LiteRTLM

@main
struct LiteRTLMCompileSmoke {
  static func main() async throws {
    let config = try EngineConfig(
      modelPath: "/nonexistent/no-model-smoke.litertlm",
      backend: .cpu(threadCount: 2),
      maxNumTokens: 1
    )
    let backendName = config.backend.rawValue
    let engine = Engine(engineConfig: config)

    print(
      "LiteRTLM no-model smoke: backend=\(backendName) "
        + "initialized=\(await engine.isInitialized())"
    )
  }
}
