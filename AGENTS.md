# Flutter Local Agent

- Keep `packages/agent_core` pure Dart; it must never import Flutter.
- Follow strict Red/Green TDD for every behavioral change.
- Keep `bootstrap.dart` and future `app_composition.dart` as the composition root.
- Do not add globals, static singletons, or a service locator.
- Run `dart run tool/verify.dart` before a checkpoint commit.
