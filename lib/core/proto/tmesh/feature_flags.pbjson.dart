// This is a generated file - do not edit.
//
// Generated from feature_flags.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use envelopeDescriptor instead')
const Envelope$json = {
  '1': 'Envelope',
  '2': [
    {
      '1': 'request',
      '3': 50000,
      '4': 1,
      '5': 11,
      '6': '.tmesh.Request',
      '9': 0,
      '10': 'request'
    },
    {
      '1': 'response',
      '3': 50001,
      '4': 1,
      '5': 11,
      '6': '.tmesh.Response',
      '9': 0,
      '10': 'response'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `Envelope`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List envelopeDescriptor = $convert.base64Decode(
    'CghFbnZlbG9wZRIsCgdyZXF1ZXN0GNCGAyABKAsyDi50bWVzaC5SZXF1ZXN0SABSB3JlcXVlc3'
    'QSLwoIcmVzcG9uc2UY0YYDIAEoCzIPLnRtZXNoLlJlc3BvbnNlSABSCHJlc3BvbnNlQgkKB3Bh'
    'eWxvYWQ=');

@$core.Deprecated('Use featureFlagsConfigDescriptor instead')
const FeatureFlagsConfig$json = {
  '1': 'FeatureFlagsConfig',
  '2': [
    {
      '1': 'restricted_routing_mode',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.tmesh.FeatureFlagsConfig.RestrictedRoutingMode',
      '10': 'restrictedRoutingMode'
    },
    {
      '1': 'restricted_routing_disallows_private_text',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'restrictedRoutingDisallowsPrivateText'
    },
    {
      '1': 'hop_decrement_mode',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.tmesh.FeatureFlagsConfig.HopDecrementMode',
      '10': 'hopDecrementMode'
    },
    {
      '1': 'force_next_hop_mode',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.tmesh.FeatureFlagsConfig.ForceNextHopMode',
      '10': 'forceNextHopMode'
    },
    {
      '1': 'force_next_hop_relay',
      '3': 5,
      '4': 1,
      '5': 13,
      '10': 'forceNextHopRelay'
    },
    {
      '1': 'favorite_router_mode',
      '3': 6,
      '4': 1,
      '5': 14,
      '6': '.tmesh.FeatureFlagsConfig.FavoriteRouterMode',
      '10': 'favoriteRouterMode'
    },
    {
      '1': 'favorite_router_relay',
      '3': 7,
      '4': 1,
      '5': 13,
      '10': 'favoriteRouterRelay'
    },
  ],
  '4': [
    FeatureFlagsConfig_RestrictedRoutingMode$json,
    FeatureFlagsConfig_HopDecrementMode$json,
    FeatureFlagsConfig_ForceNextHopMode$json,
    FeatureFlagsConfig_FavoriteRouterMode$json
  ],
};

@$core.Deprecated('Use featureFlagsConfigDescriptor instead')
const FeatureFlagsConfig_RestrictedRoutingMode$json = {
  '1': 'RestrictedRoutingMode',
  '2': [
    {'1': 'STANDARD_CORE_PORTS', '2': 0},
    {'1': 'TEXT_ALL_AND_ADMIN', '2': 1},
    {'1': 'TEXT_ALL_ADMIN_AND_ROUTING', '2': 2},
    {'1': 'TEXT_ALL_ADMIN_ROUTING_AND_TRACEROUTE', '2': 3},
    {'1': 'TEXT_ALL_NODEINFO_ADMIN_AND_ROUTING', '2': 4},
    {'1': 'TEXT_ALL_NODEINFO_ADMIN_ROUTING_AND_TRACEROUTE', '2': 5},
  ],
};

@$core.Deprecated('Use featureFlagsConfigDescriptor instead')
const FeatureFlagsConfig_HopDecrementMode$json = {
  '1': 'HopDecrementMode',
  '2': [
    {'1': 'STANDARD_FAVORITE_ROUTER_BEHAVIOR', '2': 0},
    {'1': 'PRESERVE_AFTER_ANY_FAVORITE_RELAY', '2': 1},
    {'1': 'DECREMENT_FIRST_HOP_ONLY', '2': 2},
  ],
};

@$core.Deprecated('Use featureFlagsConfigDescriptor instead')
const FeatureFlagsConfig_ForceNextHopMode$json = {
  '1': 'ForceNextHopMode',
  '2': [
    {'1': 'FORCE_NEXT_HOP_DISABLED', '2': 0},
    {'1': 'LOCAL_PACKETS_WITH_FLOODING_FALLBACK', '2': 1},
    {'1': 'LOCAL_AND_RELAYED_PACKETS_WITH_FLOODING_FALLBACK', '2': 2},
    {'1': 'ALL_PACKETS_WITHOUT_FORCED_FLOODING_FALLBACK', '2': 3},
  ],
};

@$core.Deprecated('Use featureFlagsConfigDescriptor instead')
const FeatureFlagsConfig_FavoriteRouterMode$json = {
  '1': 'FavoriteRouterMode',
  '2': [
    {'1': 'FAVORITE_ROUTER_DISABLED', '2': 0},
    {'1': 'PRESERVE_HOPS_ONLY', '2': 1},
    {'1': 'PRESERVE_HOPS_AND_RELAY', '2': 2},
  ],
};

/// Descriptor for `FeatureFlagsConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List featureFlagsConfigDescriptor = $convert.base64Decode(
    'ChJGZWF0dXJlRmxhZ3NDb25maWcSZwoXcmVzdHJpY3RlZF9yb3V0aW5nX21vZGUYASABKA4yLy'
    '50bWVzaC5GZWF0dXJlRmxhZ3NDb25maWcuUmVzdHJpY3RlZFJvdXRpbmdNb2RlUhVyZXN0cmlj'
    'dGVkUm91dGluZ01vZGUSWAopcmVzdHJpY3RlZF9yb3V0aW5nX2Rpc2FsbG93c19wcml2YXRlX3'
    'RleHQYAiABKAhSJXJlc3RyaWN0ZWRSb3V0aW5nRGlzYWxsb3dzUHJpdmF0ZVRleHQSWAoSaG9w'
    'X2RlY3JlbWVudF9tb2RlGAMgASgOMioudG1lc2guRmVhdHVyZUZsYWdzQ29uZmlnLkhvcERlY3'
    'JlbWVudE1vZGVSEGhvcERlY3JlbWVudE1vZGUSWQoTZm9yY2VfbmV4dF9ob3BfbW9kZRgEIAEo'
    'DjIqLnRtZXNoLkZlYXR1cmVGbGFnc0NvbmZpZy5Gb3JjZU5leHRIb3BNb2RlUhBmb3JjZU5leH'
    'RIb3BNb2RlEi8KFGZvcmNlX25leHRfaG9wX3JlbGF5GAUgASgNUhFmb3JjZU5leHRIb3BSZWxh'
    'eRJeChRmYXZvcml0ZV9yb3V0ZXJfbW9kZRgGIAEoDjIsLnRtZXNoLkZlYXR1cmVGbGFnc0Nvbm'
    'ZpZy5GYXZvcml0ZVJvdXRlck1vZGVSEmZhdm9yaXRlUm91dGVyTW9kZRIyChVmYXZvcml0ZV9y'
    'b3V0ZXJfcmVsYXkYByABKA1SE2Zhdm9yaXRlUm91dGVyUmVsYXki8AEKFVJlc3RyaWN0ZWRSb3'
    'V0aW5nTW9kZRIXChNTVEFOREFSRF9DT1JFX1BPUlRTEAASFgoSVEVYVF9BTExfQU5EX0FETUlO'
    'EAESHgoaVEVYVF9BTExfQURNSU5fQU5EX1JPVVRJTkcQAhIpCiVURVhUX0FMTF9BRE1JTl9ST1'
    'VUSU5HX0FORF9UUkFDRVJPVVRFEAMSJwojVEVYVF9BTExfTk9ERUlORk9fQURNSU5fQU5EX1JP'
    'VVRJTkcQBBIyCi5URVhUX0FMTF9OT0RFSU5GT19BRE1JTl9ST1VUSU5HX0FORF9UUkFDRVJPVV'
    'RFEAUifgoQSG9wRGVjcmVtZW50TW9kZRIlCiFTVEFOREFSRF9GQVZPUklURV9ST1VURVJfQkVI'
    'QVZJT1IQABIlCiFQUkVTRVJWRV9BRlRFUl9BTllfRkFWT1JJVEVfUkVMQVkQARIcChhERUNSRU'
    '1FTlRfRklSU1RfSE9QX09OTFkQAiLBAQoQRm9yY2VOZXh0SG9wTW9kZRIbChdGT1JDRV9ORVhU'
    'X0hPUF9ESVNBQkxFRBAAEigKJExPQ0FMX1BBQ0tFVFNfV0lUSF9GTE9PRElOR19GQUxMQkFDSx'
    'ABEjQKMExPQ0FMX0FORF9SRUxBWUVEX1BBQ0tFVFNfV0lUSF9GTE9PRElOR19GQUxMQkFDSxAC'
    'EjAKLEFMTF9QQUNLRVRTX1dJVEhPVVRfRk9SQ0VEX0ZMT09ESU5HX0ZBTExCQUNLEAMiZwoSRm'
    'F2b3JpdGVSb3V0ZXJNb2RlEhwKGEZBVk9SSVRFX1JPVVRFUl9ESVNBQkxFRBAAEhYKElBSRVNF'
    'UlZFX0hPUFNfT05MWRABEhsKF1BSRVNFUlZFX0hPUFNfQU5EX1JFTEFZEAI=');

@$core.Deprecated('Use requestDescriptor instead')
const Request$json = {
  '1': 'Request',
  '2': [
    {
      '1': 'operation',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.tmesh.Request.Operation',
      '10': 'operation'
    },
    {
      '1': 'config',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.tmesh.FeatureFlagsConfig',
      '10': 'config'
    },
  ],
  '4': [Request_Operation$json],
};

@$core.Deprecated('Use requestDescriptor instead')
const Request_Operation$json = {
  '1': 'Operation',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'GET', '2': 1},
    {'1': 'SET', '2': 2},
    {'1': 'CLEAR', '2': 3},
  ],
};

