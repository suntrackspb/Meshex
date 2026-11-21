// This is a generated file - do not edit.
//
// Generated from feature_flags.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'feature_flags.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'feature_flags.pbenum.dart';

enum Envelope_Payload { request, response, notSet }

/// Send an Envelope as the payload of a self-addressed ADMIN_APP MeshPacket with
/// want_response=true. The response is an ADMIN_APP packet with request_id set.
/// Only local clients can use this protocol; normal local admin access checks apply.
/// Fields 50000 and 50001 are TMesh-specific, not part of Meshtastic's AdminMessage.
class Envelope extends $pb.GeneratedMessage {
  factory Envelope({
    Request? request,
    Response? response,
  }) {
    final result = Envelope._();
    if (request != null) result.request = request;
    if (response != null) result.response = response;
    return result;
  }

  Envelope._();

  factory Envelope.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Envelope()..mergeFromBuffer(data, registry);
  factory Envelope.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Envelope()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, Envelope_Payload> _Envelope_PayloadByTag = {
    50000: Envelope_Payload.request,
    50001: Envelope_Payload.response,
    0: Envelope_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Envelope',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tmesh'),
      createEmptyInstance: Envelope.$_createMessage)
    ..oo(0, [50000, 50001])
    ..aOM<Request>(50000, _omitFieldNames ? '' : 'request',
        subBuilder: Request.$_createMessage)
    ..aOM<Response>(50001, _omitFieldNames ? '' : 'response',
        subBuilder: Response.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Envelope copyWith(void Function(Envelope) updates) =>
      super.copyWith((message) => updates(message as Envelope)) as Envelope;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Envelope() / Envelope.new instead')
  static Envelope create() => Envelope._();
  static $pb.GeneratedMessage $_createMessage() => Envelope._();
  @$core.override
  Envelope createEmptyInstance() => Envelope._();
  @$core.pragma('dart2js:noInline')
  static Envelope getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Envelope>(Envelope.$_createMessage);
  static Envelope? _defaultInstance;

  @$pb.TagNumber(50000)
  @$pb.TagNumber(50001)
  Envelope_Payload whichPayload() => _Envelope_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(50000)
  @$pb.TagNumber(50001)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(50000)
  Request get request => $_getN(0);
  @$pb.TagNumber(50000)
  set request(Request value) => $_setField(50000, value);
  @$pb.TagNumber(50000)
  $core.bool hasRequest() => $_has(0);
  @$pb.TagNumber(50000)
  void clearRequest() => $_clearField(50000);
  @$pb.TagNumber(50000)
  Request ensureRequest() => $_ensure(0);

  @$pb.TagNumber(50001)
  Response get response => $_getN(1);
  @$pb.TagNumber(50001)
  set response(Response value) => $_setField(50001, value);
  @$pb.TagNumber(50001)
  $core.bool hasResponse() => $_has(1);
  @$pb.TagNumber(50001)
  void clearResponse() => $_clearField(50001);
  @$pb.TagNumber(50001)
  Response ensureResponse() => $_ensure(1);
}

class FeatureFlagsConfig extends $pb.GeneratedMessage {
  factory FeatureFlagsConfig({
    FeatureFlagsConfig_RestrictedRoutingMode? restrictedRoutingMode,
    $core.bool? restrictedRoutingDisallowsPrivateText,
    FeatureFlagsConfig_HopDecrementMode? hopDecrementMode,
    FeatureFlagsConfig_ForceNextHopMode? forceNextHopMode,
    $core.int? forceNextHopRelay,
    FeatureFlagsConfig_FavoriteRouterMode? favoriteRouterMode,
    $core.int? favoriteRouterRelay,
  }) {
    final result = FeatureFlagsConfig._();
    if (restrictedRoutingMode != null)
      result.restrictedRoutingMode = restrictedRoutingMode;
    if (restrictedRoutingDisallowsPrivateText != null)
      result.restrictedRoutingDisallowsPrivateText =
          restrictedRoutingDisallowsPrivateText;
    if (hopDecrementMode != null) result.hopDecrementMode = hopDecrementMode;
    if (forceNextHopMode != null) result.forceNextHopMode = forceNextHopMode;
    if (forceNextHopRelay != null) result.forceNextHopRelay = forceNextHopRelay;
    if (favoriteRouterMode != null)
      result.favoriteRouterMode = favoriteRouterMode;
    if (favoriteRouterRelay != null)
      result.favoriteRouterRelay = favoriteRouterRelay;
    return result;
  }

  FeatureFlagsConfig._();

