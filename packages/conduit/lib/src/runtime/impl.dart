import 'dart:async';
import 'dart:mirrors';

import 'package:conduit/src/application/application.dart';
import 'package:conduit/src/application/channel.dart';
import 'package:conduit/src/application/isolate_application_server.dart';
import 'package:conduit/src/application/options.dart';
import 'package:conduit/src/http/controller.dart';
import 'package:conduit/src/http/resource_controller.dart';
import 'package:conduit/src/http/resource_controller_interfaces.dart';
import 'package:conduit/src/http/serializable.dart';
import 'package:conduit/src/runtime/resource_controller_impl.dart';
import 'package:conduit_common/conduit_common.dart';
import 'package:conduit_open_api/v3.dart';
import 'package:conduit_runtime/runtime.dart';

class ChannelRuntimeImpl extends ChannelRuntime implements SourceCompiler {
  ChannelRuntimeImpl(this.type);

  final ClassMirror type;

  static const _globalStartSymbol = #initializeApplication;

  @override
  String get name => MirrorSystem.getName(type.simpleName);

  @override
  IsolateEntryFunction get isolateEntryPoint => isolateServerEntryPoint;

  @override
  Uri get libraryUri => (type.owner! as LibraryMirror).uri;

  bool get hasGlobalInitializationMethod {
    return type.staticMembers[_globalStartSymbol] != null;
  }

  @override
  Type get channelType => type.reflectedType;

  @override
  ApplicationChannel instantiateChannel() {
    return type.newInstance(Symbol.empty, []).reflectee as ApplicationChannel;
  }

  @override
  Future? runGlobalInitialization(ApplicationOptions config) {
    if (hasGlobalInitializationMethod) {
      return type.invoke(_globalStartSymbol, [config]).reflectee as Future?;
    }

    return null;
  }

  @override
  Iterable<APIComponentDocumenter?> getDocumentableChannelComponents(
    ApplicationChannel channel,
  ) {
    final documenter = reflectType(APIComponentDocumenter);
    return type.declarations.values
        .whereType<VariableMirror>()
        .where(
          (member) =>
              !member.isStatic && member.type.isAssignableTo(documenter),
        )
        .map((dm) {
      return reflect(channel).getField(dm.simpleName).reflectee
          as APIComponentDocumenter?;
    }).where((o) => o != null);
  }

  @override
  Future<String> compile(BuildContext ctx) async {
    final className = MirrorSystem.getName(type.simpleName);
    final originalFileUri = type.location!.sourceUri.toString();
    final globalInitBody = hasGlobalInitializationMethod
        ? "await $className.initializeApplication(config);"
        : "";

    return """
import 'dart:async';    
import 'package:conduit/conduit.dart';
import 'package:conduit/src/application/isolate_application_server.dart';
import 'package:conduit_common/conduit_common.dart';

import '$originalFileUri';

final instance = ChannelRuntimeImpl();

void entryPoint(ApplicationInitialServerMessage params) {
  final runtime = ChannelRuntimeImpl();
  
  final server = ApplicationIsolateServer(runtime.channelType,
    params.configuration, params.identifier, params.parentMessagePort,
    logToConsole: params.logToConsole);

  server.start(shareHttpServer: true);
}

class ChannelRuntimeImpl extends ChannelRuntime {
  @override
  String get name => '$className';

  @override
  IsolateEntryFunction get isolateEntryPoint => entryPoint;
  
  @override
  Uri get libraryUri => Uri();

  @override
  Type get channelType => $className;
  
  @override
  ApplicationChannel instantiateChannel() {
    return $className();
  }
  
  @override
  Future runGlobalInitialization(ApplicationOptions config) async {
    $globalInitBody
  }
  
  @override
  Iterable<APIComponentDocumenter> getDocumentableChannelComponents(
      ApplicationChannel channel) { 
    throw UnsupportedError('This method is not implemented for compiled applications.');
  }
}
    """;
  }
}

void isolateServerEntryPoint(ApplicationInitialServerMessage params) {
  final channelSourceLibrary =
      currentMirrorSystem().libraries[params.streamLibraryURI]!;
  final channelType = channelSourceLibrary
      .declarations[Symbol(params.streamTypeName)]! as ClassMirror;

  final runtime = ChannelRuntimeImpl(channelType);

  final server = ApplicationIsolateServer(
    runtime.channelType,
    params.configuration,
    params.identifier,
    params.parentMessagePort,
    logToConsole: params.logToConsole,
  );

  server.start(shareHttpServer: true);
}

