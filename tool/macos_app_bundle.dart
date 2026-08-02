import 'dart:io';

/// Workspace-relative location of the Flutter macOS application package.
const String macosAppPackagePath = 'apps/local_agent_macos';

/// Matches an `xcconfig` assignment to exactly `PRODUCT_NAME`.
///
/// Anchored on the key so that neighbours such as `PRODUCT_NAME_PREFIX` cannot
/// satisfy it: a substring match there would resolve the gate to a bundle that
/// was never built.
final RegExp _productNameAssignment = RegExp(r'^\s*PRODUCT_NAME\s*=\s*(.*)$');

/// Path of the Xcode configuration that declares the macOS product name.
String defaultAppInfoConfigPath(String workspaceRoot) {
  return '$workspaceRoot/$macosAppPackagePath'
      '/macos/Runner/Configs/AppInfo.xcconfig';
}

/// Reads the `PRODUCT_NAME` declared by the [xcconfig] configuration file.
///
/// Renaming the app has twice broken tooling that hard-coded the old name, so
/// callers resolve it from this single source instead. Throws a
/// [FormatException] whose message carries no filesystem path when the file is
/// absent or declares no product name.
String readProductName(File xcconfig) {
  if (!xcconfig.existsSync()) {
    throw const FormatException('app configuration file is missing.');
  }

  String? productName;
  for (final String line in xcconfig.readAsLinesSync()) {
    if (line.trimLeft().startsWith('//')) {
      continue;
    }
    final RegExpMatch? match = _productNameAssignment.firstMatch(line);
    if (match != null) {
      productName = _unquote(match.group(1)!.trim());
    }
  }

  if (productName == null || productName.isEmpty) {
    throw const FormatException(
      'PRODUCT_NAME is not declared in the app configuration.',
    );
  }
  return productName;
}

/// Absolute path of the bundle `flutter build macos` writes for
/// [configuration], given the [productName] declared by the app configuration.
String macosAppBundlePath({
  required String workspaceRoot,
  required String configuration,
  required String productName,
}) {
  return '$workspaceRoot/$macosAppPackagePath'
      '/build/macos/Build/Products/$configuration/$productName.app';
}

/// Removes one layer of surrounding double quotes from an `xcconfig` value.
String _unquote(String value) {
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    return value.substring(1, value.length - 1);
  }
  return value;
}
