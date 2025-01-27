// ignore_for_file: avoid_catching_errors

import 'package:conduit/src/db/managed/data_model.dart';
import 'package:conduit/src/db/managed/entity.dart';
import 'package:conduit/src/db/managed/relationship_type.dart';
import 'package:conduit/src/db/managed/validation/managed.dart';
import 'package:conduit/src/db/managed/validation/metadata.dart';
import 'package:conduit/src/runtime/orm/entity_builder.dart';
import 'package:conduit/src/runtime/orm/property_builder.dart';

class ValidatorBuilder {
  ValidatorBuilder(this.property, this.metadata);

  final PropertyBuilder property;
  final Validate metadata;
  dynamic _state;
  ManagedValidator? _validator;

  ManagedValidator? get managedValidator => _validator;

  void compile(List<EntityBuilder>? entityBuilders) {}

  void validate(List<EntityBuilder>? entityBuilders) {
    if (property.isRelationship) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        throw ManagedDataModelError(
          "Invalid '@Validate' on property '${property.parent.name}.${property.name}'. Validations cannot be performed on has-one or has-many relationships.",
        );
      }
    }
    Type? type;
    PropertyBuilder? prop = property;
    if (property.isRelationship) {
      if (property.relationshipType != ManagedRelationshipType.belongsTo) {
        throw ManagedDataModelError(
          "Invalid '@Validate' on property '${property.parent.name}.${property.name}'. Validations cannot be performed on has-one or has-many relationships.",
        );
      }

      type = property.relatedProperty!.parent.instanceType.reflectedType;
      prop = property.relatedProperty!.parent.primaryKeyProperty;
    }

    try {
      _state = metadata.compile(prop.type, relationshipInverseType: type);
    } on ValidateCompilationError catch (e) {
      throw ManagedDataModelError(
        "Invalid '@Validate' on property '${property.parent.name}.${property.name}'. Reason: ${e.reason}",
      );
    }
  }

  void link(List<ManagedEntity> others) {
    _validator = ManagedValidator(metadata, _state);
  }
}
