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
  @override
  List<GeneratedColumn> get $columns => [
    id,
    conversationId,
    role,
    status,
    content,
    savedAtMs,
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
  const TurnRow({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.status,
    required this.content,
    required this.savedAtMs,
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
    };
  }

  TurnRow copyWith({
    int? id,
    String? conversationId,
    String? role,
    String? status,
    String? content,
    int? savedAtMs,
  }) => TurnRow(
    id: id ?? this.id,
    conversationId: conversationId ?? this.conversationId,
    role: role ?? this.role,
    status: status ?? this.status,
    content: content ?? this.content,
    savedAtMs: savedAtMs ?? this.savedAtMs,
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
          ..write('savedAtMs: $savedAtMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, conversationId, role, status, content, savedAtMs);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TurnRow &&
          other.id == this.id &&
          other.conversationId == this.conversationId &&
          other.role == this.role &&
          other.status == this.status &&
          other.content == this.content &&
          other.savedAtMs == this.savedAtMs);
}

class TurnRowsCompanion extends UpdateCompanion<TurnRow> {
  final Value<int> id;
  final Value<String> conversationId;
  final Value<String> role;
  final Value<String> status;
  final Value<String> content;
  final Value<int> savedAtMs;
  const TurnRowsCompanion({
    this.id = const Value.absent(),
    this.conversationId = const Value.absent(),
    this.role = const Value.absent(),
    this.status = const Value.absent(),
    this.content = const Value.absent(),
    this.savedAtMs = const Value.absent(),
  });
  TurnRowsCompanion.insert({
    this.id = const Value.absent(),
    required String conversationId,
    required String role,
    required String status,
    required String content,
    required int savedAtMs,
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
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (conversationId != null) 'conversation_id': conversationId,
      if (role != null) 'role': role,
      if (status != null) 'status': status,
      if (content != null) 'content': content,
      if (savedAtMs != null) 'saved_at_ms': savedAtMs,
    });
  }

  TurnRowsCompanion copyWith({
    Value<int>? id,
    Value<String>? conversationId,
    Value<String>? role,
    Value<String>? status,
    Value<String>? content,
    Value<int>? savedAtMs,
  }) {
    return TurnRowsCompanion(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      status: status ?? this.status,
      content: content ?? this.content,
      savedAtMs: savedAtMs ?? this.savedAtMs,
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
          ..write('savedAtMs: $savedAtMs')
          ..write(')'))
        .toString();
  }
}

abstract class _$ConversationDatabase extends GeneratedDatabase {
  _$ConversationDatabase(QueryExecutor e) : super(e);
  $ConversationDatabaseManager get managers =>
      $ConversationDatabaseManager(this);
  late final $TurnRowsTable turnRows = $TurnRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [turnRows];
}

typedef $$TurnRowsTableCreateCompanionBuilder =
    TurnRowsCompanion Function({
      Value<int> id,
      required String conversationId,
      required String role,
      required String status,
      required String content,
      required int savedAtMs,
    });
typedef $$TurnRowsTableUpdateCompanionBuilder =
    TurnRowsCompanion Function({
      Value<int> id,
      Value<String> conversationId,
      Value<String> role,
      Value<String> status,
      Value<String> content,
      Value<int> savedAtMs,
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
              }) => TurnRowsCompanion(
                id: id,
                conversationId: conversationId,
                role: role,
                status: status,
                content: content,
                savedAtMs: savedAtMs,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String conversationId,
                required String role,
                required String status,
                required String content,
                required int savedAtMs,
              }) => TurnRowsCompanion.insert(
                id: id,
                conversationId: conversationId,
                role: role,
                status: status,
                content: content,
                savedAtMs: savedAtMs,
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

class $ConversationDatabaseManager {
  final _$ConversationDatabase _db;
  $ConversationDatabaseManager(this._db);
  $$TurnRowsTableTableManager get turnRows =>
      $$TurnRowsTableTableManager(_db, _db.turnRows);
}
