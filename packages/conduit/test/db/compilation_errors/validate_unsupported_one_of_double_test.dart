// ignore_for_file: avoid_catching_errors

import 'package:conduit/conduit.dart';
import 'package:test/test.dart';

class UnsupportedDoubleOneOf extends ManagedObject<_UDOOO> {}

class _UDOOO {
  @primaryKey
  int? id;

  @Validate.oneOf(["3.14159265359", "2.71828"])
  double? someFloatingNumber;
}

void main() {
  test("Unsupported type, double, for oneOf", () {
    try {
      ManagedDataModel([UnsupportedDoubleOneOf]);
      expect(true, false);
    } on ManagedDataModelError catch (e) {
      expect(e.toString(), contains("Validate.oneOf"));
      expect(e.toString(), contains("someFloatingNumber"));
    }
  });
}
