import 'dart:convert';
import 'dart:io';

const String _vendorRelativePath = 'native/vendor/litert_lm';
const String _inferenceServiceRelativePath = 'native/inference_service';
const String _releaseArchiveUrl =
    'https://github.com/google-ai-edge/LiteRT-LM/releases/download/'
    'v0.14.0/CLiteRTLM_mac.xcframework.zip';
const String _releaseArchiveChecksum =
    '450615483509aaa6d34b321fdc6862e41a224b674468ab10aff64ebe113d21b7';
const String _upstreamRevision = '80f301ff9a3b02c2c1e7be2dd1a567752f7b51b6';

const Map<String, String> _sourceChecksums = <String, String>{
  'Benchmark.swift':
      '33f131245456ceef8a2b8eaf8a5ea1ec310cec6124e3227f5e7a3ed35e0a3199',
  'Capabilities.swift':
      '30bc7cd1057f9100ef19249863266481a61e4c80d2a28ccb6098236318dee020',
  'Config.swift':
      '3f1c93449c679736b4e487376805161673b440c74244b07bb15c3c288e6aa929',
  'Conversation.swift':
      '178a722d7727febd319f9852b33f7094d1e6d251541f9e0f3ad210ae6694eadf',
  'Engine.swift':
      'aae9f14109d8cc6aeec34c6c67e6b49f096bad4d54b81813e5901a0efd8eab2c',
  'ExperimentalFlags.swift':
      'bc2d554c686a0db84d553174d1acffbcd38e151a8f10f3f0b78e747a11400621',
  'LiteRTLMError.swift':
      '0ab54191c0f0a01ce03b69b411b968400bee295d4672fb51519713f3f275dc85',
  'Message.swift':
      'c9f3bcaa02897e406b8e3208c9c9657c8035d4830ee61dd0c5a2a6536f814d55',
  'Tool.swift':
      'd9698c6c7f8425cfa1f479cec5070fe94d9ca732b3e20b171e3dd90ca1545422',
  'ToolManager.swift':
      '7fed45d66e562a153dd61e57a8cc67cbd89fa063d1c09d9d20626ea48574d3f7',
};

const String _licenseChecksum =
    'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4';
const String _compileSmokeChecksum =
    '7904978862d1050f52fc75f475e145fadc4a8a48439aad6da7379567e1684570';
const String _compileSmokeOutput =
    'LiteRTLM no-model smoke: backend=cpu initialized=false';

Future<void> main(List<String> arguments) async {
  try {
    await _main(arguments);
  } on _VerificationFailure catch (failure) {
    stderr.writeln(failure.message);
    exitCode = 1;
  }
}

