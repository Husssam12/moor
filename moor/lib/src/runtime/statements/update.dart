import 'dart:async';

import 'package:moor/moor.dart';
import 'package:moor/src/runtime/components/component.dart';

class UpdateStatement<T extends Table, D extends DataClass> extends Query<T, D>
    with SingleTableQueryMixin<T, D> {
  UpdateStatement(QueryEngine database, TableInfo<T, D> table)
      : super(database, table);

  Map<String, Variable> _updatedFields;

  @override
  void writeStartPart(GenerationContext ctx) {
    // TODO support the OR (ROLLBACK / ABORT / REPLACE / FAIL / IGNORE...) thing

    ctx.buffer.write('UPDATE ${table.$tableName} SET ');

    var first = true;
    _updatedFields.forEach((columnName, variable) {
      if (!first) {
        ctx.buffer.write(', ');
      } else {
        first = false;
      }

      ctx.buffer..write(columnName)..write(' = ');

      variable.writeInto(ctx);
    });
  }

  Future<int> _performQuery() async {
    final ctx = constructQuery();
    final rows = await ctx.executor.doWhenOpened((e) async {
      return await e.runUpdate(ctx.sql, ctx.boundVariables);
    });

    if (rows > 0) {
      database.markTablesUpdated({table});
    }

    return rows;
  }

  /// Writes all non-null fields from [entity] into the columns of all rows
  /// that match the [where] clause. Warning: That also means that, when you're
  /// not setting a where clause explicitly, this method will update all rows in
  /// the [table].
  ///
  /// The fields that are null on the [entity] object will not be changed by
  /// this operation, they will be ignored.
  ///
  /// Returns the amount of rows that have been affected by this operation.
  ///
  /// See also: [replace], which does not require [where] statements and
  /// supports setting fields back to null.
  Future<int> write(Insertable<D> entity) async {
    // todo needs to use entity as update companion here
    table.validateIntegrity(null).throwIfInvalid(entity);

    _updatedFields = table.entityToSql(entity.createCompanion(true))
      ..remove((_, value) => value == null);

    if (_updatedFields.isEmpty) {
      // nothing to update, we're done
      return Future.value(0);
    }

    return await _performQuery();
  }

  /// Replaces the old version of [entity] that is stored in the database with
  /// the fields of the [entity] provided here. This implicitly applies a
  /// [where] clause to rows with the same primary key as [entity], so that only
  /// the row representing outdated data will be replaced.
  ///
  /// If [entity] has fields with null as value, data in the row will be set
  /// back to null. This behavior is different to that of [write], which ignores
  /// null fields.
  ///
  /// Returns true if a row was affected by this operation.
  ///
  /// See also:
  ///  - [write], which doesn't apply a [where] statement itself and ignores
  ///    null values in the entity.
  ///  - [InsertStatement.insert] with the `orReplace` parameter, which behaves
  ///  similar to this method but creates a new row if none exists.
  Future<bool> replace(Insertable<D> entity) async {
    // We don't turn nulls to absent values here (as opposed to a regular
    // update, where only non-null fields will be written).
    final companion = entity.createCompanion(false);
    table.validateIntegrity(companion).throwIfInvalid(entity);
    assert(
        whereExpr == null,
        'When using replace on an update statement, you may not use where(...)'
        'as well. The where clause will be determined automatically');

    whereSamePrimaryKey(entity);

    _updatedFields = table.entityToSql(companion);
    final primaryKeys = table.$primaryKey.map((c) => c.$name);

    // Don't update the primary key
    _updatedFields.removeWhere((key, _) => primaryKeys.contains(key));

    final updatedRows = await _performQuery();
    return updatedRows != 0;
  }
}
