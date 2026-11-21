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

class FeatureFlagsConfig_RestrictedRoutingMode extends $pb.ProtobufEnum {
  static const FeatureFlagsConfig_RestrictedRoutingMode STANDARD_CORE_PORTS =
      FeatureFlagsConfig_RestrictedRoutingMode._(
          0, _omitEnumNames ? '' : 'STANDARD_CORE_PORTS');
  static const FeatureFlagsConfig_RestrictedRoutingMode TEXT_ALL_AND_ADMIN =
      FeatureFlagsConfig_RestrictedRoutingMode._(
          1, _omitEnumNames ? '' : 'TEXT_ALL_AND_ADMIN');
  static const FeatureFlagsConfig_RestrictedRoutingMode
      TEXT_ALL_ADMIN_AND_ROUTING = FeatureFlagsConfig_RestrictedRoutingMode._(
          2, _omitEnumNames ? '' : 'TEXT_ALL_ADMIN_AND_ROUTING');
  static const FeatureFlagsConfig_RestrictedRoutingMode
      TEXT_ALL_ADMIN_ROUTING_AND_TRACEROUTE =
      FeatureFlagsConfig_RestrictedRoutingMode._(
          3, _omitEnumNames ? '' : 'TEXT_ALL_ADMIN_ROUTING_AND_TRACEROUTE');
  static const FeatureFlagsConfig_RestrictedRoutingMode
      TEXT_ALL_NODEINFO_ADMIN_AND_ROUTING =
      FeatureFlagsConfig_RestrictedRoutingMode._(
          4, _omitEnumNames ? '' : 'TEXT_ALL_NODEINFO_ADMIN_AND_ROUTING');
  static const FeatureFlagsConfig_RestrictedRoutingMode
      TEXT_ALL_NODEINFO_ADMIN_ROUTING_AND_TRACEROUTE =
      FeatureFlagsConfig_RestrictedRoutingMode._(
          5,
          _omitEnumNames
              ? ''
              : 'TEXT_ALL_NODEINFO_ADMIN_ROUTING_AND_TRACEROUTE');

  static const $core.List<FeatureFlagsConfig_RestrictedRoutingMode> values =
      <FeatureFlagsConfig_RestrictedRoutingMode>[
    STANDARD_CORE_PORTS,
    TEXT_ALL_AND_ADMIN,
    TEXT_ALL_ADMIN_AND_ROUTING,
    TEXT_ALL_ADMIN_ROUTING_AND_TRACEROUTE,
    TEXT_ALL_NODEINFO_ADMIN_AND_ROUTING,
    TEXT_ALL_NODEINFO_ADMIN_ROUTING_AND_TRACEROUTE,
  ];

  static final $core.List<FeatureFlagsConfig_RestrictedRoutingMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static FeatureFlagsConfig_RestrictedRoutingMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FeatureFlagsConfig_RestrictedRoutingMode._(super.value, super.name);
}

class FeatureFlagsConfig_HopDecrementMode extends $pb.ProtobufEnum {
  static const FeatureFlagsConfig_HopDecrementMode
      STANDARD_FAVORITE_ROUTER_BEHAVIOR = FeatureFlagsConfig_HopDecrementMode._(
          0, _omitEnumNames ? '' : 'STANDARD_FAVORITE_ROUTER_BEHAVIOR');
  static const FeatureFlagsConfig_HopDecrementMode
      PRESERVE_AFTER_ANY_FAVORITE_RELAY = FeatureFlagsConfig_HopDecrementMode._(
          1, _omitEnumNames ? '' : 'PRESERVE_AFTER_ANY_FAVORITE_RELAY');
  static const FeatureFlagsConfig_HopDecrementMode DECREMENT_FIRST_HOP_ONLY =
      FeatureFlagsConfig_HopDecrementMode._(
          2, _omitEnumNames ? '' : 'DECREMENT_FIRST_HOP_ONLY');

  static const $core.List<FeatureFlagsConfig_HopDecrementMode> values =
      <FeatureFlagsConfig_HopDecrementMode>[
    STANDARD_FAVORITE_ROUTER_BEHAVIOR,
    PRESERVE_AFTER_ANY_FAVORITE_RELAY,
    DECREMENT_FIRST_HOP_ONLY,
  ];

  static final $core.List<FeatureFlagsConfig_HopDecrementMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static FeatureFlagsConfig_HopDecrementMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FeatureFlagsConfig_HopDecrementMode._(super.value, super.name);
}