Future<void> _main(List<String> arguments) async {
  if (arguments.contains('--self-test')) {
    await _runSelfTests(arguments);
    return;
  }
  final bool contractOnly = arguments.contains('--contract-only');
  final Directory workspace = Directory.current;
  final Directory vendor = Directory(
    _join(workspace.path, _vendorRelativePath),
  );
  final Directory wrapperSources = Directory(_join(vendor.path, 'swift'));
  final Directory inferenceService = Directory(
    _join(workspace.path, _inferenceServiceRelativePath),
  );
  final File compileSmokeSource = File(
    _join(inferenceService.path, 'Sources/LiteRTLMCompileSmoke/main.swift'),
  );

  _requireInTreeEntry(
    workspace,
    _vendorRelativePath,
    FileSystemEntityType.directory,
  );
  _requireInTreeEntry(
    workspace,
    '$_vendorRelativePath/swift',
    FileSystemEntityType.directory,
  );
  for (final String sourceName in _sourceChecksums.keys) {
    _requireInTreeEntry(
      workspace,
      '$_vendorRelativePath/swift/$sourceName',
      FileSystemEntityType.file,
    );
  }
  for (final String vendorFile in <String>[
    'LICENSE',
    'Package.swift',
    'PATCHES.md',
  ]) {
    _requireInTreeEntry(
      workspace,
      '$_vendorRelativePath/$vendorFile',
      FileSystemEntityType.file,
    );
  }
  _requireInTreeEntry(
    workspace,
    _inferenceServiceRelativePath,
    FileSystemEntityType.directory,
  );
  _requireInTreeEntry(
    workspace,
    '$_inferenceServiceRelativePath/Package.swift',
    FileSystemEntityType.file,
  );
  _requireInTreeEntry(
    workspace,
    '$_inferenceServiceRelativePath/Sources',
    FileSystemEntityType.directory,
  );
  _requireInTreeEntry(
    workspace,
    '$_inferenceServiceRelativePath/Sources/LiteRTLMCompileSmoke',
    FileSystemEntityType.directory,
  );
  _requireInTreeEntry(
    workspace,
    '$_inferenceServiceRelativePath/Sources/LiteRTLMCompileSmoke/main.swift',
    FileSystemEntityType.file,
  );

  final List<String> actualSourceEntries = _sourceTreeEntries(wrapperSources);
  final List<String> expectedSourceEntries =
      _sourceChecksums.keys.map((String name) => 'file:$name').toList()..sort();
  _require(
    _deepEquals(actualSourceEntries, expectedSourceEntries),
    'Vendored wrapper source set differs from official v0.14.0 production '
    'sources.\nExpected: $expectedSourceEntries'
    '\nActual: $actualSourceEntries',
  );

  for (final MapEntry<String, String> source in _sourceChecksums.entries) {
    await _requireChecksum(
      File(_join(wrapperSources.path, source.key)),
      source.value,
    );
  }
  await _requireChecksum(File(_join(vendor.path, 'LICENSE')), _licenseChecksum);
  await _requireChecksum(compileSmokeSource, _compileSmokeChecksum);

  final Map<String, dynamic> vendorPackage = await _dumpPackage(vendor);
  _validateVendorPackage(vendorPackage);

  final String patches = _read(_join(vendor.path, 'PATCHES.md'));
  for (final String provenance in <String>[
    'google-ai-edge/LiteRT-LM',
    'v0.14.0',
    _upstreamRevision,
    _releaseArchiveChecksum,
    'Apache-2.0',
    'Exit condition',
  ]) {
    _require(
      patches.contains(provenance),
      'PATCHES.md is missing provenance: $provenance',
    );
  }

  final Map<String, dynamic> inferencePackage = await _dumpPackage(
    inferenceService,
  );
  _validateInferencePackage(inferencePackage, vendor.absolute.path);

  final String podfile = _read(
    _join(workspace.path, 'apps/local_agent_macos/macos/Podfile'),
  );
  _validatePodfile(podfile);
  final String xcodeProject = _read(
    _join(
      workspace.path,
      'apps/local_agent_macos/macos/Runner.xcodeproj/project.pbxproj',
    ),
  );
  _validateXcodeDeploymentTargets(xcodeProject);

  if (contractOnly) {
    stdout.writeln('LiteRT-LM vendor contract passed.');
    return;
  }

  await _run('swift', <String>[
    'package',
    '--package-path',
    inferenceService.path,
    'resolve',
  ]);
  await _run('swift', <String>[
    'build',
    '--package-path',
    inferenceService.path,
    '--product',
    'LiteRTLMCompileSmoke',
  ]);
  final ProcessResult smokeResult = await _runCaptured('swift', <String>[
    'run',
    '--package-path',
    inferenceService.path,
    'LiteRTLMCompileSmoke',
  ]);
  final String smokeStdout = smokeResult.stdout.toString().trim();
  _require(
    smokeStdout == _compileSmokeOutput,
    'Compile-smoke output is not the expected no-model semantic result.\n'
    'Expected: $_compileSmokeOutput\n'
    'Actual: $smokeStdout',
  );
  stdout.writeln(smokeStdout);

  stdout.writeln(
    'LiteRT-LM vendor contract, compile, link, and no-model smoke passed.',
  );
}

List<String> _sourceTreeEntries(Directory root) {
  final List<String> entries = <String>[];
  for (final FileSystemEntity entity in root.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final String relativePath = entity.path
        .substring(root.path.length + 1)
        .split(Platform.pathSeparator)
        .join('/');
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    final String kind = switch (type) {
      FileSystemEntityType.file => 'file',
      FileSystemEntityType.directory => 'directory',
      FileSystemEntityType.link => 'link',
      _ => 'other',
    };
    entries.add('$kind:$relativePath');
  }
  return entries..sort();
}

void _requireInTreeEntry(
  Directory root,
  String relativePath,
  FileSystemEntityType expectedType,
) {
  final List<String> segments = relativePath.split('/');
  String currentPath = root.absolute.path;
  for (int index = 0; index < segments.length; index++) {
    currentPath = _join(currentPath, segments[index]);
    final FileSystemEntityType expected = index == segments.length - 1
        ? expectedType
        : FileSystemEntityType.directory;
    final FileSystemEntityType actual = FileSystemEntity.typeSync(
      currentPath,
      followLinks: false,
    );
    _require(
      actual == expected,
      'Required in-tree entry must be a regular ${_entryTypeLabel(expected)}: '
      '$relativePath (found ${_entryTypeLabel(actual)} at '
      "${segments.take(index + 1).join('/')})",
    );
  }

  final String resolvedRoot = root.resolveSymbolicLinksSync();
  final String resolvedEntry = switch (expectedType) {
    FileSystemEntityType.directory => Directory(
      currentPath,
    ).resolveSymbolicLinksSync(),
    FileSystemEntityType.file => File(currentPath).resolveSymbolicLinksSync(),
    _ => throw const _VerificationFailure('Unsupported required entry type.'),
  };
  _require(
    resolvedEntry.startsWith('$resolvedRoot${Platform.pathSeparator}'),
    'Required entry escapes the workspace: $relativePath',
  );
}

String _entryTypeLabel(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) {
    return 'file';
  }
  if (type == FileSystemEntityType.directory) {
    return 'directory';
  }
  if (type == FileSystemEntityType.link) {
    return 'symlink';
  }
  if (type == FileSystemEntityType.notFound) {
    return 'missing entry';
  }
  return 'other entry';
}

