// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drift_conversation_storage_service.dart';

// ignore_for_file: type=lint
class $TurnRowsTable extends TurnRows with TableInfo<$TurnRowsTable, TurnRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TurnRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMsMeta = const VerificationMeta(
    'savedAtMs',
  );
  @override
  late final GeneratedColumn<int> savedAtMs = GeneratedColumn<int>(
    'saved_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rawTranscriptMeta = const VerificationMeta(
    'rawTranscript',
  );
  @override
  late final GeneratedColumn<String> rawTranscript = GeneratedColumn<String>(
    'raw_transcript',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refinedTranscriptMeta = const VerificationMeta(
    'refinedTranscript',
  );
  @override
  late final GeneratedColumn<String> refinedTranscript =
      GeneratedColumn<String>(
        'refined_transcript',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _refinementStatusMeta = const VerificationMeta(
    'refinementStatus',
  );
  @override
  late final GeneratedColumn<String> refinementStatus = GeneratedColumn<String>(
    'refinement_status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refinerIdMeta = const VerificationMeta(
    'refinerId',
  );
  @override
  late final GeneratedColumn<String> refinerId = GeneratedColumn<String>(
    'refiner_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refinerVersionMeta = const VerificationMeta(
    'refinerVersion',
  );
  @override
  late final GeneratedColumn<String> refinerVersion = GeneratedColumn<String>(
    'refiner_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _refinementEditsJsonMeta =
      const VerificationMeta('refinementEditsJson');
  @override
  late final GeneratedColumn<String> refinementEditsJson =
      GeneratedColumn<String>(
        'refinement_edits_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    status,
    content,
    savedAtMs,
    rawTranscript,
    refinedTranscript,
    refinementStatus,
    refinerId,
    refinerVersion,
    refinementEditsJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'turn_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TurnRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    } else if (isInserting) {
      context.missing(_roleMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('saved_at_ms')) {
      context.handle(
        _savedAtMsMeta,
        savedAtMs.isAcceptableOrUnknown(data['saved_at_ms']!, _savedAtMsMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMsMeta);
    }
    if (data.containsKey('raw_transcript')) {
      context.handle(
        _rawTranscriptMeta,
        rawTranscript.isAcceptableOrUnknown(
          data['raw_transcript']!,
          _rawTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('refined_transcript')) {
      context.handle(
        _refinedTranscriptMeta,
        refinedTranscript.isAcceptableOrUnknown(
          data['refined_transcript']!,
          _refinedTranscriptMeta,
        ),
      );
    }
    if (data.containsKey('refinement_status')) {
      context.handle(
        _refinementStatusMeta,
        refinementStatus.isAcceptableOrUnknown(
          data['refinement_status']!,
          _refinementStatusMeta,
        ),
      );
    }
    if (data.containsKey('refiner_id')) {
      context.handle(
        _refinerIdMeta,
        refinerId.isAcceptableOrUnknown(data['refiner_id']!, _refinerIdMeta),
      );
    }
    if (data.containsKey('refiner_version')) {
      context.handle(
        _refinerVersionMeta,
        refinerVersion.isAcceptableOrUnknown(
          data['refiner_version']!,
          _refinerVersionMeta,
        ),
      );
    }
    if (data.containsKey('refinement_edits_json')) {
      context.handle(
        _refinementEditsJsonMeta,
        refinementEditsJson.isAcceptableOrUnknown(
          data['refinement_edits_json']!,
          _refinementEditsJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TurnRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TurnRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      savedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}saved_at_ms'],
      )!,
      rawTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_transcript'],
      ),
      refinedTranscript: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refined_transcript'],
      ),
      refinementStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refinement_status'],
      ),
      refinerId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refiner_id'],
      ),
      refinerVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refiner_version'],
      ),
      refinementEditsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}refinement_edits_json'],
      ),
    );
  }

  @override
  $TurnRowsTable createAlias(String alias) {
    return $TurnRowsTable(attachedDatabase, alias);
  }
}

class TurnRow extends DataClass implements Insertable<TurnRow> {
  /// Monotonic insertion order, which is also the order things were said.
  final int id;

  /// The conversation this turn belongs to.
  final String conversationId;

  /// Who said it: stored by name, so reordering the enum cannot silently
  /// rewrite history.
  final String role;

  /// How the turn ended, stored by name for the same reason as [role].
  final String status;

  /// What was said. Named `content` because `text` is the column builder.
  final String content;

  /// When it was saved, in milliseconds since the epoch.
  final int savedAtMs;

  /// Exact recognizer output for a voice-authored user turn.
  final String? rawTranscript;

  /// Applied proposal, absent when raw text was selected.
  final String? refinedTranscript;

  /// [TranscriptRefinementStatus.name] for voice input.
  final String? refinementStatus;

  /// Stable refiner implementation identity.
  final String? refinerId;

