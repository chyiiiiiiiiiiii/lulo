// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'storage_benchmark.dart';

// ignore_for_file: type=lint
class $BenchmarkConversationsTable extends BenchmarkConversations
    with TableInfo<$BenchmarkConversationsTable, BenchmarkConversation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BenchmarkConversationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMsMeta = const VerificationMeta(
    'updatedAtMs',
  );
  @override
  late final GeneratedColumn<int> updatedAtMs = GeneratedColumn<int>(
    'updated_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _turnCountMeta = const VerificationMeta(
    'turnCount',
  );
  @override
  late final GeneratedColumn<int> turnCount = GeneratedColumn<int>(
    'turn_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(0),
  );
  static const VerificationMeta _lastTurnSequenceMeta = const VerificationMeta(
    'lastTurnSequence',
  );
  @override
  late final GeneratedColumn<int> lastTurnSequence = GeneratedColumn<int>(
    'last_turn_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant<int>(-1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAtMs,
    updatedAtMs,
    title,
    turnCount,
    lastTurnSequence,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'conversations';
  @override
  VerificationContext validateIntegrity(
    Insertable<BenchmarkConversation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    if (data.containsKey('updated_at_ms')) {
      context.handle(
        _updatedAtMsMeta,
        updatedAtMs.isAcceptableOrUnknown(
          data['updated_at_ms']!,
          _updatedAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMsMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('turn_count')) {
      context.handle(
        _turnCountMeta,
        turnCount.isAcceptableOrUnknown(data['turn_count']!, _turnCountMeta),
      );
    }
    if (data.containsKey('last_turn_sequence')) {
      context.handle(
        _lastTurnSequenceMeta,
        lastTurnSequence.isAcceptableOrUnknown(
          data['last_turn_sequence']!,
          _lastTurnSequenceMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BenchmarkConversation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BenchmarkConversation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
      updatedAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at_ms'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      turnCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}turn_count'],
      )!,
      lastTurnSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_turn_sequence'],
      )!,
    );
  }

  @override
  $BenchmarkConversationsTable createAlias(String alias) {
    return $BenchmarkConversationsTable(attachedDatabase, alias);
  }
}

class BenchmarkConversation extends DataClass
    implements Insertable<BenchmarkConversation> {
  final String id;
  final int createdAtMs;
  final int updatedAtMs;
  final String title;
  final int turnCount;
  final int lastTurnSequence;
  const BenchmarkConversation({
    required this.id,
    required this.createdAtMs,
    required this.updatedAtMs,
    required this.title,
    required this.turnCount,
    required this.lastTurnSequence,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    map['updated_at_ms'] = Variable<int>(updatedAtMs);
    map['title'] = Variable<String>(title);
    map['turn_count'] = Variable<int>(turnCount);
    map['last_turn_sequence'] = Variable<int>(lastTurnSequence);
    return map;
  }

  BenchmarkConversationsCompanion toCompanion(bool nullToAbsent) {
    return BenchmarkConversationsCompanion(
      id: Value(id),
      createdAtMs: Value(createdAtMs),
      updatedAtMs: Value(updatedAtMs),
      title: Value(title),
      turnCount: Value(turnCount),
      lastTurnSequence: Value(lastTurnSequence),
    );
  }

  factory BenchmarkConversation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BenchmarkConversation(
      id: serializer.fromJson<String>(json['id']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
      updatedAtMs: serializer.fromJson<int>(json['updatedAtMs']),
      title: serializer.fromJson<String>(json['title']),
      turnCount: serializer.fromJson<int>(json['turnCount']),
      lastTurnSequence: serializer.fromJson<int>(json['lastTurnSequence']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
      'updatedAtMs': serializer.toJson<int>(updatedAtMs),
      'title': serializer.toJson<String>(title),
      'turnCount': serializer.toJson<int>(turnCount),
      'lastTurnSequence': serializer.toJson<int>(lastTurnSequence),
    };
  }

  BenchmarkConversation copyWith({
    String? id,
    int? createdAtMs,
    int? updatedAtMs,
    String? title,
    int? turnCount,
    int? lastTurnSequence,
  }) => BenchmarkConversation(
    id: id ?? this.id,
    createdAtMs: createdAtMs ?? this.createdAtMs,
    updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    title: title ?? this.title,
    turnCount: turnCount ?? this.turnCount,
    lastTurnSequence: lastTurnSequence ?? this.lastTurnSequence,
  );
  BenchmarkConversation copyWithCompanion(
    BenchmarkConversationsCompanion data,
  ) {
    return BenchmarkConversation(
      id: data.id.present ? data.id.value : this.id,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
      updatedAtMs: data.updatedAtMs.present
          ? data.updatedAtMs.value
          : this.updatedAtMs,
      title: data.title.present ? data.title.value : this.title,
      turnCount: data.turnCount.present ? data.turnCount.value : this.turnCount,
      lastTurnSequence: data.lastTurnSequence.present
          ? data.lastTurnSequence.value
          : this.lastTurnSequence,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkConversation(')
          ..write('id: $id, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('title: $title, ')
          ..write('turnCount: $turnCount, ')
          ..write('lastTurnSequence: $lastTurnSequence')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAtMs,
    updatedAtMs,
    title,
    turnCount,
    lastTurnSequence,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BenchmarkConversation &&
          other.id == this.id &&
          other.createdAtMs == this.createdAtMs &&
          other.updatedAtMs == this.updatedAtMs &&
          other.title == this.title &&
          other.turnCount == this.turnCount &&
          other.lastTurnSequence == this.lastTurnSequence);
}

class BenchmarkConversationsCompanion
    extends UpdateCompanion<BenchmarkConversation> {
  final Value<String> id;
  final Value<int> createdAtMs;
  final Value<int> updatedAtMs;
  final Value<String> title;
  final Value<int> turnCount;
  final Value<int> lastTurnSequence;
  final Value<int> rowid;
  const BenchmarkConversationsCompanion({
    this.id = const Value.absent(),
    this.createdAtMs = const Value.absent(),
    this.updatedAtMs = const Value.absent(),
    this.title = const Value.absent(),
    this.turnCount = const Value.absent(),
    this.lastTurnSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BenchmarkConversationsCompanion.insert({
    required String id,
    required int createdAtMs,
    required int updatedAtMs,
    required String title,
    this.turnCount = const Value.absent(),
    this.lastTurnSequence = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAtMs = Value(createdAtMs),
       updatedAtMs = Value(updatedAtMs),
       title = Value(title);
  static Insertable<BenchmarkConversation> custom({
    Expression<String>? id,
    Expression<int>? createdAtMs,
    Expression<int>? updatedAtMs,
    Expression<String>? title,
    Expression<int>? turnCount,
    Expression<int>? lastTurnSequence,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
      if (updatedAtMs != null) 'updated_at_ms': updatedAtMs,
      if (title != null) 'title': title,
      if (turnCount != null) 'turn_count': turnCount,
      if (lastTurnSequence != null) 'last_turn_sequence': lastTurnSequence,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BenchmarkConversationsCompanion copyWith({
    Value<String>? id,
    Value<int>? createdAtMs,
    Value<int>? updatedAtMs,
    Value<String>? title,
    Value<int>? turnCount,
    Value<int>? lastTurnSequence,
    Value<int>? rowid,
  }) {
    return BenchmarkConversationsCompanion(
      id: id ?? this.id,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      title: title ?? this.title,
      turnCount: turnCount ?? this.turnCount,
      lastTurnSequence: lastTurnSequence ?? this.lastTurnSequence,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    if (updatedAtMs.present) {
      map['updated_at_ms'] = Variable<int>(updatedAtMs.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (turnCount.present) {
      map['turn_count'] = Variable<int>(turnCount.value);
    }
    if (lastTurnSequence.present) {
      map['last_turn_sequence'] = Variable<int>(lastTurnSequence.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkConversationsCompanion(')
          ..write('id: $id, ')
          ..write('createdAtMs: $createdAtMs, ')
          ..write('updatedAtMs: $updatedAtMs, ')
          ..write('title: $title, ')
          ..write('turnCount: $turnCount, ')
          ..write('lastTurnSequence: $lastTurnSequence, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BenchmarkTurnsTable extends BenchmarkTurns
    with TableInfo<$BenchmarkTurnsTable, BenchmarkTurn> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BenchmarkTurnsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<int> role = GeneratedColumn<int>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<int> status = GeneratedColumn<int>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _textValueMeta = const VerificationMeta(
    'textValue',
  );
  @override
  late final GeneratedColumn<String> textValue = GeneratedColumn<String>(
    'text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMsMeta = const VerificationMeta(
    'createdAtMs',
  );
  @override
  late final GeneratedColumn<int> createdAtMs = GeneratedColumn<int>(
    'created_at_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    conversationId,
    sequence,
    role,
    status,
    textValue,
    createdAtMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'turns';
  @override
  VerificationContext validateIntegrity(
    Insertable<BenchmarkTurn> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
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
    if (data.containsKey('text')) {
      context.handle(
        _textValueMeta,
        textValue.isAcceptableOrUnknown(data['text']!, _textValueMeta),
      );
    } else if (isInserting) {
      context.missing(_textValueMeta);
    }
    if (data.containsKey('created_at_ms')) {
      context.handle(
        _createdAtMsMeta,
        createdAtMs.isAcceptableOrUnknown(
          data['created_at_ms']!,
          _createdAtMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtMsMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conversationId, sequence};
  @override
  BenchmarkTurn map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BenchmarkTurn(
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}status'],
      )!,
      textValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text'],
      )!,
      createdAtMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at_ms'],
      )!,
    );
  }

  @override
  $BenchmarkTurnsTable createAlias(String alias) {
    return $BenchmarkTurnsTable(attachedDatabase, alias);
  }

  @override
  bool get withoutRowId => true;
}

class BenchmarkTurn extends DataClass implements Insertable<BenchmarkTurn> {
  final String conversationId;
  final int sequence;
  final int role;
  final int status;
  final String textValue;
  final int createdAtMs;
  const BenchmarkTurn({
    required this.conversationId,
    required this.sequence,
    required this.role,
    required this.status,
    required this.textValue,
    required this.createdAtMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conversation_id'] = Variable<String>(conversationId);
    map['sequence'] = Variable<int>(sequence);
    map['role'] = Variable<int>(role);
    map['status'] = Variable<int>(status);
    map['text'] = Variable<String>(textValue);
    map['created_at_ms'] = Variable<int>(createdAtMs);
    return map;
  }

  BenchmarkTurnsCompanion toCompanion(bool nullToAbsent) {
    return BenchmarkTurnsCompanion(
      conversationId: Value(conversationId),
      sequence: Value(sequence),
      role: Value(role),
      status: Value(status),
      textValue: Value(textValue),
      createdAtMs: Value(createdAtMs),
    );
  }

  factory BenchmarkTurn.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BenchmarkTurn(
      conversationId: serializer.fromJson<String>(json['conversationId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      role: serializer.fromJson<int>(json['role']),
      status: serializer.fromJson<int>(json['status']),
      textValue: serializer.fromJson<String>(json['textValue']),
      createdAtMs: serializer.fromJson<int>(json['createdAtMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conversationId': serializer.toJson<String>(conversationId),
      'sequence': serializer.toJson<int>(sequence),
      'role': serializer.toJson<int>(role),
      'status': serializer.toJson<int>(status),
      'textValue': serializer.toJson<String>(textValue),
      'createdAtMs': serializer.toJson<int>(createdAtMs),
    };
  }

  BenchmarkTurn copyWith({
    String? conversationId,
    int? sequence,
    int? role,
    int? status,
    String? textValue,
    int? createdAtMs,
  }) => BenchmarkTurn(
    conversationId: conversationId ?? this.conversationId,
    sequence: sequence ?? this.sequence,
    role: role ?? this.role,
    status: status ?? this.status,
    textValue: textValue ?? this.textValue,
    createdAtMs: createdAtMs ?? this.createdAtMs,
  );
  BenchmarkTurn copyWithCompanion(BenchmarkTurnsCompanion data) {
    return BenchmarkTurn(
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      role: data.role.present ? data.role.value : this.role,
      status: data.status.present ? data.status.value : this.status,
      textValue: data.textValue.present ? data.textValue.value : this.textValue,
      createdAtMs: data.createdAtMs.present
          ? data.createdAtMs.value
          : this.createdAtMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkTurn(')
          ..write('conversationId: $conversationId, ')
          ..write('sequence: $sequence, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('textValue: $textValue, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conversationId,
    sequence,
    role,
    status,
    textValue,
    createdAtMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BenchmarkTurn &&
          other.conversationId == this.conversationId &&
          other.sequence == this.sequence &&
          other.role == this.role &&
          other.status == this.status &&
          other.textValue == this.textValue &&
          other.createdAtMs == this.createdAtMs);
}

class BenchmarkTurnsCompanion extends UpdateCompanion<BenchmarkTurn> {
  final Value<String> conversationId;
  final Value<int> sequence;
  final Value<int> role;
  final Value<int> status;
  final Value<String> textValue;
  final Value<int> createdAtMs;
  const BenchmarkTurnsCompanion({
    this.conversationId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.role = const Value.absent(),
    this.status = const Value.absent(),
    this.textValue = const Value.absent(),
    this.createdAtMs = const Value.absent(),
  });
  BenchmarkTurnsCompanion.insert({
    required String conversationId,
    required int sequence,
    required int role,
    required int status,
    required String textValue,
    required int createdAtMs,
  }) : conversationId = Value(conversationId),
       sequence = Value(sequence),
       role = Value(role),
       status = Value(status),
       textValue = Value(textValue),
       createdAtMs = Value(createdAtMs);
  static Insertable<BenchmarkTurn> custom({
    Expression<String>? conversationId,
    Expression<int>? sequence,
    Expression<int>? role,
    Expression<int>? status,
    Expression<String>? textValue,
    Expression<int>? createdAtMs,
  }) {
    return RawValuesInsertable({
      if (conversationId != null) 'conversation_id': conversationId,
      if (sequence != null) 'sequence': sequence,
      if (role != null) 'role': role,
      if (status != null) 'status': status,
      if (textValue != null) 'text': textValue,
      if (createdAtMs != null) 'created_at_ms': createdAtMs,
    });
  }

  BenchmarkTurnsCompanion copyWith({
    Value<String>? conversationId,
    Value<int>? sequence,
    Value<int>? role,
    Value<int>? status,
    Value<String>? textValue,
    Value<int>? createdAtMs,
  }) {
    return BenchmarkTurnsCompanion(
      conversationId: conversationId ?? this.conversationId,
      sequence: sequence ?? this.sequence,
      role: role ?? this.role,
      status: status ?? this.status,
      textValue: textValue ?? this.textValue,
      createdAtMs: createdAtMs ?? this.createdAtMs,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (role.present) {
      map['role'] = Variable<int>(role.value);
    }
    if (status.present) {
      map['status'] = Variable<int>(status.value);
    }
    if (textValue.present) {
      map['text'] = Variable<String>(textValue.value);
    }
    if (createdAtMs.present) {
      map['created_at_ms'] = Variable<int>(createdAtMs.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkTurnsCompanion(')
          ..write('conversationId: $conversationId, ')
          ..write('sequence: $sequence, ')
          ..write('role: $role, ')
          ..write('status: $status, ')
          ..write('textValue: $textValue, ')
          ..write('createdAtMs: $createdAtMs')
          ..write(')'))
        .toString();
  }
}

class $BenchmarkGenerationsTable extends BenchmarkGenerations
    with TableInfo<$BenchmarkGenerationsTable, BenchmarkGeneration> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BenchmarkGenerationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
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
  static const VerificationMeta _assistantTurnSequenceMeta =
      const VerificationMeta('assistantTurnSequence');
  @override
  late final GeneratedColumn<int> assistantTurnSequence = GeneratedColumn<int>(
    'assistant_turn_sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestPromptMeta = const VerificationMeta(
    'requestPrompt',
  );
  @override
  late final GeneratedColumn<String> requestPrompt = GeneratedColumn<String>(
    'request_prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    assistantTurnSequence,
    requestPrompt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'generations';
  @override
  VerificationContext validateIntegrity(
    Insertable<BenchmarkGeneration> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
    if (data.containsKey('assistant_turn_sequence')) {
      context.handle(
        _assistantTurnSequenceMeta,
        assistantTurnSequence.isAcceptableOrUnknown(
          data['assistant_turn_sequence']!,
          _assistantTurnSequenceMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_assistantTurnSequenceMeta);
    }
    if (data.containsKey('request_prompt')) {
      context.handle(
        _requestPromptMeta,
        requestPrompt.isAcceptableOrUnknown(
          data['request_prompt']!,
          _requestPromptMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_requestPromptMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BenchmarkGeneration map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BenchmarkGeneration(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      conversationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conversation_id'],
      )!,
      assistantTurnSequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}assistant_turn_sequence'],
      )!,
      requestPrompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_prompt'],
      )!,
    );
  }

  @override
  $BenchmarkGenerationsTable createAlias(String alias) {
    return $BenchmarkGenerationsTable(attachedDatabase, alias);
  }
}

class BenchmarkGeneration extends DataClass
    implements Insertable<BenchmarkGeneration> {
  final String id;
  final String conversationId;
  final int assistantTurnSequence;
  final String requestPrompt;
  const BenchmarkGeneration({
    required this.id,
    required this.conversationId,
    required this.assistantTurnSequence,
    required this.requestPrompt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['conversation_id'] = Variable<String>(conversationId);
    map['assistant_turn_sequence'] = Variable<int>(assistantTurnSequence);
    map['request_prompt'] = Variable<String>(requestPrompt);
    return map;
  }

  BenchmarkGenerationsCompanion toCompanion(bool nullToAbsent) {
    return BenchmarkGenerationsCompanion(
      id: Value(id),
      conversationId: Value(conversationId),
      assistantTurnSequence: Value(assistantTurnSequence),
      requestPrompt: Value(requestPrompt),
    );
  }

  factory BenchmarkGeneration.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BenchmarkGeneration(
      id: serializer.fromJson<String>(json['id']),
      conversationId: serializer.fromJson<String>(json['conversationId']),
      assistantTurnSequence: serializer.fromJson<int>(
        json['assistantTurnSequence'],
      ),
      requestPrompt: serializer.fromJson<String>(json['requestPrompt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'conversationId': serializer.toJson<String>(conversationId),
      'assistantTurnSequence': serializer.toJson<int>(assistantTurnSequence),
      'requestPrompt': serializer.toJson<String>(requestPrompt),
    };
  }

  BenchmarkGeneration copyWith({
    String? id,
    String? conversationId,
    int? assistantTurnSequence,
    String? requestPrompt,
  }) => BenchmarkGeneration(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    assistantTurnSequence: assistantTurnSequence ?? this.assistantTurnSequence,
    requestPrompt: requestPrompt ?? this.requestPrompt,
  );
  BenchmarkGeneration copyWithCompanion(BenchmarkGenerationsCompanion data) {
    return BenchmarkGeneration(
      id: data.id.present ? data.id.value : this.id,
      conversationId: data.conversationId.present
          ? data.conversationId.value
          : this.conversationId,
      assistantTurnSequence: data.assistantTurnSequence.present
          ? data.assistantTurnSequence.value
          : this.assistantTurnSequence,
      requestPrompt: data.requestPrompt.present
          ? data.requestPrompt.value
          : this.requestPrompt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkGeneration(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('assistantTurnSequence: $assistantTurnSequence, ')
          ..write('requestPrompt: $requestPrompt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, assistantTurnSequence, requestPrompt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BenchmarkGeneration &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.assistantTurnSequence == this.assistantTurnSequence &&
          other.requestPrompt == this.requestPrompt);
}

class BenchmarkGenerationsCompanion
    extends UpdateCompanion<BenchmarkGeneration> {
  final Value<String> id;
  final Value<String> conversationId;
  final Value<int> assistantTurnSequence;
  final Value<String> requestPrompt;
  final Value<int> rowid;
  const BenchmarkGenerationsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.assistantTurnSequence = const Value.absent(),
    this.requestPrompt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BenchmarkGenerationsCompanion.insert({
    required String id,
    required String conversationId,
    required int assistantTurnSequence,
    required String requestPrompt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       conversationId = Value(conversationId),
       assistantTurnSequence = Value(assistantTurnSequence),
       requestPrompt = Value(requestPrompt);
  static Insertable<BenchmarkGeneration> custom({
    Expression<String>? id,
    Expression<String>? conversationId,
    Expression<int>? assistantTurnSequence,
    Expression<String>? requestPrompt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (assistantTurnSequence != null)
        'assistant_turn_sequence': assistantTurnSequence,
      if (requestPrompt != null) 'request_prompt': requestPrompt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BenchmarkGenerationsCompanion copyWith({
    Value<String>? id,
    Value<String>? conversationId,
    Value<int>? assistantTurnSequence,
    Value<String>? requestPrompt,
    Value<int>? rowid,
  }) {
    return BenchmarkGenerationsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      assistantTurnSequence:
          assistantTurnSequence ?? this.assistantTurnSequence,
      requestPrompt: requestPrompt ?? this.requestPrompt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (conversationId.present) {
      map['conversation_id'] = Variable<String>(conversationId.value);
    }
    if (assistantTurnSequence.present) {
      map['assistant_turn_sequence'] = Variable<int>(
        assistantTurnSequence.value,
      );
    }
    if (requestPrompt.present) {
      map['request_prompt'] = Variable<String>(requestPrompt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BenchmarkGenerationsCompanion(')
          ..write('id: $id, ')
          ..write('conversationId: $conversationId, ')
          ..write('assistantTurnSequence: $assistantTurnSequence, ')
          ..write('requestPrompt: $requestPrompt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$_BenchmarkDatabase extends GeneratedDatabase {
  _$_BenchmarkDatabase(QueryExecutor e) : super(e);
  $_BenchmarkDatabaseManager get managers => $_BenchmarkDatabaseManager(this);
  late final $BenchmarkConversationsTable benchmarkConversations =
      $BenchmarkConversationsTable(this);
  late final $BenchmarkTurnsTable benchmarkTurns = $BenchmarkTurnsTable(this);
  late final $BenchmarkGenerationsTable benchmarkGenerations =
      $BenchmarkGenerationsTable(this);
  late final Index conversationsByUpdated = Index(
    'conversations_by_updated',
    'CREATE INDEX conversations_by_updated ON conversations (updated_at_ms DESC, id DESC)',
  );
  late final Index generationsByConversationTurn = Index(
    'generations_by_conversation_turn',
    'CREATE INDEX generations_by_conversation_turn ON generations (conversation_id, assistant_turn_sequence)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    benchmarkConversations,
    benchmarkTurns,
    benchmarkGenerations,
    conversationsByUpdated,
    generationsByConversationTurn,
  ];
}

typedef $$BenchmarkConversationsTableCreateCompanionBuilder =
    BenchmarkConversationsCompanion Function({
      required String id,
      required int createdAtMs,
      required int updatedAtMs,
      required String title,
      Value<int> turnCount,
      Value<int> lastTurnSequence,
      Value<int> rowid,
    });
typedef $$BenchmarkConversationsTableUpdateCompanionBuilder =
    BenchmarkConversationsCompanion Function({
      Value<String> id,
      Value<int> createdAtMs,
      Value<int> updatedAtMs,
      Value<String> title,
      Value<int> turnCount,
      Value<int> lastTurnSequence,
      Value<int> rowid,
    });

class $$BenchmarkConversationsTableFilterComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkConversationsTable> {
  $$BenchmarkConversationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get turnCount => $composableBuilder(
    column: $table.turnCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastTurnSequence => $composableBuilder(
    column: $table.lastTurnSequence,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BenchmarkConversationsTableOrderingComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkConversationsTable> {
  $$BenchmarkConversationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get turnCount => $composableBuilder(
    column: $table.turnCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastTurnSequence => $composableBuilder(
    column: $table.lastTurnSequence,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BenchmarkConversationsTableAnnotationComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkConversationsTable> {
  $$BenchmarkConversationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAtMs => $composableBuilder(
    column: $table.updatedAtMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get turnCount =>
      $composableBuilder(column: $table.turnCount, builder: (column) => column);

  GeneratedColumn<int> get lastTurnSequence => $composableBuilder(
    column: $table.lastTurnSequence,
    builder: (column) => column,
  );
}

class $$BenchmarkConversationsTableTableManager
    extends
        RootTableManager<
          _$_BenchmarkDatabase,
          $BenchmarkConversationsTable,
          BenchmarkConversation,
          $$BenchmarkConversationsTableFilterComposer,
          $$BenchmarkConversationsTableOrderingComposer,
          $$BenchmarkConversationsTableAnnotationComposer,
          $$BenchmarkConversationsTableCreateCompanionBuilder,
          $$BenchmarkConversationsTableUpdateCompanionBuilder,
          (
            BenchmarkConversation,
            BaseReferences<
              _$_BenchmarkDatabase,
              $BenchmarkConversationsTable,
              BenchmarkConversation
            >,
          ),
          BenchmarkConversation,
          PrefetchHooks Function()
        > {
  $$BenchmarkConversationsTableTableManager(
    _$_BenchmarkDatabase db,
    $BenchmarkConversationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BenchmarkConversationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$BenchmarkConversationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BenchmarkConversationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
                Value<int> updatedAtMs = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> turnCount = const Value.absent(),
                Value<int> lastTurnSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BenchmarkConversationsCompanion(
                id: id,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                title: title,
                turnCount: turnCount,
                lastTurnSequence: lastTurnSequence,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int createdAtMs,
                required int updatedAtMs,
                required String title,
                Value<int> turnCount = const Value.absent(),
                Value<int> lastTurnSequence = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BenchmarkConversationsCompanion.insert(
                id: id,
                createdAtMs: createdAtMs,
                updatedAtMs: updatedAtMs,
                title: title,
                turnCount: turnCount,
                lastTurnSequence: lastTurnSequence,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BenchmarkConversationsTableProcessedTableManager =
    ProcessedTableManager<
      _$_BenchmarkDatabase,
      $BenchmarkConversationsTable,
      BenchmarkConversation,
      $$BenchmarkConversationsTableFilterComposer,
      $$BenchmarkConversationsTableOrderingComposer,
      $$BenchmarkConversationsTableAnnotationComposer,
      $$BenchmarkConversationsTableCreateCompanionBuilder,
      $$BenchmarkConversationsTableUpdateCompanionBuilder,
      (
        BenchmarkConversation,
        BaseReferences<
          _$_BenchmarkDatabase,
          $BenchmarkConversationsTable,
          BenchmarkConversation
        >,
      ),
      BenchmarkConversation,
      PrefetchHooks Function()
    >;
typedef $$BenchmarkTurnsTableCreateCompanionBuilder =
    BenchmarkTurnsCompanion Function({
      required String conversationId,
      required int sequence,
      required int role,
      required int status,
      required String textValue,
      required int createdAtMs,
    });
typedef $$BenchmarkTurnsTableUpdateCompanionBuilder =
    BenchmarkTurnsCompanion Function({
      Value<String> conversationId,
      Value<int> sequence,
      Value<int> role,
      Value<int> status,
      Value<String> textValue,
      Value<int> createdAtMs,
    });

class $$BenchmarkTurnsTableFilterComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkTurnsTable> {
  $$BenchmarkTurnsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BenchmarkTurnsTableOrderingComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkTurnsTable> {
  $$BenchmarkTurnsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BenchmarkTurnsTableAnnotationComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkTurnsTable> {
  $$BenchmarkTurnsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<int> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);

  GeneratedColumn<int> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get textValue =>
      $composableBuilder(column: $table.textValue, builder: (column) => column);

  GeneratedColumn<int> get createdAtMs => $composableBuilder(
    column: $table.createdAtMs,
    builder: (column) => column,
  );
}

class $$BenchmarkTurnsTableTableManager
    extends
        RootTableManager<
          _$_BenchmarkDatabase,
          $BenchmarkTurnsTable,
          BenchmarkTurn,
          $$BenchmarkTurnsTableFilterComposer,
          $$BenchmarkTurnsTableOrderingComposer,
          $$BenchmarkTurnsTableAnnotationComposer,
          $$BenchmarkTurnsTableCreateCompanionBuilder,
          $$BenchmarkTurnsTableUpdateCompanionBuilder,
          (
            BenchmarkTurn,
            BaseReferences<
              _$_BenchmarkDatabase,
              $BenchmarkTurnsTable,
              BenchmarkTurn
            >,
          ),
          BenchmarkTurn,
          PrefetchHooks Function()
        > {
  $$BenchmarkTurnsTableTableManager(
    _$_BenchmarkDatabase db,
    $BenchmarkTurnsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BenchmarkTurnsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BenchmarkTurnsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BenchmarkTurnsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> conversationId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<int> role = const Value.absent(),
                Value<int> status = const Value.absent(),
                Value<String> textValue = const Value.absent(),
                Value<int> createdAtMs = const Value.absent(),
              }) => BenchmarkTurnsCompanion(
                conversationId: conversationId,
                sequence: sequence,
                role: role,
                status: status,
                textValue: textValue,
                createdAtMs: createdAtMs,
              ),
          createCompanionCallback:
              ({
                required String conversationId,
                required int sequence,
                required int role,
                required int status,
                required String textValue,
                required int createdAtMs,
              }) => BenchmarkTurnsCompanion.insert(
                conversationId: conversationId,
                sequence: sequence,
                role: role,
                status: status,
                textValue: textValue,
                createdAtMs: createdAtMs,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BenchmarkTurnsTableProcessedTableManager =
    ProcessedTableManager<
      _$_BenchmarkDatabase,
      $BenchmarkTurnsTable,
      BenchmarkTurn,
      $$BenchmarkTurnsTableFilterComposer,
      $$BenchmarkTurnsTableOrderingComposer,
      $$BenchmarkTurnsTableAnnotationComposer,
      $$BenchmarkTurnsTableCreateCompanionBuilder,
      $$BenchmarkTurnsTableUpdateCompanionBuilder,
      (
        BenchmarkTurn,
        BaseReferences<
          _$_BenchmarkDatabase,
          $BenchmarkTurnsTable,
          BenchmarkTurn
        >,
      ),
      BenchmarkTurn,
      PrefetchHooks Function()
    >;
typedef $$BenchmarkGenerationsTableCreateCompanionBuilder =
    BenchmarkGenerationsCompanion Function({
      required String id,
      required String conversationId,
      required int assistantTurnSequence,
      required String requestPrompt,
      Value<int> rowid,
    });
typedef $$BenchmarkGenerationsTableUpdateCompanionBuilder =
    BenchmarkGenerationsCompanion Function({
      Value<String> id,
      Value<String> conversationId,
      Value<int> assistantTurnSequence,
      Value<String> requestPrompt,
      Value<int> rowid,
    });

class $$BenchmarkGenerationsTableFilterComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkGenerationsTable> {
  $$BenchmarkGenerationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get assistantTurnSequence => $composableBuilder(
    column: $table.assistantTurnSequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestPrompt => $composableBuilder(
    column: $table.requestPrompt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BenchmarkGenerationsTableOrderingComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkGenerationsTable> {
  $$BenchmarkGenerationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get assistantTurnSequence => $composableBuilder(
    column: $table.assistantTurnSequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestPrompt => $composableBuilder(
    column: $table.requestPrompt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BenchmarkGenerationsTableAnnotationComposer
    extends Composer<_$_BenchmarkDatabase, $BenchmarkGenerationsTable> {
  $$BenchmarkGenerationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get conversationId => $composableBuilder(
    column: $table.conversationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get assistantTurnSequence => $composableBuilder(
    column: $table.assistantTurnSequence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get requestPrompt => $composableBuilder(
    column: $table.requestPrompt,
    builder: (column) => column,
  );
}

class $$BenchmarkGenerationsTableTableManager
    extends
        RootTableManager<
          _$_BenchmarkDatabase,
          $BenchmarkGenerationsTable,
          BenchmarkGeneration,
          $$BenchmarkGenerationsTableFilterComposer,
          $$BenchmarkGenerationsTableOrderingComposer,
          $$BenchmarkGenerationsTableAnnotationComposer,
          $$BenchmarkGenerationsTableCreateCompanionBuilder,
          $$BenchmarkGenerationsTableUpdateCompanionBuilder,
          (
            BenchmarkGeneration,
            BaseReferences<
              _$_BenchmarkDatabase,
              $BenchmarkGenerationsTable,
              BenchmarkGeneration
            >,
          ),
          BenchmarkGeneration,
          PrefetchHooks Function()
        > {
  $$BenchmarkGenerationsTableTableManager(
    _$_BenchmarkDatabase db,
    $BenchmarkGenerationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BenchmarkGenerationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BenchmarkGenerationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$BenchmarkGenerationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> conversationId = const Value.absent(),
                Value<int> assistantTurnSequence = const Value.absent(),
                Value<String> requestPrompt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BenchmarkGenerationsCompanion(
                id: id,
                conversationId: conversationId,
                assistantTurnSequence: assistantTurnSequence,
                requestPrompt: requestPrompt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String conversationId,
                required int assistantTurnSequence,
                required String requestPrompt,
                Value<int> rowid = const Value.absent(),
              }) => BenchmarkGenerationsCompanion.insert(
                id: id,
                conversationId: conversationId,
                assistantTurnSequence: assistantTurnSequence,
                requestPrompt: requestPrompt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BenchmarkGenerationsTableProcessedTableManager =
    ProcessedTableManager<
      _$_BenchmarkDatabase,
      $BenchmarkGenerationsTable,
      BenchmarkGeneration,
      $$BenchmarkGenerationsTableFilterComposer,
      $$BenchmarkGenerationsTableOrderingComposer,
      $$BenchmarkGenerationsTableAnnotationComposer,
      $$BenchmarkGenerationsTableCreateCompanionBuilder,
      $$BenchmarkGenerationsTableUpdateCompanionBuilder,
      (
        BenchmarkGeneration,
        BaseReferences<
          _$_BenchmarkDatabase,
          $BenchmarkGenerationsTable,
          BenchmarkGeneration
        >,
      ),
      BenchmarkGeneration,
      PrefetchHooks Function()
    >;

class $_BenchmarkDatabaseManager {
  final _$_BenchmarkDatabase _db;
  $_BenchmarkDatabaseManager(this._db);
  $$BenchmarkConversationsTableTableManager get benchmarkConversations =>
      $$BenchmarkConversationsTableTableManager(
        _db,
        _db.benchmarkConversations,
      );
  $$BenchmarkTurnsTableTableManager get benchmarkTurns =>
      $$BenchmarkTurnsTableTableManager(_db, _db.benchmarkTurns);
  $$BenchmarkGenerationsTableTableManager get benchmarkGenerations =>
      $$BenchmarkGenerationsTableTableManager(_db, _db.benchmarkGenerations);
}