Future<Map<String, dynamic>> _dumpPackage(Directory package) async {
  final ProcessResult result = await Process.run('swift', <String>[
    'package',
    '--package-path',
    package.path,
    'dump-package',
  ], environment: _swiftEnvironment());
  _require(
    result.exitCode == 0,
    'Could not dump active package semantics for ${package.path}:\n'
    '${result.stdout}\n${result.stderr}',
  );
  final Object? decoded = jsonDecode(result.stdout.toString());
  _require(
    decoded is Map<String, dynamic>,
    'Swift package dump for ${package.path} was not a JSON object.',
  );
  return decoded! as Map<String, dynamic>;
}

void _validateVendorPackage(Map<String, dynamic> package) {
  _require(
    package['name'] == 'LiteRTLM',
    'Vendor package name must be LiteRTLM.',
  );
  _require(
    _deepEquals(_platformValues(package), <List<String>>[
      <String>['macos', '12.0'],
    ]),
    'Vendor package must actively declare only macOS 12.',
  );
  _require(
    _asList(package['dependencies']).isEmpty,
    'Vendor package must not add package dependencies.',
  );

  final List<dynamic> products = _asList(package['products']);
  _require(
    products.length == 1,
    'Vendor package must expose exactly one product.',
  );
  final Map<String, dynamic> product = _namedObject(
    products,
    'LiteRTLM',
    'vendor product',
  );
  _require(
    _deepEquals(product['targets'], <String>['LiteRTLM']),
    'LiteRTLM product must contain exactly the LiteRTLM target.',
  );
  _require(
    _deepEquals(product['type'], <String, dynamic>{
      'library': <dynamic>['automatic'],
    }),
    'LiteRTLM product must remain an automatic library.',
  );

  final List<dynamic> targets = _asList(package['targets']);
  final List<String> targetNames =
      targets.map((dynamic target) => _asMap(target)['name'] as String).toList()
        ..sort();
  _require(
    _deepEquals(targetNames, <String>['CLiteRTLM_mac', 'LiteRTLM']),
    'Vendor package target set is not exact.',
  );

  final Map<String, dynamic> binary = _namedObject(
    targets,
    'CLiteRTLM_mac',
    'vendor target',
  );
  _require(binary['type'] == 'binary', 'CLiteRTLM_mac must be binary.');
  _require(
    binary['url'] == _releaseArchiveUrl,
    'CLiteRTLM_mac active URL is not the official v0.14.0 archive.',
  );
  _require(
    binary['checksum'] == _releaseArchiveChecksum,
    'CLiteRTLM_mac active checksum is not the verified archive checksum.',
  );
  _require(
    _asList(binary['settings']).isEmpty,
    'CLiteRTLM_mac must not add build settings.',
  );

  final Map<String, dynamic> wrapper = _namedObject(
    targets,
    'LiteRTLM',
    'vendor target',
  );
  _require(wrapper['type'] == 'regular', 'LiteRTLM must be a regular target.');
  _require(wrapper['path'] == 'swift', 'LiteRTLM must compile only swift/.');
  _require(
    _deepEquals(wrapper['dependencies'], <Map<String, dynamic>>[
      <String, dynamic>{
        'byName': <dynamic>['CLiteRTLM_mac', null],
      },
    ]),
    'LiteRTLM must depend exactly on CLiteRTLM_mac.',
  );
  _require(
    _asList(wrapper['settings']).isEmpty,
    'LiteRTLM must not add unsafe or other build settings.',
  );
}