  /// Refiner implementation or model version.
  final String? refinerVersion;

  /// JSON edit trail, rejection categories, and elapsed microseconds.
  final String? refinementEditsJson;
  const TurnRow({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.status,
    required this.content,
    required this.savedAtMs,
    this.rawTranscript,
    this.refinedTranscript,
    this.refinementStatus,
    this.refinerId,
    this.refinerVersion,
    this.refinementEditsJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['role'] = Variable<String>(role);
    map['status'] = Variable<String>(status);
    map['content'] = Variable<String>(content);
    map['saved_at_ms'] = Variable<int>(savedAtMs);
    if (!nullToAbsent || rawTranscript != null) {
      map['raw_transcript'] = Variable<String>(rawTranscript);
    }
    if (!nullToAbsent || refinedTranscript != null) {
      map['refined_transcript'] = Variable<String>(refinedTranscript);
    }
    if (!nullToAbsent || refinementStatus != null) {
      map['refinement_status'] = Variable<String>(refinementStatus);
    }
    if (!nullToAbsent || refinerId != null) {
      map['refiner_id'] = Variable<String>(refinerId);
    }
    if (!nullToAbsent || refinerVersion != null) {
      map['refiner_version'] = Variable<String>(refinerVersion);
    }
    if (!nullToAbsent || refinementEditsJson != null) {
      map['refinement_edits_json'] = Variable<String>(refinementEditsJson);
    }
    return map;
  }

  TurnRowsCompanion toCompanion(bool nullToAbsent) {
    return TurnRowsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      role: Value(role),
      status: Value(status),
      content: Value(content),
      savedAtMs: Value(savedAtMs),
      rawTranscript: rawTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(rawTranscript),
      refinedTranscript: refinedTranscript == null && nullToAbsent
          ? const Value.absent()
          : Value(refinedTranscript),
      refinementStatus: refinementStatus == null && nullToAbsent
          ? const Value.absent()
          : Value(refinementStatus),
      refinerId: refinerId == null && nullToAbsent
          ? const Value.absent()
          : Value(refinerId),
      refinerVersion: refinerVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(refinerVersion),
      refinementEditsJson: refinementEditsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(refinementEditsJson),
    );
  }