/// Descriptor for `Request`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List requestDescriptor = $convert.base64Decode(
    'CgdSZXF1ZXN0EjYKCW9wZXJhdGlvbhgBIAEoDjIYLnRtZXNoLlJlcXVlc3QuT3BlcmF0aW9uUg'
    'lvcGVyYXRpb24SMQoGY29uZmlnGAIgASgLMhkudG1lc2guRmVhdHVyZUZsYWdzQ29uZmlnUgZj'
    'b25maWciOQoJT3BlcmF0aW9uEg8KC1VOU1BFQ0lGSUVEEAASBwoDR0VUEAESBwoDU0VUEAISCQ'
    'oFQ0xFQVIQAw==');

@$core.Deprecated('Use responseDescriptor instead')
const Response$json = {
  '1': 'Response',
  '2': [
    {
      '1': 'status',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.tmesh.Response.Status',
      '10': 'status'
    },
    {
      '1': 'config',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.tmesh.FeatureFlagsConfig',
      '10': 'config'
    },
  ],
  '4': [Response_Status$json],
};

@$core.Deprecated('Use responseDescriptor instead')
const Response_Status$json = {
  '1': 'Status',
  '2': [
    {'1': 'UNSPECIFIED', '2': 0},
    {'1': 'OK', '2': 1},
    {'1': 'INVALID_ARGUMENT', '2': 2},
    {'1': 'STORAGE_ERROR', '2': 3},
  ],
};