void _validateInferencePackage(
  Map<String, dynamic> package,
  String expectedVendorPath,
) {
  _require(
    package['name'] == 'InferenceService',
    'Inference package name must remain InferenceService.',
  );
  _require(
    _deepEquals(_platformValues(package), <List<String>>[
      <String>['macos', '12.0'],
    ]),
    'InferenceService must actively declare only macOS 12.',
  );

  final List<dynamic> dependencies = _asList(package['dependencies']);
  _require(
    dependencies.length == 1,
    'InferenceService must have exactly one package dependency.',
  );
  final List<dynamic> fileSystems = _asList(
    _asMap(dependencies.single)['fileSystem'],
  );
  _require(
    fileSystems.length == 1,
    'InferenceService dependency must be one local filesystem package.',
  );
  final Map<String, dynamic> dependency = _asMap(fileSystems.single);
  _require(
    dependency['identity'] == 'litert_lm',
    'InferenceService local dependency identity must be litert_lm.',
  );
  _require(
    dependency['path'] == expectedVendorPath,
    'InferenceService local dependency must resolve to $expectedVendorPath.',
  );

  final List<dynamic> products = _asList(package['products']);
  final List<String> productNames =
      products
          .map((dynamic product) => _asMap(product)['name'] as String)
          .toList()
        ..sort();
  _require(
    _deepEquals(productNames, <String>[
      'InferenceService',
      'LiteRTLMCompileSmoke',
    ]),
    'InferenceService package product set is not exact.',
  );
  final Map<String, dynamic> smokeProduct = _namedObject(
    products,
    'LiteRTLMCompileSmoke',
    'inference product',
  );
  _require(
    _deepEquals(smokeProduct['targets'], <String>['LiteRTLMCompileSmoke']),
    'Compile-smoke product must contain only its compile-smoke target.',
  );
  _require(
    _asMap(smokeProduct['type']).containsKey('executable'),
    'Compile-smoke product must be executable.',
  );
  _require(
    _asList(smokeProduct['settings']).isEmpty,
    'Compile-smoke product must not add settings.',
  );
  final Map<String, dynamic> inferenceProduct = _namedObject(
    products,
    'InferenceService',
    'inference product',
  );
  _require(
    _deepEquals(inferenceProduct['targets'], <String>['InferenceService']),
    'InferenceService library product must contain only its library target.',
  );
  _require(
    _deepEquals(inferenceProduct['type'], <String, dynamic>{
      'library': <dynamic>['automatic'],
    }),
    'InferenceService product must remain an automatic library.',
  );
  _require(
    _asList(inferenceProduct['settings']).isEmpty,
    'InferenceService product must not add settings.',
  );

  final List<dynamic> targets = _asList(package['targets']);
  final List<String> targetNames =
      targets.map((dynamic target) => _asMap(target)['name'] as String).toList()
        ..sort();
  _require(
    _deepEquals(targetNames, <String>[
      'InferenceService',
      'InferenceServiceTests',
      'LiteRTLMCompileSmoke',
    ]),
    'InferenceService package target set is not exact.',
  );
  final Map<String, dynamic> inferenceTarget = _namedObject(
    targets,
    'InferenceService',
    'inference target',
  );
  _require(
    inferenceTarget['type'] == 'regular',
    'InferenceService must remain a regular target.',
  );
  _require(
    _asList(inferenceTarget['dependencies']).isEmpty,
    'InferenceService target must not add dependencies.',
  );
  _require(
    _asList(inferenceTarget['settings']).isEmpty,
    'InferenceService target must not add build settings.',
  );
  final Map<String, dynamic> testsTarget = _namedObject(
    targets,
    'InferenceServiceTests',
    'inference target',
  );
  _require(
    testsTarget['type'] == 'test',
    'InferenceServiceTests must remain a test target.',
  );
  _require(
    _deepEquals(testsTarget['dependencies'], <Map<String, dynamic>>[
      <String, dynamic>{
        'byName': <dynamic>['InferenceService', null],
      },
    ]),
    'InferenceServiceTests must depend exactly on InferenceService.',
  );
  _require(
    _asList(testsTarget['settings']).isEmpty,
    'InferenceServiceTests must not add build settings.',
  );
  final Map<String, dynamic> smokeTarget = _namedObject(
    targets,
    'LiteRTLMCompileSmoke',
    'inference target',
  );
  _require(
    smokeTarget['type'] == 'executable',
    'Compile-smoke target must be executable.',
  );
  _require(
    _deepEquals(smokeTarget['dependencies'], <Map<String, dynamic>>[
      <String, dynamic>{
        'product': <dynamic>['LiteRTLM', 'litert_lm', null, null],
      },
    ]),
    'Compile-smoke target must depend exactly on local LiteRTLM.',
  );
  _require(
    _asList(smokeTarget['settings']).isEmpty,
    'Compile-smoke target must not add build settings.',
  );
}

void _validatePodfile(String podfile) {
  final RegExp platformPattern = RegExp(
    r'''^platform\s+:osx,\s*['"]([^'"]+)['"]\s*$''',
  );
  final List<String> activePlatformVersions = <String>[];
  for (final String line in podfile.split('\n')) {
    final String active = line.split('#').first.trim();
    if (active.isEmpty || !active.startsWith('platform')) {
      continue;
    }
    final RegExpMatch? match = platformPattern.firstMatch(active);
    _require(match != null, 'Unrecognized active Podfile platform: $active');
    activePlatformVersions.add(match!.group(1)!);
  }
  _require(
    _deepEquals(activePlatformVersions, <String>['12.0']),
    'Podfile must actively declare exactly one macOS 12.0 platform.',
  );
}