  factory TurnRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TurnRow(
      id: serializer.fromJson<int>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      role: serializer.fromJson<String>(json['role']),
      status: serializer.fromJson<String>(json['status']),
      content: serializer.fromJson<String>(json['content']),
      savedAtMs: serializer.fromJson<int>(json['savedAtMs']),
      rawTranscript: serializer.fromJson<String?>(json['rawTranscript']),
      refinedTranscript: serializer.fromJson<String?>(
        json['refinedTranscript'],
      ),
      refinementStatus: serializer.fromJson<String?>(json['refinementStatus']),
      refinerId: serializer.fromJson<String?>(json['refinerId']),
      refinerVersion: serializer.fromJson<String?>(json['refinerVersion']),
      refinementEditsJson: serializer.fromJson<String?>(
        json['refinementEditsJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'role': serializer.toJson<String>(role),
      'status': serializer.toJson<String>(status),
      'content': serializer.toJson<String>(content),
      'savedAtMs': serializer.toJson<int>(savedAtMs),
      'rawTranscript': serializer.toJson<String?>(rawTranscript),
      'refinedTranscript': serializer.toJson<String?>(refinedTranscript),
      'refinementStatus': serializer.toJson<String?>(refinementStatus),
      'refinerId': serializer.toJson<String?>(refinerId),
      'refinerVersion': serializer.toJson<String?>(refinerVersion),
      'refinementEditsJson': serializer.toJson<String?>(refinementEditsJson),
    };
  }

  TurnRow copyWith({
    int? id,
    String? conversationId,
    String? role,
    String? status,
    String? content,
    int? savedAtMs,
    Value<String?> rawTranscript = const Value.absent(),
    Value<String?> refinedTranscript = const Value.absent(),
    Value<String?> refinementStatus = const Value.absent(),
    Value<String?> refinerId = const Value.absent(),
    Value<String?> refinerVersion = const Value.absent(),
    Value<String?> refinementEditsJson = const Value.absent(),
  }) => TurnRow(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    status: status ?? this.status,
    content: content ?? this.content,
    savedAtMs: savedAtMs ?? this.savedAtMs,
    rawTranscript: rawTranscript.present
        ? rawTranscript.value
        : this.rawTranscript,
    refinedTranscript: refinedTranscript.present
        ? refinedTranscript.value
        : this.refinedTranscript,
    refinementStatus: refinementStatus.present
        ? refinementStatus.value
        : this.refinementStatus,
    refinerId: refinerId.present ? refinerId.value : this.refinerId,
    refinerVersion: refinerVersion.present
        ? refinerVersion.value
        : this.refinerVersion,
    refinementEditsJson: refinementEditsJson.present
        ? refinementEditsJson.value
        : this.refinementEditsJson,
  );
  TurnRow copyWithCompanion(TurnRowsCompanion data) {
    return TurnRow(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      role: data.role.present ? data.role.value : this.role,
      status: data.status.present ? data.status.value : this.status,
      content: data.content.present ? data.content.value : this.content,
      savedAtMs: data.savedAtMs.present ? data.savedAtMs.value : this.savedAtMs,
      rawTranscript: data.rawTranscript.present
          ? data.rawTranscript.value
          : this.rawTranscript,
      refinedTranscript: data.refinedTranscript.present
          ? data.refinedTranscript.value
          : this.refinedTranscript,
      refinementStatus: data.refinementStatus.present
          ? data.refinementStatus.value
          : this.refinementStatus,
      refinerId: data.refinerId.present ? data.refinerId.value : this.refinerId,
      refinerVersion: data.refinerVersion.present
          ? data.refinerVersion.value
          : this.refinerVersion,
      refinementEditsJson: data.refinementEditsJson.present
          ? data.refinementEditsJson.value
          : this.refinementEditsJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TurnRow(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('content: $content, ')
          ..write('savedAtMs: $savedAtMs, ')
          ..write('rawTranscript: $rawTranscript, ')
          ..write('refinedTranscript: $refinedTranscript, ')
          ..write('refinementStatus: $refinementStatus, ')
          ..write('refinerId: $refinerId, ')
          ..write('refinerVersion: $refinerVersion, ')
          ..write('refinementEditsJson: $refinementEditsJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    conversationId,
    role,
    status,
    content,
    savedAtMs,
    rawTranscript,
    refinedTranscript,
    refinementStatus,
    refinerId,
    refinerVersion,
    refinementEditsJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TurnRow &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.status == this.status &&
          other.content == this.content &&
          other.savedAtMs == this.savedAtMs &&
          other.rawTranscript == this.rawTranscript &&
          other.refinedTranscript == this.refinedTranscript &&
          other.refinementStatus == this.refinementStatus &&
          other.refinerId == this.refinerId &&
          other.refinerVersion == this.refinerVersion &&
          other.refinementEditsJson == this.refinementEditsJson);
}

class TurnRowsCompanion extends UpdateCompanion<TurnRow> {
  final Value<int> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String> status;
  final Value<String> content;
  final Value<int> savedAtMs;
  final Value<String?> rawTranscript;
  final Value<String?> refinedTranscript;
  final Value<String?> refinementStatus;
  final Value<String?> refinerId;
  final Value<String?> refinerVersion;
  final Value<String?> refinementEditsJson;
  const TurnRowsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.status = const Value.absent(),
    this.content = const Value.absent(),
    this.savedAtMs = const Value.absent(),
    this.rawTranscript = const Value.absent(),
    this.refinedTranscript = const Value.absent(),
    this.refinementStatus = const Value.absent(),
    this.refinerId = const Value.absent(),
    this.refinerVersion = const Value.absent(),
    this.refinementEditsJson = const Value.absent(),
  });
  TurnRowsCompanion.insert({
    this.id = const Value.absent(),
    required String conversationId,
    required String role,
    required String status,
    required String content,
    required int savedAtMs,
    this.rawTranscript = const Value.absent(),
    this.refinedTranscript = const Value.absent(),
    this.refinementStatus = const Value.absent(),
    this.refinerId = const Value.absent(),
    this.refinerVersion = const Value.absent(),
    this.refinementEditsJson = const Value.absent(),
  }) : conversationId = Value(conversationId),
       role = Value(role),
       status = Value(status),
       content = Value(content),
       savedAtMs = Value(savedAtMs);
  static Insertable<TurnRow> custom({
    Expression<int>? id,
    Expression<String>? conversationId,
    Expression<String>? role,
    Expression<String>? status,
    Expression<String>? content,
    Expression<int>? savedAtMs,
    Expression<String>? rawTranscript,
    Expression<String>? refinedTranscript,
    Expression<String>? refinementStatus,
    Expression<String>? refinerId,
    Expression<String>? refinerVersion,
    Expression<String>? refinementEditsJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (status != null) 'status': status,
      if (content != null) 'content': content,
      if (savedAtMs != null) 'saved_at_ms': savedAtMs,
      if (rawTranscript != null) 'raw_transcript': rawTranscript,
      if (refinedTranscript != null) 'refined_transcript': refinedTranscript,
      if (refinementStatus != null) 'refinement_status': refinementStatus,
      if (refinerId != null) 'refiner_id': refinerId,
      if (refinerVersion != null) 'refiner_version': refinerVersion,
      if (refinementEditsJson != null)
        'refinement_edits_json': refinementEditsJson,
    });
  }

  TurnRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? conversationId,
    Value<String>? role,
    Value<String>? status,
    Value<String>? content,
    Value<int>? savedAtMs,
    Value<String?>? rawTranscript,
    Value<String?>? refinedTranscript,
    Value<String?>? refinementStatus,
    Value<String?>? refinerId,
    Value<String?>? refinerVersion,
    Value<String?>? refinementEditsJson,
  }) {
    return TurnRowsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      status: status ?? this.status,
      content: content ?? this.content,
      savedAtMs: savedAtMs ?? this.savedAtMs,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      refinedTranscript: refinedTranscript ?? this.refinedTranscript,
      refinementStatus: refinementStatus ?? this.refinementStatus,
      refinerId: refinerId ?? this.refinerId,
      refinerVersion: refinerVersion ?? this.refinerVersion,
      refinementEditsJson: refinementEditsJson ?? this.refinementEditsJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (savedAtMs.present) {
      map['saved_at_ms'] = Variable<int>(savedAtMs.value);
    }
    if (rawTranscript.present) {
      map['raw_transcript'] = Variable<String>(rawTranscript.value);
    }
    if (refinedTranscript.present) {
      map['refined_transcript'] = Variable<String>(refinedTranscript.value);
    }
    if (refinementStatus.present) {
      map['refinement_status'] = Variable<String>(refinementStatus.value);
    }
    if (refinerId.present) {
      map['refiner_id'] = Variable<String>(refinerId.value);
    }
    if (refinerVersion.present) {
      map['refiner_version'] = Variable<String>(refinerVersion.value);
    }
    if (refinementEditsJson.present) {
      map['refinement_edits_json'] = Variable<String>(
        refinementEditsJson.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TurnRowsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('content: $content, ')
          ..write('savedAtMs: $savedAtMs, ')
          ..write('rawTranscript: $rawTranscript, ')
          ..write('refinedTranscript: $refinedTranscript, ')
          ..write('refinementStatus: $refinementStatus, ')
          ..write('refinerId: $refinerId, ')
          ..write('refinerVersion: $refinerVersion, ')
          ..write('refinementEditsJson: $refinementEditsJson')
          ..write(')'))
        .toString();
  }
}

