/// How far the model is allowed to roam when it answers.
///
/// The one sampling dial a user has a reason to touch, named for what it does
/// to an answer rather than for the number behind it. Temperature and nucleus
/// probability move together because they are two halves of the same choice,
/// and offering them separately would be offering a decision nobody outside
/// the model has the information to make.
///
/// These are per generation, not per model: the sampler is part of the
/// request the host already receives, so changing one costs nothing and never
/// reloads the model.
enum AnswerStyle {
  /// Careful and repeatable. The same question tends to the same answer.
  steady(temperature: 0.2, topP: 0.9),

  /// What the app shipped with, and the default for that reason.
  balanced(temperature: 0.7, topP: 0.95),

  /// Freer, at the cost of steadiness. Useful for drafting, not for facts.
  inventive(temperature: 1, topP: 0.98);

  const AnswerStyle({required this.temperature, required this.topP});

  /// Sampling temperature handed to the runtime.
  final double temperature;

  /// Nucleus-sampling probability handed to the runtime.
  final double topP;
}