void _validateXcodeDeploymentTargets(String project) {
  const String projectListMarker =
      '/* Build configuration list for PBXProject "Runner" */ = {';
  final int projectListStart = project.indexOf(projectListMarker);
  _require(
    projectListStart >= 0,
    'Missing Runner PBXProject configuration list.',
  );
  final String projectList = _bracedObjectAt(project, projectListStart);
  final RegExp configurationReference = RegExp(
    r'^\s*([0-9A-F]+) /\* (Debug|Release|Profile) \*/,\s*$',
    multiLine: true,
  );
  final Map<String, String> configurationIds = <String, String>{};
  for (final RegExpMatch match in configurationReference.allMatches(
    projectList,
  )) {
    configurationIds[match.group(2)!] = match.group(1)!;
  }
  _require(
    _deepEquals(configurationIds.keys.toList()..sort(), <String>[
      'Debug',
      'Profile',
      'Release',
    ]),
    'Runner PBXProject must map Debug, Release, and Profile exactly once.',
  );
  for (final String name in <String>['Debug', 'Release', 'Profile']) {
    final String id = configurationIds[name]!;
    final String marker = '$id /* $name */ = {';
    final int configurationStart = project.indexOf(marker);
    _require(
      configurationStart >= 0,
      'Missing Runner $name build configuration $id.',
    );
    final String configuration = _bracedObjectAt(project, configurationStart);
    final RegExp assignment = RegExp(
      r'^[ \t]*MACOSX_DEPLOYMENT_TARGET[ \t]*=[ \t]*([^;]+);[ \t]*$',
      multiLine: true,
    );
    final List<String> values = assignment
        .allMatches(configuration)
        .map((RegExpMatch match) => match.group(1)!.trim())
        .toList();
    _require(
      _deepEquals(values, <String>['12.0']),
      'Runner $name must actively target macOS 12.0.',
    );
    _require(
      RegExp(
        '^\\s*name\\s*=\\s*$name;\\s*\$',
        multiLine: true,
      ).hasMatch(configuration),
      'Runner configuration $id must be named $name.',
    );
  }
}

String _bracedObjectAt(String source, int start) {
  final int openingBrace = source.indexOf('{', start);
  _require(openingBrace >= start, 'Missing opening brace at offset $start.');
  int depth = 0;
  for (int index = openingBrace; index < source.length; index++) {
    final String character = source[index];
    if (character == '{') {
      depth++;
    } else if (character == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(start, index + 1);
      }
    }
  }
  throw const _VerificationFailure('Unterminated Xcode object.');
}

List<List<String>> _platformValues(Map<String, dynamic> package) {
  return _asList(package['platforms']).map((dynamic platform) {
    final Map<String, dynamic> value = _asMap(platform);
    return <String>[
      value['platformName'] as String,
      value['version'] as String,
    ];
  }).toList();
}

Map<String, dynamic> _namedObject(
  List<dynamic> values,
  String name,
  String label,
) {
  final List<Map<String, dynamic>> matches = values
      .map(_asMap)
      .where((Map<String, dynamic> value) => value['name'] == name)
      .toList();
  _require(matches.length == 1, 'Expected exactly one $label named $name.');
  return matches.single;
}

Map<String, dynamic> _asMap(dynamic value) {
  _require(value is Map<String, dynamic>, 'Expected JSON object, got $value.');
  return value! as Map<String, dynamic>;
}

List<dynamic> _asList(dynamic value) {
  _require(value is List<dynamic>, 'Expected JSON list, got $value.');
  return value! as List<dynamic>;
}

bool _deepEquals(dynamic left, dynamic right) {
  if (left is List && right is List) {
    return left.length == right.length &&
        List<int>.generate(
          left.length,
          (int index) => index,
        ).every((int index) => _deepEquals(left[index], right[index]));
  }
  if (left is Map && right is Map) {
    return left.length == right.length &&
        left.keys.every(
          (dynamic key) =>
              right.containsKey(key) && _deepEquals(left[key], right[key]),
        );
  }
  return left == right;
}

Map<String, String> _swiftEnvironment() {
  final String moduleCache = _join(
    Directory.current.path,
    'native/inference_service/.build/vendor-contract-module-cache',
  );
  return <String, String>{
    'CLANG_MODULE_CACHE_PATH': moduleCache,
    'SWIFTPM_MODULECACHE_OVERRIDE_PATH': moduleCache,
  };
}