class $RunRowsTable extends RunRows with TableInfo<$RunRowsTable, RunRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RunRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _generationIdMeta = const VerificationMeta(
    'generationId',
  );
  @override
  late final GeneratedColumn<String> generationId = GeneratedColumn<String>(
    'generation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conversationIdMeta = const VerificationMeta(
    'conversationId',
  );
  @override
  late final GeneratedColumn<String> conversationId = GeneratedColumn<String>(
    'conversation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modelIdMeta = const VerificationMeta(
    'modelId',
  );
  @override
  late final GeneratedColumn<String> modelId = GeneratedColumn<String>(
    'model_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMsMeta = const VerificationMeta(
    'startedAtMs',
  );
  @override
  late final GeneratedColumn<int> startedAtMs = GeneratedColumn<int>(
    'started_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMsMeta = const VerificationMeta(
    'endedAtMs',
  );
  @override
  late final GeneratedColumn<int> endedAtMs = GeneratedColumn<int>(
    'ended_at_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _outcomeMeta = const VerificationMeta(
    'outcome',
  );
  @override
  late final GeneratedColumn<String> outcome = GeneratedColumn<String>(
    'outcome',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _partialTextMeta = const VerificationMeta(
    'partialText',
  );
  @override
  late final GeneratedColumn<String> partialText = GeneratedColumn<String>(
    'partial_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant<String>(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    generationId,
    conversationId,
    modelId,
    startedAtMs,
    endedAtMs,
    outcome,
    partialText,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'run_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<RunRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('generation_id')) {
      context.handle(
        _generationIdMeta,
        generationId.isAcceptableOrUnknown(
          data['generation_id']!,
          _generationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_generationIdMeta);
    }
    if (data.containsKey('conversation_id')) {
      context.handle(
        _conversationIdMeta,
        conversationId.isAcceptableOrUnknown(
          data['conversation_id']!,
          _conversationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conversationIdMeta);
    }
    if (data.containsKey('model_id')) {
      context.handle(
        _modelIdMeta,
        modelId.isAcceptableOrUnknown(data['model_id']!, _modelIdMeta),
      );
    } else if (isInserting) {
      context.missing(_modelIdMeta);
    }
    if (data.containsKey('started_at_ms')) {
      context.handle(
        _startedAtMsMeta,
        startedAtMs.isAcceptableOrUnknown(
          data['started_at_ms']!,
          _startedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startedAtMsMeta);
    }
    if (data.containsKey('ended_at_ms')) {
      context.handle(
        _endedAtMsMeta,
        endedAtMs.isAcceptableOrUnknown(data['ended_at_ms']!, _endedAtMsMeta),
      );
    }
    if (data.containsKey('outcome')) {
      context.handle(
        _outcomeMeta,
        outcome.isAcceptableOrUnknown(data['outcome']!, _outcomeMeta),
      );
    }
    if (data.containsKey('partial_text')) {
      context.handle(
        _partialTextMeta,
        partialText.isAcceptableOrUnknown(
          data['partial_text']!,
          _partialTextMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {generationId};
  @override
  RunRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RunRow(
      generationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}generation_id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      modelId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model_id'],
      )!,
      startedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at_ms'],
      )!,
      endedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at_ms'],
      ),
      outcome: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}outcome'],
      ),
      partialText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}partial_text'],
      )!,
    );
  }

  @override
  $RunRowsTable createAlias(String alias) {
    return $RunRowsTable(attachedDatabase, alias);
  }
}