/// Descriptor for `Response`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List responseDescriptor = $convert.base64Decode(
    'CghSZXNwb25zZRIuCgZzdGF0dXMYASABKA4yFi50bWVzaC5SZXNwb25zZS5TdGF0dXNSBnN0YX'
    'R1cxIxCgZjb25maWcYAiABKAsyGS50bWVzaC5GZWF0dXJlRmxhZ3NDb25maWdSBmNvbmZpZyJK'
    'CgZTdGF0dXMSDwoLVU5TUEVDSUZJRUQQABIGCgJPSxABEhQKEElOVkFMSURfQVJHVU1FTlQQAh'
    'IRCg1TVE9SQUdFX0VSUk9SEAM=');

@$core.Deprecated('Use storeDescriptor instead')
const Store$json = {
  '1': 'Store',
  '2': [
    {
      '1': 'config',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.tmesh.FeatureFlagsConfig',
      '10': 'config'
    },
    {'1': 'format_version', '3': 2, '4': 1, '5': 13, '10': 'formatVersion'},
  ],
};

/// Descriptor for `Store`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storeDescriptor = $convert.base64Decode(
    'CgVTdG9yZRIxCgZjb25maWcYASABKAsyGS50bWVzaC5GZWF0dXJlRmxhZ3NDb25maWdSBmNvbm'
    'ZpZxIlCg5mb3JtYXRfdmVyc2lvbhgCIAEoDVINZm9ybWF0VmVyc2lvbg==');