Future<void> _runSelfTests(List<String> arguments) async {
  final Directory sourceWorkspace = Directory.current;
  final Directory selfTestRoot = await Directory.systemTemp.createTemp(
    'litert-vendor-verifier-',
  );
  try {
    final Directory baseline = await _createFixture(
      sourceWorkspace,
      selfTestRoot,
      'baseline',
    );
    final ProcessResult baselineResult = await _runContractForFixture(baseline);
    _require(
      baselineResult.exitCode == 0,
      'Verifier self-test baseline failed:\n'
      '${baselineResult.stdout}\n${baselineResult.stderr}',
    );

    final List<_MutationCase> cases = <_MutationCase>[
      _MutationCase('nested unexpected source file', (Directory fixture) {
        final Directory nested = Directory(
          _join(fixture.path, 'native/vendor/litert_lm/swift/nested'),
        )..createSync(recursive: true);
        File(
          _join(nested.path, 'Extra.swift'),
        ).writeAsStringSync('// Unexpected nested source.\n');
      }),
      _MutationCase('unexpected source directory', (Directory fixture) {
        Directory(
          _join(fixture.path, 'native/vendor/litert_lm/swift/empty'),
        ).createSync(recursive: true);
      }),
      _MutationCase('required source symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(
            _join(
              fixture.path,
              'native/vendor/litert_lm/swift/Benchmark.swift',
            ),
          ),
          '../Benchmark.swift.real',
        );
      }),
      _MutationCase('wrapper source root symlink', (Directory fixture) {
        final Directory root = Directory(
          _join(fixture.path, 'native/vendor/litert_lm/swift'),
        );
        final Directory moved = Directory(
          _join(fixture.path, 'native/vendor/litert_lm/swift-real'),
        );
        root.renameSync(moved.path);
        Link(root.path).createSync('swift-real');
      }),
      _MutationCase('license symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(_join(fixture.path, 'native/vendor/litert_lm/LICENSE')),
          'LICENSE.real',
        );
      }),
      _MutationCase('patches symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(_join(fixture.path, 'native/vendor/litert_lm/PATCHES.md')),
          'PATCHES.md.real',
        );
      }),
      _MutationCase('vendor manifest symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(_join(fixture.path, 'native/vendor/litert_lm/Package.swift')),
          'Package.swift.real',
        );
      }),
      _MutationCase('inference manifest symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          'Package.swift.real',
        );
      }),
      _MutationCase('compile-smoke source symlink', (Directory fixture) {
        _replaceFileWithSymlink(
          File(
            _join(
              fixture.path,
              'native/inference_service/Sources/LiteRTLMCompileSmoke/main.swift',
            ),
          ),
          'main.swift.real',
        );
      }),
      _MutationCase('vendor platform semantics', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/vendor/litert_lm/Package.swift')),
          '.macOS(.v12)',
          '.macOS(.v13)',
        );
      }),
      _MutationCase('vendor binary URL semantics', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/vendor/litert_lm/Package.swift')),
          _releaseArchiveUrl,
          'https://invalid.test/Wrong.xcframework.zip',
        );
      }),
      _MutationCase('vendor binary checksum semantics', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/vendor/litert_lm/Package.swift')),
          _releaseArchiveChecksum,
          '0000000000000000000000000000000000000000000000000000000000000000',
        );
      }),
      _MutationCase('inference platform semantics', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.macOS(.v12)',
          '.macOS(.v13)',
        );
      }),
      _MutationCase('inference local dependency semantics', (
        Directory fixture,
      ) {
        _copyDirectorySync(
          Directory(_join(fixture.path, 'native/vendor/litert_lm')),
          Directory(_join(fixture.path, 'native/vendor/litert_lm_alternate')),
        );
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.package(path: "../vendor/litert_lm")',
          '.package(path: "../vendor/litert_lm_alternate")',
        );
      }),
      _MutationCase('inference library product type', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.library(name: "InferenceService", targets: ["InferenceService"])',
          '.executable(name: "InferenceService", '
              'targets: ["InferenceService"])',
        );
      }),
      _MutationCase('inference library product target mapping', (
        Directory fixture,
      ) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.library(name: "InferenceService", targets: ["InferenceService"])',
          '.library(name: "InferenceService", '
              'targets: ["LiteRTLMCompileSmoke"])',
        );
      }),
      _MutationCase('inference target dependency', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.target(name: "InferenceService"),',
          '''
.target(
      name: "InferenceService",
      dependencies: [
        .product(name: "LiteRTLM", package: "litert_lm"),
      ]
    ),''',
        );
      }),
      _MutationCase('inference target settings', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.target(name: "InferenceService"),',
          '''
.target(
      name: "InferenceService",
      swiftSettings: [.unsafeFlags(["-DUNSAFE"])]
    ),''',
        );
      }),
      _MutationCase('inference test dependency', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          'dependencies: ["InferenceService"]',
          'dependencies: []',
        );
      }),
      _MutationCase('inference test settings', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          'dependencies: ["InferenceService"]\n    )',
          'dependencies: ["InferenceService"],\n'
              '      swiftSettings: [.unsafeFlags(["-DUNSAFE"])]\n'
              '    )',
        );
      }),
      _MutationCase('compile-smoke product target mapping', (
        Directory fixture,
      ) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          'targets: ["LiteRTLMCompileSmoke"]\n    ),',
          'targets: ["InferenceService"]\n    ),',
        );
      }),
      _MutationCase('compile-smoke target dependency', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'native/inference_service/Package.swift')),
          '.product(name: "LiteRTLM", package: "litert_lm"),',
          '',
        );
      }),
      _MutationCase('no-op compile-smoke source edit', (Directory fixture) {
        final File source = File(
          _join(
            fixture.path,
            'native/inference_service/Sources/LiteRTLMCompileSmoke/main.swift',
          ),
        );
        source.writeAsStringSync('${source.readAsStringSync()}\n// no-op\n');
      }),
      _MutationCase('semantic compile-smoke source edit', (Directory fixture) {
        _mutateFile(
          File(
            _join(
              fixture.path,
              'native/inference_service/Sources/LiteRTLMCompileSmoke/main.swift',
            ),
          ),
          'LiteRTLM no-model smoke: backend=',
          'Wrong smoke output: backend=',
        );
      }),
      _MutationCase('Podfile deployment target', (Directory fixture) {
        _mutateFile(
          File(_join(fixture.path, 'apps/local_agent_macos/macos/Podfile')),
          "platform :osx, '12.0'",
          "platform :osx, '13.0'",
        );
      }),
      _MutationCase('Xcode Debug deployment target', (Directory fixture) {
        _mutateXcodeConfiguration(fixture, '33CC10F92044A3C60003C045');
      }),
      _MutationCase('Xcode Release deployment target', (Directory fixture) {
        _mutateXcodeConfiguration(fixture, '33CC10FA2044A3C60003C045');
      }),
      _MutationCase('Xcode Profile deployment target', (Directory fixture) {
        _mutateXcodeConfiguration(fixture, '338D0CE9231458BD00FA5F75');
      }),
    ];

    final String? selectedCase = arguments
        .where((String argument) => argument.startsWith('--self-test-case='))
        .map(
          (String argument) => argument.substring('--self-test-case='.length),
        )
        .firstOrNull;
    final List<_MutationCase> selectedCases = selectedCase == null
        ? cases
        : cases
              .where((_MutationCase test) => test.name == selectedCase)
              .toList();
    _require(
      selectedCases.isNotEmpty,
      'Unknown verifier self-test case: $selectedCase',
    );

    final List<String> acceptedMutations = <String>[];
    int caseIndex = 0;
    for (final _MutationCase test in selectedCases) {
      final Directory fixture = await _createFixture(
        sourceWorkspace,
        selfTestRoot,
        'case-${caseIndex++}',
      );
      final String before = _fixtureFingerprint(fixture);
      test.mutate(fixture);
      final String after = _fixtureFingerprint(fixture);
      _require(
        before != after,
        'Self-test mutation did not change its fixture: ${test.name}',
      );
      final ProcessResult result = await _runContractForFixture(fixture);
      if (result.exitCode == 0) {
        acceptedMutations.add(test.name);
      }
    }
    _require(
      acceptedMutations.isEmpty,
      'Verifier accepted forbidden mutations:\n'
      '${acceptedMutations.map((String name) => '- $name').join('\n')}',
    );
    stdout.writeln('LiteRT-LM vendor verifier self-test passed.');
  } finally {
    await selfTestRoot.delete(recursive: true);
  }
}