class RunRow extends DataClass implements Insertable<RunRow> {
  /// The generation identifier, which is the run's identity.
  final String generationId;

  /// The conversation the generation belongs to.
  final String conversationId;

  /// What produced the answer.
  final String modelId;

  /// When generation started, in milliseconds since the epoch.
  final int startedAtMs;

  /// When it reached a terminal state; null while it is still running.
  final int? endedAtMs;

  /// [TurnStatus.name]; null while it is still running.
  final String? outcome;

  /// The whole answer as of the last checkpoint, not the last delta.
  final String partialText;
  const RunRow({
    required this.generationId,
    required this.conversationId,
    required this.modelId,
    required this.startedAtMs,
    this.endedAtMs,
    this.outcome,
    required this.partialText,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['generation_id'] = Variable<String>(generationId);
    map['conversation_id'] = Variable<String>(conversationId);
    map['model_id'] = Variable<String>(modelId);
    map['started_at_ms'] = Variable<int>(startedAtMs);
    if (!nullToAbsent || endedAtMs != null) {
      map['ended_at_ms'] = Variable<int>(endedAtMs);
    }
    if (!nullToAbsent || outcome != null) {
      map['outcome'] = Variable<String>(outcome);
    }
    map['partial_text'] = Variable<String>(partialText);
    return map;
  }

  RunRowsCompanion toCompanion(bool nullToAbsent) {
    return RunRowsCompanion(
      generationId: Value(generationId),
      conversationId: Value(conversationId),
      modelId: Value(modelId),
      startedAtMs: Value(startedAtMs),
      endedAtMs: endedAtMs == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAtMs),
      outcome: outcome == null && nullToAbsent
          ? const Value.absent()
          : Value(outcome),
      partialText: Value(partialText),
    );
  }