  factory FeatureFlagsConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FeatureFlagsConfig()..mergeFromBuffer(data, registry);
  factory FeatureFlagsConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      FeatureFlagsConfig()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FeatureFlagsConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tmesh'),
      createEmptyInstance: FeatureFlagsConfig.$_createMessage)
    ..aE<FeatureFlagsConfig_RestrictedRoutingMode>(
        1, _omitFieldNames ? '' : 'restrictedRoutingMode',
        enumValues: FeatureFlagsConfig_RestrictedRoutingMode.values)
    ..aOB(2, _omitFieldNames ? '' : 'restrictedRoutingDisallowsPrivateText')
    ..aE<FeatureFlagsConfig_HopDecrementMode>(
        3, _omitFieldNames ? '' : 'hopDecrementMode',
        enumValues: FeatureFlagsConfig_HopDecrementMode.values)
    ..aE<FeatureFlagsConfig_ForceNextHopMode>(
        4, _omitFieldNames ? '' : 'forceNextHopMode',
        enumValues: FeatureFlagsConfig_ForceNextHopMode.values)
    ..aI(5, _omitFieldNames ? '' : 'forceNextHopRelay',
        fieldType: $pb.PbFieldType.OU3)
    ..aE<FeatureFlagsConfig_FavoriteRouterMode>(
        6, _omitFieldNames ? '' : 'favoriteRouterMode',
        enumValues: FeatureFlagsConfig_FavoriteRouterMode.values)
    ..aI(7, _omitFieldNames ? '' : 'favoriteRouterRelay',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlagsConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FeatureFlagsConfig copyWith(void Function(FeatureFlagsConfig) updates) =>
      super.copyWith((message) => updates(message as FeatureFlagsConfig))
          as FeatureFlagsConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use FeatureFlagsConfig() / FeatureFlagsConfig.new instead')
  static FeatureFlagsConfig create() => FeatureFlagsConfig._();
  static $pb.GeneratedMessage $_createMessage() => FeatureFlagsConfig._();
  @$core.override
  FeatureFlagsConfig createEmptyInstance() => FeatureFlagsConfig._();
  @$core.pragma('dart2js:noInline')
  static FeatureFlagsConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FeatureFlagsConfig>(
          FeatureFlagsConfig.$_createMessage);
  static FeatureFlagsConfig? _defaultInstance;

  @$pb.TagNumber(1)
  FeatureFlagsConfig_RestrictedRoutingMode get restrictedRoutingMode =>
      $_getN(0);
  @$pb.TagNumber(1)
  set restrictedRoutingMode(FeatureFlagsConfig_RestrictedRoutingMode value) =>
      $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRestrictedRoutingMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearRestrictedRoutingMode() => $_clearField(1);

  /// False preserves the legacy default of allowing private text.
  @$pb.TagNumber(2)
  $core.bool get restrictedRoutingDisallowsPrivateText => $_getBF(1);
  @$pb.TagNumber(2)
  set restrictedRoutingDisallowsPrivateText($core.bool value) =>
      $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRestrictedRoutingDisallowsPrivateText() => $_has(1);
  @$pb.TagNumber(2)
  void clearRestrictedRoutingDisallowsPrivateText() => $_clearField(2);

  @$pb.TagNumber(3)
  FeatureFlagsConfig_HopDecrementMode get hopDecrementMode => $_getN(2);
  @$pb.TagNumber(3)
  set hopDecrementMode(FeatureFlagsConfig_HopDecrementMode value) =>
      $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasHopDecrementMode() => $_has(2);
  @$pb.TagNumber(3)
  void clearHopDecrementMode() => $_clearField(3);

  @$pb.TagNumber(4)
  FeatureFlagsConfig_ForceNextHopMode get forceNextHopMode => $_getN(3);
  @$pb.TagNumber(4)
  set forceNextHopMode(FeatureFlagsConfig_ForceNextHopMode value) =>
      $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasForceNextHopMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearForceNextHopMode() => $_clearField(4);

  /// Relay values are last bytes, 0..255; an enabled mode requires 1..255.
  @$pb.TagNumber(5)
  $core.int get forceNextHopRelay => $_getIZ(4);
  @$pb.TagNumber(5)
  set forceNextHopRelay($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasForceNextHopRelay() => $_has(4);
  @$pb.TagNumber(5)
  void clearForceNextHopRelay() => $_clearField(5);

  @$pb.TagNumber(6)
  FeatureFlagsConfig_FavoriteRouterMode get favoriteRouterMode => $_getN(5);
  @$pb.TagNumber(6)
  set favoriteRouterMode(FeatureFlagsConfig_FavoriteRouterMode value) =>
      $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasFavoriteRouterMode() => $_has(5);
  @$pb.TagNumber(6)
  void clearFavoriteRouterMode() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get favoriteRouterRelay => $_getIZ(6);
  @$pb.TagNumber(7)
  set favoriteRouterRelay($core.int value) => $_setUnsignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasFavoriteRouterRelay() => $_has(6);
  @$pb.TagNumber(7)
  void clearFavoriteRouterRelay() => $_clearField(7);
}

class Request extends $pb.GeneratedMessage {
  factory Request({
    Request_Operation? operation,
    FeatureFlagsConfig? config,
  }) {
    final result = Request._();
    if (operation != null) result.operation = operation;
    if (config != null) result.config = config;
    return result;
  }

  Request._();

  factory Request.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Request()..mergeFromBuffer(data, registry);
  factory Request.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Request()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Request',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tmesh'),
      createEmptyInstance: Request.$_createMessage)
    ..aE<Request_Operation>(1, _omitFieldNames ? '' : 'operation',
        enumValues: Request_Operation.values)
    ..aOM<FeatureFlagsConfig>(2, _omitFieldNames ? '' : 'config',
        subBuilder: FeatureFlagsConfig.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Request clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Request copyWith(void Function(Request) updates) =>
      super.copyWith((message) => updates(message as Request)) as Request;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Request() / Request.new instead')
  static Request create() => Request._();
  static $pb.GeneratedMessage $_createMessage() => Request._();
  @$core.override
  Request createEmptyInstance() => Request._();
  @$core.pragma('dart2js:noInline')
  static Request getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Request>(Request.$_createMessage);
  static Request? _defaultInstance;

  /// GET reads the custom config, SET replaces it, CLEAR restores legacy fallback.
  @$pb.TagNumber(1)
  Request_Operation get operation => $_getN(0);
  @$pb.TagNumber(1)
  set operation(Request_Operation value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasOperation() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperation() => $_clearField(1);

  @$pb.TagNumber(2)
  FeatureFlagsConfig get config => $_getN(1);
  @$pb.TagNumber(2)
  set config(FeatureFlagsConfig value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasConfig() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfig() => $_clearField(2);
  @$pb.TagNumber(2)
  FeatureFlagsConfig ensureConfig() => $_ensure(1);
}

class Response extends $pb.GeneratedMessage {
  factory Response({
    Response_Status? status,
    FeatureFlagsConfig? config,
  }) {
    final result = Response._();
    if (status != null) result.status = status;
    if (config != null) result.config = config;
    return result;
  }

  Response._();

  factory Response.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Response()..mergeFromBuffer(data, registry);
  factory Response.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Response()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Response',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tmesh'),
      createEmptyInstance: Response.$_createMessage)
    ..aE<Response_Status>(1, _omitFieldNames ? '' : 'status',
        enumValues: Response_Status.values)
    ..aOM<FeatureFlagsConfig>(2, _omitFieldNames ? '' : 'config',
        subBuilder: FeatureFlagsConfig.$_createMessage)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Response clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Response copyWith(void Function(Response) updates) =>
      super.copyWith((message) => updates(message as Response)) as Response;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Response() / Response.new instead')
  static Response create() => Response._();
  static $pb.GeneratedMessage $_createMessage() => Response._();
  @$core.override
  Response createEmptyInstance() => Response._();
  @$core.pragma('dart2js:noInline')
  static Response getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Response>(Response.$_createMessage);
  static Response? _defaultInstance;

  @$pb.TagNumber(1)
  Response_Status get status => $_getN(0);
  @$pb.TagNumber(1)
  set status(Response_Status value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStatus() => $_has(0);
  @$pb.TagNumber(1)
  void clearStatus() => $_clearField(1);

  /// When status is OK, absence means the detection-sensor fallback is active.
  @$pb.TagNumber(2)
  FeatureFlagsConfig get config => $_getN(1);
  @$pb.TagNumber(2)
  set config(FeatureFlagsConfig value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasConfig() => $_has(1);
  @$pb.TagNumber(2)
  void clearConfig() => $_clearField(2);
  @$pb.TagNumber(2)
  FeatureFlagsConfig ensureConfig() => $_ensure(1);
}

class Store extends $pb.GeneratedMessage {
  factory Store({
    FeatureFlagsConfig? config,
    $core.int? formatVersion,
  }) {
    final result = Store._();
    if (config != null) result.config = config;
    if (formatVersion != null) result.formatVersion = formatVersion;
    return result;
  }

  Store._();

  factory Store.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Store()..mergeFromBuffer(data, registry);
  factory Store.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      Store()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Store',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'tmesh'),
      createEmptyInstance: Store.$_createMessage)
    ..aOM<FeatureFlagsConfig>(1, _omitFieldNames ? '' : 'config',
        subBuilder: FeatureFlagsConfig.$_createMessage)
    ..aI(2, _omitFieldNames ? '' : 'formatVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Store clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Store copyWith(void Function(Store) updates) =>
      super.copyWith((message) => updates(message as Store)) as Store;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  @$core.Deprecated('Use Store() / Store.new instead')
  static Store create() => Store._();
  static $pb.GeneratedMessage $_createMessage() => Store._();
  @$core.override
  Store createEmptyInstance() => Store._();
  @$core.pragma('dart2js:noInline')
  static Store getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<Store>(Store.$_createMessage);
  static Store? _defaultInstance;

  @$pb.TagNumber(1)
  FeatureFlagsConfig get config => $_getN(0);
  @$pb.TagNumber(1)
  set config(FeatureFlagsConfig value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasConfig() => $_has(0);
  @$pb.TagNumber(1)
  void clearConfig() => $_clearField(1);
  @$pb.TagNumber(1)
  FeatureFlagsConfig ensureConfig() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.int get formatVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set formatVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFormatVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearFormatVersion() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