class FeatureFlagsConfig_ForceNextHopMode extends $pb.ProtobufEnum {
  static const FeatureFlagsConfig_ForceNextHopMode FORCE_NEXT_HOP_DISABLED =
      FeatureFlagsConfig_ForceNextHopMode._(
          0, _omitEnumNames ? '' : 'FORCE_NEXT_HOP_DISABLED');
  static const FeatureFlagsConfig_ForceNextHopMode
      LOCAL_PACKETS_WITH_FLOODING_FALLBACK =
      FeatureFlagsConfig_ForceNextHopMode._(
          1, _omitEnumNames ? '' : 'LOCAL_PACKETS_WITH_FLOODING_FALLBACK');
  static const FeatureFlagsConfig_ForceNextHopMode
      LOCAL_AND_RELAYED_PACKETS_WITH_FLOODING_FALLBACK =
      FeatureFlagsConfig_ForceNextHopMode._(
          2,
          _omitEnumNames
              ? ''
              : 'LOCAL_AND_RELAYED_PACKETS_WITH_FLOODING_FALLBACK');
  static const FeatureFlagsConfig_ForceNextHopMode
      ALL_PACKETS_WITHOUT_FORCED_FLOODING_FALLBACK =
      FeatureFlagsConfig_ForceNextHopMode._(3,
          _omitEnumNames ? '' : 'ALL_PACKETS_WITHOUT_FORCED_FLOODING_FALLBACK');

  static const $core.List<FeatureFlagsConfig_ForceNextHopMode> values =
      <FeatureFlagsConfig_ForceNextHopMode>[
    FORCE_NEXT_HOP_DISABLED,
    LOCAL_PACKETS_WITH_FLOODING_FALLBACK,
    LOCAL_AND_RELAYED_PACKETS_WITH_FLOODING_FALLBACK,
    ALL_PACKETS_WITHOUT_FORCED_FLOODING_FALLBACK,
  ];

  static final $core.List<FeatureFlagsConfig_ForceNextHopMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static FeatureFlagsConfig_ForceNextHopMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FeatureFlagsConfig_ForceNextHopMode._(super.value, super.name);
}

class FeatureFlagsConfig_FavoriteRouterMode extends $pb.ProtobufEnum {
  static const FeatureFlagsConfig_FavoriteRouterMode FAVORITE_ROUTER_DISABLED =
      FeatureFlagsConfig_FavoriteRouterMode._(
          0, _omitEnumNames ? '' : 'FAVORITE_ROUTER_DISABLED');
  static const FeatureFlagsConfig_FavoriteRouterMode PRESERVE_HOPS_ONLY =
      FeatureFlagsConfig_FavoriteRouterMode._(
          1, _omitEnumNames ? '' : 'PRESERVE_HOPS_ONLY');
  static const FeatureFlagsConfig_FavoriteRouterMode PRESERVE_HOPS_AND_RELAY =
      FeatureFlagsConfig_FavoriteRouterMode._(
          2, _omitEnumNames ? '' : 'PRESERVE_HOPS_AND_RELAY');

  static const $core.List<FeatureFlagsConfig_FavoriteRouterMode> values =
      <FeatureFlagsConfig_FavoriteRouterMode>[
    FAVORITE_ROUTER_DISABLED,
    PRESERVE_HOPS_ONLY,
    PRESERVE_HOPS_AND_RELAY,
  ];

  static final $core.List<FeatureFlagsConfig_FavoriteRouterMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 2);
  static FeatureFlagsConfig_FavoriteRouterMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FeatureFlagsConfig_FavoriteRouterMode._(super.value, super.name);
}

class Request_Operation extends $pb.ProtobufEnum {
  static const Request_Operation UNSPECIFIED =
      Request_Operation._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const Request_Operation GET =
      Request_Operation._(1, _omitEnumNames ? '' : 'GET');
  static const Request_Operation SET =
      Request_Operation._(2, _omitEnumNames ? '' : 'SET');
  static const Request_Operation CLEAR =
      Request_Operation._(3, _omitEnumNames ? '' : 'CLEAR');

  static const $core.List<Request_Operation> values = <Request_Operation>[
    UNSPECIFIED,
    GET,
    SET,
    CLEAR,
  ];

  static final $core.List<Request_Operation?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Request_Operation? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Request_Operation._(super.value, super.name);
}

class Response_Status extends $pb.ProtobufEnum {
  static const Response_Status UNSPECIFIED =
      Response_Status._(0, _omitEnumNames ? '' : 'UNSPECIFIED');
  static const Response_Status OK =
      Response_Status._(1, _omitEnumNames ? '' : 'OK');
  static const Response_Status INVALID_ARGUMENT =
      Response_Status._(2, _omitEnumNames ? '' : 'INVALID_ARGUMENT');
  static const Response_Status STORAGE_ERROR =
      Response_Status._(3, _omitEnumNames ? '' : 'STORAGE_ERROR');

  static const $core.List<Response_Status> values = <Response_Status>[
    UNSPECIFIED,
    OK,
    INVALID_ARGUMENT,
    STORAGE_ERROR,
  ];

  static final $core.List<Response_Status?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static Response_Status? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Response_Status._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