  factory RunRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RunRow(
      generationId: serializer.fromJson<String>(json['generationId']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      modelId: serializer.fromJson<String>(json['modelId']),
      startedAtMs: serializer.fromJson<int>(json['startedAtMs']),
      endedAtMs: serializer.fromJson<int?>(json['endedAtMs']),
      outcome: serializer.fromJson<String?>(json['outcome']),
      partialText: serializer.fromJson<String>(json['partialText']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'generationId': serializer.toJson<String>(generationId),
      'conversationId': serializer.toJson<String>(conversationId),
      'modelId': serializer.toJson<String>(modelId),
      'startedAtMs': serializer.toJson<int>(startedAtMs),
      'endedAtMs': serializer.toJson<int?>(endedAtMs),
      'outcome': serializer.toJson<String?>(outcome),
      'partialText': serializer.toJson<String>(partialText),
    };
  }

  RunRow copyWith({
    String? generationId,
    String? conversationId,
    String? modelId,
    int? startedAtMs,
    Value<int?> endedAtMs = const Value.absent(),
    Value<String?> outcome = const Value.absent(),
    String? partialText,
  }) => RunRow(
    generationId: generationId ?? this.generationId,
    conversationId: conversationId ?? this.conversationId,
    modelId: modelId ?? this.modelId,
    startedAtMs: startedAtMs ?? this.startedAtMs,
    endedAtMs: endedAtMs.present ? endedAtMs.value : this.endedAtMs,
    outcome: outcome.present ? outcome.value : this.outcome,
    partialText: partialText ?? this.partialText,
  );
  RunRow copyWithCompanion(RunRowsCompanion data) {
    return RunRow(
      generationId: data.generationId.present
          ? data.generationId.value
          : this.generationId,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      modelId: data.modelId.present ? data.modelId.value : this.modelId,
      startedAtMs: data.startedAtMs.present
          ? data.startedAtMs.value
          : this.startedAtMs,
      endedAtMs: data.endedAtMs.present ? data.endedAtMs.value : this.endedAtMs,
      outcome: data.outcome.present ? data.outcome.value : this.outcome,
      partialText: data.partialText.present
          ? data.partialText.value
          : this.partialText,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RunRow(')
          ..write('generationId: $generationId, ')
          ..write('conversationId: $conversationId, ')
          ..write('modelId: $modelId, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('outcome: $outcome, ')
          ..write('partialText: $partialText')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    generationId,
    conversationId,
    modelId,
    startedAtMs,
    endedAtMs,
    outcome,
    partialText,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RunRow &&
          other.generationId == this.generationId &&
          other.conversationId == this.conversationId &&
          other.modelId == this.modelId &&
          other.startedAtMs == this.startedAtMs &&
          other.endedAtMs == this.endedAtMs &&
          other.outcome == this.outcome &&
          other.partialText == this.partialText);
}

class RunRowsCompanion extends UpdateCompanion<RunRow> {
  final Value<String> generationId;
  final Value<String> conversationId;
  final Value<String> modelId;
  final Value<int> startedAtMs;
  final Value<int?> endedAtMs;
  final Value<String?> outcome;
  final Value<String> partialText;
  final Value<int> rowid;
  const RunRowsCompanion({
    this.generationId = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.modelId = const Value.absent(),
    this.startedAtMs = const Value.absent(),
    this.endedAtMs = const Value.absent(),
    this.outcome = const Value.absent(),
    this.partialText = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RunRowsCompanion.insert({
    required String generationId,
    required String conversationId,
    required String modelId,
    required int startedAtMs,
    this.endedAtMs = const Value.absent(),
    this.outcome = const Value.absent(),
    this.partialText = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : generationId = Value(generationId),
       conversationId = Value(conversationId),
       modelId = Value(modelId),
       startedAtMs = Value(startedAtMs);
  static Insertable<RunRow> custom({
    Expression<String>? generationId,
    Expression<String>? conversationId,
    Expression<String>? modelId,
    Expression<int>? startedAtMs,
    Expression<int>? endedAtMs,
    Expression<String>? outcome,
    Expression<String>? partialText,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (generationId != null) 'generation_id': generationId,
      if (conversationId != null) 'conversation_id': conversationId,
      if (modelId != null) 'model_id': modelId,
      if (startedAtMs != null) 'started_at_ms': startedAtMs,
      if (endedAtMs != null) 'ended_at_ms': endedAtMs,
      if (outcome != null) 'outcome': outcome,
      if (partialText != null) 'partial_text': partialText,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RunRowsCompanion copyWith({
    Value<String>? generationId,
    Value<String>? conversationId,
    Value<String>? modelId,
    Value<int>? startedAtMs,
    Value<int?>? endedAtMs,
    Value<String?>? outcome,
    Value<String>? partialText,
    Value<int>? rowid,
  }) {
    return RunRowsCompanion(
      generationId: generationId ?? this.generationId,
      conversationId: conversationId ?? this.conversationId,
      modelId: modelId ?? this.modelId,
      startedAtMs: startedAtMs ?? this.startedAtMs,
      endedAtMs: endedAtMs ?? this.endedAtMs,
      outcome: outcome ?? this.outcome,
      partialText: partialText ?? this.partialText,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (generationId.present) {
      map['generation_id'] = Variable<String>(generationId.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (modelId.present) {
      map['model_id'] = Variable<String>(modelId.value);
    }
    if (startedAtMs.present) {
      map['started_at_ms'] = Variable<int>(startedAtMs.value);
    }
    if (endedAtMs.present) {
      map['ended_at_ms'] = Variable<int>(endedAtMs.value);
    }
    if (outcome.present) {
      map['outcome'] = Variable<String>(outcome.value);
    }
    if (partialText.present) {
      map['partial_text'] = Variable<String>(partialText.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RunRowsCompanion(')
          ..write('generationId: $generationId, ')
          ..write('conversationId: $conversationId, ')
          ..write('modelId: $modelId, ')
          ..write('startedAtMs: $startedAtMs, ')
          ..write('endedAtMs: $endedAtMs, ')
          ..write('outcome: $outcome, ')
          ..write('partialText: $partialText, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ConversationDatabase extends GeneratedDatabase {
  _$ConversationDatabase(QueryExecutor e) : super(e);
  $ConversationDatabaseManager get managers =>
      $ConversationDatabaseManager(this);
  late final $TurnRowsTable turnRows = $TurnRowsTable(this);
  late final $RunRowsTable runRows = $RunRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [turnRows, runRows];
}

typedef $$TurnRowsTableCreateCompanionBuilder =
    TurnRowsCompanion Function({
      Value<int> id,
      required String conversationId,
      required String role,
      required String status,
      required String content,
      required int savedAtMs,
      Value<String?> rawTranscript,
      Value<String?> refinedTranscript,
      Value<String?> refinementStatus,
      Value<String?> refinerId,
      Value<String?> refinerVersion,
      Value<String?> refinementEditsJson,
    });
typedef $$TurnRowsTableUpdateCompanionBuilder =
    TurnRowsCompanion Function({
      Value<int> id,
      Value<String> conversationId,
      Value<String> role,
      Value<String> status,
      Value<String> content,
      Value<int> savedAtMs,
      Value<String?> rawTranscript,
      Value<String?> refinedTranscript,
      Value<String?> refinementStatus,
      Value<String?> refinerId,
      Value<String?> refinerVersion,
      Value<String?> refinementEditsJson,
    });

class $$TurnRowsTableFilterComposer
    extends Composer<_$ConversationDatabase, $TurnRowsTable> {
  $$TurnRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get savedAtMs => $composableBuilder(
    column: $table.savedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refinedTranscript => $composableBuilder(
    column: $table.refinedTranscript,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refinementStatus => $composableBuilder(
    column: $table.refinementStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refinerId => $composableBuilder(
    column: $table.refinerId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refinerVersion => $composableBuilder(
    column: $table.refinerVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refinementEditsJson => $composableBuilder(
    column: $table.refinementEditsJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TurnRowsTableOrderingComposer
    extends Composer<_$ConversationDatabase, $TurnRowsTable> {
  $$TurnRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get savedAtMs => $composableBuilder(
    column: $table.savedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refinedTranscript => $composableBuilder(
    column: $table.refinedTranscript,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refinementStatus => $composableBuilder(
    column: $table.refinementStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refinerId => $composableBuilder(
    column: $table.refinerId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refinerVersion => $composableBuilder(
    column: $table.refinerVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refinementEditsJson => $composableBuilder(
    column: $table.refinementEditsJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TurnRowsTableAnnotationComposer
    extends Composer<_$ConversationDatabase, $TurnRowsTable> {
  $$TurnRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<int> get savedAtMs =>
      $composableBuilder(column: $table.savedAtMs, builder: (column) => column);

  GeneratedColumn<String> get rawTranscript => $composableBuilder(
    column: $table.rawTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refinedTranscript => $composableBuilder(
    column: $table.refinedTranscript,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refinementStatus => $composableBuilder(
    column: $table.refinementStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refinerId =>
      $composableBuilder(column: $table.refinerId, builder: (column) => column);

  GeneratedColumn<String> get refinerVersion => $composableBuilder(
    column: $table.refinerVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get refinementEditsJson => $composableBuilder(
    column: $table.refinementEditsJson,
    builder: (column) => column,
  );
}

class $$TurnRowsTableTableManager
    extends
        RootTableManager<
          _$ConversationDatabase,
          $TurnRowsTable,
          TurnRow,
          $$TurnRowsTableFilterComposer,
          $$TurnRowsTableOrderingComposer,
          $$TurnRowsTableAnnotationComposer,
          $$TurnRowsTableCreateCompanionBuilder,
          $$TurnRowsTableUpdateCompanionBuilder,
          (
            TurnRow,
            BaseReferences<_$ConversationDatabase, $TurnRowsTable, TurnRow>,
          ),
          TurnRow,
          PrefetchHooks Function()
        > {
  $$TurnRowsTableTableManager(_$ConversationDatabase db, $TurnRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TurnRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TurnRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TurnRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<int> savedAtMs = const Value.absent(),
                Value<String?> rawTranscript = const Value.absent(),
                Value<String?> refinedTranscript = const Value.absent(),
                Value<String?> refinementStatus = const Value.absent(),
                Value<String?> refinerId = const Value.absent(),
                Value<String?> refinerVersion = const Value.absent(),
                Value<String?> refinementEditsJson = const Value.absent(),
              }) => TurnRowsCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                status: status,
                content: content,
                savedAtMs: savedAtMs,
                rawTranscript: rawTranscript,
                refinedTranscript: refinedTranscript,
                refinementStatus: refinementStatus,
                refinerId: refinerId,
                refinerVersion: refinerVersion,
                refinementEditsJson: refinementEditsJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String conversationId,
                required String role,
                required String status,
                required String content,
                required int savedAtMs,
                Value<String?> rawTranscript = const Value.absent(),
                Value<String?> refinedTranscript = const Value.absent(),
                Value<String?> refinementStatus = const Value.absent(),
                Value<String?> refinerId = const Value.absent(),
                Value<String?> refinerVersion = const Value.absent(),
                Value<String?> refinementEditsJson = const Value.absent(),
              }) => TurnRowsCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                status: status,
                content: content,
                savedAtMs: savedAtMs,
                rawTranscript: rawTranscript,
                refinedTranscript: refinedTranscript,
                refinementStatus: refinementStatus,
                refinerId: refinerId,
                refinerVersion: refinerVersion,
                refinementEditsJson: refinementEditsJson,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TurnRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ConversationDatabase,
      $TurnRowsTable,
      TurnRow,
      $$TurnRowsTableFilterComposer,
      $$TurnRowsTableOrderingComposer,
      $$TurnRowsTableAnnotationComposer,
      $$TurnRowsTableCreateCompanionBuilder,
      $$TurnRowsTableUpdateCompanionBuilder,
      (
        TurnRow,
        BaseReferences<_$ConversationDatabase, $TurnRowsTable, TurnRow>,
      ),
      TurnRow,
      PrefetchHooks Function()
    >;
typedef $$RunRowsTableCreateCompanionBuilder =
    RunRowsCompanion Function({
      required String generationId,
      required String conversationId,
      required String modelId,
      required int startedAtMs,
      Value<int?> endedAtMs,
      Value<String?> outcome,
      Value<String> partialText,
      Value<int> rowid,
    });
typedef $$RunRowsTableUpdateCompanionBuilder =
    RunRowsCompanion Function({
      Value<String> generationId,
      Value<String> conversationId,
      Value<String> modelId,
      Value<int> startedAtMs,
      Value<int?> endedAtMs,
      Value<String?> outcome,
      Value<String> partialText,
      Value<int> rowid,
    });

class $$RunRowsTableFilterComposer
    extends Composer<_$ConversationDatabase, $RunRowsTable> {
  $$RunRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get partialText => $composableBuilder(
    column: $table.partialText,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RunRowsTableOrderingComposer
    extends Composer<_$ConversationDatabase, $RunRowsTable> {
  $$RunRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get modelId => $composableBuilder(
    column: $table.modelId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAtMs => $composableBuilder(
    column: $table.endedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get outcome => $composableBuilder(
    column: $table.outcome,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get partialText => $composableBuilder(
    column: $table.partialText,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RunRowsTableAnnotationComposer
    extends Composer<_$ConversationDatabase, $RunRowsTable> {
  $$RunRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get generationId => $composableBuilder(
    column: $table.generationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get modelId =>
      $composableBuilder(column: $table.modelId, builder: (column) => column);

  GeneratedColumn<int> get startedAtMs => $composableBuilder(
    column: $table.startedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get endedAtMs =>
      $composableBuilder(column: $table.endedAtMs, builder: (column) => column);

  GeneratedColumn<String> get outcome =>
      $composableBuilder(column: $table.outcome, builder: (column) => column);

  GeneratedColumn<String> get partialText => $composableBuilder(
    column: $table.partialText,
    builder: (column) => column,
  );
}

class $$RunRowsTableTableManager
    extends
        RootTableManager<
          _$ConversationDatabase,
          $RunRowsTable,
          RunRow,
          $$RunRowsTableFilterComposer,
          $$RunRowsTableOrderingComposer,
          $$RunRowsTableAnnotationComposer,
          $$RunRowsTableCreateCompanionBuilder,
          $$RunRowsTableUpdateCompanionBuilder,
          (
            RunRow,
            BaseReferences<_$ConversationDatabase, $RunRowsTable, RunRow>,
          ),
          RunRow,
          PrefetchHooks Function()
        > {
  $$RunRowsTableTableManager(_$ConversationDatabase db, $RunRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RunRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RunRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RunRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> generationId = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<String> modelId = const Value.absent(),
                Value<int> startedAtMs = const Value.absent(),
                Value<int?> endedAtMs = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<String> partialText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RunRowsCompanion(
                generationId: generationId,
                conversationId: conversationId,
                modelId: modelId,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                outcome: outcome,
                partialText: partialText,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String generationId,
                required String conversationId,
                required String modelId,
                required int startedAtMs,
                Value<int?> endedAtMs = const Value.absent(),
                Value<String?> outcome = const Value.absent(),
                Value<String> partialText = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RunRowsCompanion.insert(
                generationId: generationId,
                conversationId: conversationId,
                modelId: modelId,
                startedAtMs: startedAtMs,
                endedAtMs: endedAtMs,
                outcome: outcome,
                partialText: partialText,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RunRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ConversationDatabase,
      $RunRowsTable,
      RunRow,
      $$RunRowsTableFilterComposer,
      $$RunRowsTableOrderingComposer,
      $$RunRowsTableAnnotationComposer,
      $$RunRowsTableCreateCompanionBuilder,
      $$RunRowsTableUpdateCompanionBuilder,
      (RunRow, BaseReferences<_$ConversationDatabase, $RunRowsTable, RunRow>),
      RunRow,
      PrefetchHooks Function()
    >;

class $ConversationDatabaseManager {
  final _$ConversationDatabase _db;
  $ConversationDatabaseManager(this._db);
  $$TurnRowsTableTableManager get turnRows =>
      $$TurnRowsTableTableManager(_db, _db.turnRows);
  $$RunRowsTableTableManager get runRows =>
      $$RunRowsTableTableManager(_db, _db.runRows);
}