void _mutateXcodeConfiguration(Directory fixture, String configurationId) {
  final File project = File(
    _join(
      fixture.path,
      'apps/local_agent_macos/macos/Runner.xcodeproj/project.pbxproj',
    ),
  );
  final String original = project.readAsStringSync();
  final int configurationStart = original.indexOf('$configurationId /* ');
  _require(configurationStart >= 0, 'Missing Xcode fixture $configurationId.');
  final int configurationEnd = original.indexOf(
    '\n\t\t};',
    configurationStart + configurationId.length,
  );
  final int deployment = original.indexOf(
    'MACOSX_DEPLOYMENT_TARGET = 12.0;',
    configurationStart,
  );
  _require(
    deployment >= configurationStart &&
        configurationEnd >= 0 &&
        deployment < configurationEnd,
    'Xcode fixture $configurationId does not own macOS 12.0.',
  );
  project.writeAsStringSync(
    original.replaceRange(
      deployment,
      deployment + 'MACOSX_DEPLOYMENT_TARGET = 12.0;'.length,
      'MACOSX_DEPLOYMENT_TARGET = 13.0;',
    ),
  );
}

void _mutateFile(File file, String original, String replacement) {
  final String contents = file.readAsStringSync();
  _require(
    original != replacement && contents.split(original).length == 2,
    'Self-test expected exactly one mutation anchor in ${file.path}: $original',
  );
  final String mutated = contents.replaceFirst(original, replacement);
  _require(mutated != contents, 'Self-test did not mutate ${file.path}.');
  file.writeAsStringSync(mutated);
}

void _replaceFileWithSymlink(File file, String target) {
  final File moved = File(_join(file.parent.path, _basename(target)));
  file.renameSync(moved.path);
  Link(file.path).createSync(target);
}

String _fixtureFingerprint(Directory fixture) {
  final List<String> entries = <String>[];
  for (final FileSystemEntity entity in fixture.listSync(
    recursive: true,
    followLinks: false,
  )) {
    final String relativePath = entity.path
        .substring(fixture.path.length + 1)
        .split(Platform.pathSeparator)
        .join('/');
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    switch (type) {
      case FileSystemEntityType.file:
        entries.add(
          'file:$relativePath:${base64.encode(File(entity.path).readAsBytesSync())}',
        );
      case FileSystemEntityType.directory:
        entries.add('directory:$relativePath');
      case FileSystemEntityType.link:
        entries.add('link:$relativePath:${Link(entity.path).targetSync()}');
      default:
        entries.add('other:$relativePath');
    }
  }
  return (entries..sort()).join('\n');
}

