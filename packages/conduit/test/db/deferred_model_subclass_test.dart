// ignore_for_file: overridden_fields

import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

void main() {
  test("Can override property in partial and modify attrs/validators", () {
    final dataModel =
        ManagedDataModel([OverriddenTotalModel, PartialReferenceModel]);

    final entity = dataModel.entityForType(OverriddenTotalModel);
    final field = entity.attributes["field"]!;
    expect(field.isUnique, true);
    expect(field.validators.length, 1);
  });
}

class OverriddenTotalModel extends ManagedObject<_OverriddenTotalModel>
    implements _OverriddenTotalModel {}

class _OverriddenTotalModel extends PartialModel {
  @override
  @Column(indexed: true, unique: true)
  @Validate.oneOf(["a", "b"])
  String? field;
}

class PartialModel {
  @primaryKey
  int? id;

  @Column(indexed: true)
  String? field;

  ManagedSet<PartialReferenceModel>? hasManyRelationship;

  static String tableName() {
    return "predefined";
  }
}

class PartialReferenceModel extends ManagedObject<_PartialReferenceModel>
    implements _PartialReferenceModel {}

class _PartialReferenceModel {
  @primaryKey
  int? id;

  String? field;

  @Relate.deferred(DeleteRule.cascade, isRequired: true)
  PartialModel? foreignKeyColumn;
}