class ControllerRuntimeImpl extends ControllerRuntime
    implements SourceCompiler {
  ControllerRuntimeImpl(this.type) {
    if (type.isSubclassOf(reflectClass(ResourceController))) {
      resourceController = ResourceControllerRuntimeImpl(type);
    }

    if (isMutable && !type.isAssignableTo(reflectType(Recyclable))) {
      throw StateError(
          "Invalid controller '${MirrorSystem.getName(type.simpleName)}'. "
          "Controllers must not have setters and all fields must be marked as final, or it must implement 'Recyclable'.");
    }
  }

  final ClassMirror type;

  @override
  ResourceControllerRuntime? resourceController;

  @override
  bool get isMutable {
    // We have a whitelist for a few things declared in controller that can't be final.
    final whitelist = ['policy=', '_nextController='];
    final members = type.instanceMembers;
    final fieldKeys = type.instanceMembers.keys
        .where((sym) => !whitelist.contains(MirrorSystem.getName(sym)));
    return fieldKeys.any((key) => members[key]!.isSetter);
  }

  @override
  Future<String> compile(BuildContext ctx) async {
    final originalFileUri = type.location!.sourceUri.toString();

    return """
import 'dart:async';    
import 'package:conduit/conduit.dart';
import '$originalFileUri';
${(resourceController as ResourceControllerRuntimeImpl?)?.directives.join("\n") ?? ""}
    
final instance = ControllerRuntimeImpl();
    
class ControllerRuntimeImpl extends ControllerRuntime {
  ControllerRuntimeImpl() {
    ${resourceController == null ? "" : "_resourceController = ResourceControllerRuntimeImpl();"}
  }
  
  @override
  bool get isMutable => $isMutable;

  ResourceControllerRuntime get resourceController => _resourceController;
  late ResourceControllerRuntime _resourceController;
}

${(resourceController as ResourceControllerRuntimeImpl?)?.compile(ctx) ?? ""}
    """;
  }
}

class SerializableRuntimeImpl extends SerializableRuntime {
  SerializableRuntimeImpl(this.type);

  final ClassMirror type;

  @override
  APISchemaObject documentSchema(APIDocumentContext context) {
    final mirror = type;

    final obj = APISchemaObject.object({})
      ..title = MirrorSystem.getName(mirror.simpleName);
    try {
      for (final property
          in mirror.declarations.values.whereType<VariableMirror>()) {
        final propName = MirrorSystem.getName(property.simpleName);
        obj.properties![propName] = documentVariable(context, property);
      }
    } catch (e) {
      obj.additionalPropertyPolicy = APISchemaAdditionalPropertyPolicy.freeForm;
      obj.description =
          "Failed to auto-document type '${MirrorSystem.getName(mirror.simpleName)}': $e";
    }

    return obj;
  }

  static APISchemaObject documentVariable(
    APIDocumentContext context,
    VariableMirror mirror,
  ) {
    final APISchemaObject object = documentType(context, mirror.type)
      ..title = MirrorSystem.getName(mirror.simpleName);

    return object;
  }

  static APISchemaObject documentType(
    APIDocumentContext context,
    TypeMirror type,
  ) {
    if (type.isAssignableTo(reflectType(int))) {
      return APISchemaObject.integer();
    } else if (type.isAssignableTo(reflectType(double))) {
      return APISchemaObject.number();
    } else if (type.isAssignableTo(reflectType(String))) {
      return APISchemaObject.string();
    } else if (type.isAssignableTo(reflectType(bool))) {
      return APISchemaObject.boolean();
    } else if (type.isAssignableTo(reflectType(DateTime))) {
      return APISchemaObject.string(format: "date-time");
    } else if (type.isAssignableTo(reflectType(List))) {
      return APISchemaObject.array(
        ofSchema: documentType(context, type.typeArguments.first),
      );
    } else if (type.isAssignableTo(reflectType(Map))) {
      if (!type.typeArguments.first.isAssignableTo(reflectType(String))) {
        throw ArgumentError("Unsupported type 'Map' with non-string keys.");
      }
      return APISchemaObject()
        ..type = APIType.object
        ..additionalPropertySchema =
            documentType(context, type.typeArguments.last);
    } else if (type.isAssignableTo(reflectType(Serializable))) {
      final instance = (type as ClassMirror)
          .newInstance(Symbol.empty, []).reflectee as Serializable;
      return instance.documentSchema(context);
    }

    throw ArgumentError(
        "Unsupported type '${MirrorSystem.getName(type.simpleName)}' "
        "for 'APIComponentDocumenter.documentType'.");
  }
}