void _copyDirectorySync(Directory source, Directory destination) {
  destination.createSync(recursive: true);
  for (final FileSystemEntity entity in source.listSync(followLinks: false)) {
    final String destinationPath = _join(
      destination.path,
      _basename(entity.path),
    );
    final FileSystemEntityType type = FileSystemEntity.typeSync(
      entity.path,
      followLinks: false,
    );
    switch (type) {
      case FileSystemEntityType.file:
        File(entity.path).copySync(destinationPath);
      case FileSystemEntityType.directory:
        _copyDirectorySync(entity as Directory, Directory(destinationPath));
      case FileSystemEntityType.link:
        Link(destinationPath).createSync(Link(entity.path).targetSync());
      default:
        throw StateError('Unsupported fixture entry: ${entity.path}');
    }
  }
}

final class _MutationCase {
  const _MutationCase(this.name, this.mutate);

  final String name;
  final void Function(Directory fixture) mutate;
}

Future<Directory> _createFixture(
  Directory sourceWorkspace,
  Directory selfTestRoot,
  String name,
) async {
  final Directory fixture = Directory(_join(selfTestRoot.path, name));
  await _copyDirectory(
    Directory(_join(sourceWorkspace.path, _vendorRelativePath)),
    Directory(_join(fixture.path, _vendorRelativePath)),
  );
  await _copyFile(
    File(_join(sourceWorkspace.path, 'native/inference_service/Package.swift')),
    File(_join(fixture.path, 'native/inference_service/Package.swift')),
  );
  await _copyFile(
    File(
      _join(
        sourceWorkspace.path,
        'native/inference_service/Sources/LiteRTLMCompileSmoke/main.swift',
      ),
    ),
    File(
      _join(
        fixture.path,
        'native/inference_service/Sources/LiteRTLMCompileSmoke/main.swift',
      ),
    ),
  );
  await _copyFile(
    File(_join(sourceWorkspace.path, 'apps/local_agent_macos/macos/Podfile')),
    File(_join(fixture.path, 'apps/local_agent_macos/macos/Podfile')),
  );
  await _copyFile(
    File(
      _join(
        sourceWorkspace.path,
        'apps/local_agent_macos/macos/Runner.xcodeproj/project.pbxproj',
      ),
    ),
    File(
      _join(
        fixture.path,
        'apps/local_agent_macos/macos/Runner.xcodeproj/project.pbxproj',
      ),
    ),
  );
  return fixture;
}

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await destination.create(recursive: true);
  await for (final FileSystemEntity entity in source.list()) {
    final String destinationPath = _join(
      destination.path,
      _basename(entity.path),
    );
    if (entity is File) {
      await entity.copy(destinationPath);
    } else if (entity is Directory) {
      await _copyDirectory(entity, Directory(destinationPath));
    } else if (entity is Link) {
      await Link(destinationPath).create(await entity.target());
    }
  }
}

Future<void> _copyFile(File source, File destination) async {
  await destination.parent.create(recursive: true);
  await source.copy(destination.path);
}

Future<ProcessResult> _runContractForFixture(Directory fixture) {
  return Process.run(Platform.resolvedExecutable, <String>[
    File(Platform.script.toFilePath()).absolute.path,
    '--contract-only',
  ], workingDirectory: fixture.path);
}

Future<void> _requireChecksum(File file, String expected) async {
  _require(file.existsSync(), 'Missing required file: ${file.path}');
  final ProcessResult result = await Process.run('shasum', <String>[
    '-a',
    '256',
    file.path,
  ]);
  _require(
    result.exitCode == 0,
    'Could not hash ${file.path}:\n${result.stderr}',
  );
  final String actual = result.stdout.toString().split(RegExp(r'\s+')).first;
  _require(
    actual == expected,
    'Checksum mismatch for ${file.path}.\nExpected: $expected\nActual: $actual',
  );
}

Future<void> _run(String executable, List<String> arguments) async {
  final Process process = await Process.start(
    executable,
    arguments,
    environment: _swiftEnvironment(),
    mode: ProcessStartMode.inheritStdio,
  );
  final int exitCode = await process.exitCode;
  _require(
    exitCode == 0,
    '$executable ${arguments.join(' ')} failed with exit $exitCode.',
  );
}

Future<ProcessResult> _runCaptured(
  String executable,
  List<String> arguments,
) async {
  final ProcessResult result = await Process.run(
    executable,
    arguments,
    environment: _swiftEnvironment(),
  );
  if (result.stderr.toString().isNotEmpty) {
    stderr.write(result.stderr);
  }
  _require(
    result.exitCode == 0,
    '$executable ${arguments.join(' ')} failed with exit ${result.exitCode}.',
  );
  return result;
}

String _read(String path) {
  final File file = File(path);
  _require(file.existsSync(), 'Missing required file: $path');
  return file.readAsStringSync();
}

String _join(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}

String _basename(String path) {
  return path.split(Platform.pathSeparator).last;
}

void _require(bool condition, String message) {
  if (!condition) {
    throw _VerificationFailure(message);
  }
}

final class _VerificationFailure implements Exception {
  const _VerificationFailure(this.message);

  final String message;
}
