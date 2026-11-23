import 'dart:convert';

import '../core/proto/channel_names.dart';
import '../core/proto/generated/meshtastic/mqtt.pb.dart' show MapReport;
import '../core/proto/mesh.dart';
import 'database.dart';

/// Ручной отчёт передаёт координаты с той же точностью, что и штатный MQTT
/// MapReport по умолчанию. Координаты округляются до центра ячейки.
MapReport buildMapReport({
  required Node node,
  required User user,
  required Config_LoRaConfig lora,
  required Iterable<MeshChannel> channels,
  required int onlineLocalNodes,
}) {
  const precision = 14;
  final presetName = modemPresetName(lora);
  return MapReport(
    longName: _utf8Prefix(user.longName, 24),
    shortName: _utf8Prefix(user.shortName, 4),
    role: user.role,
    hwModel: user.hwModel,
    firmwareVersion: node.firmwareVersion,
    region: lora.region,
    modemPreset: lora.modemPreset,
    hasDefaultChannel:
        lora.usePreset &&
        lora.channelNum == 0 &&
        lora.overrideFrequency == 0 &&
        channels.any((c) {
          final key = c.psk;
          return c.role != Channel_Role.DISABLED.value &&
              (c.name.isEmpty || c.name == presetName) &&
              key != null &&
              key.length == 1 &&
              key.single == 1;
        }),
    latitudeI: _cellCenter(node.latitude!, precision),
    longitudeI: _cellCenter(node.longitude!, precision),
    altitude: node.altitude,
    positionPrecision: precision,
    numOnlineLocalNodes: onlineLocalNodes,
    hasOptedReportLocation: true,
  );
}

int _cellCenter(double degrees, int precision) {
  final coordinate = (degrees * 1e7).round();
  final size = 1 << (32 - precision);
  return coordinate - (coordinate % size) + (size ~/ 2);
}

String _utf8Prefix(String text, int maxBytes) {
  final bytes = utf8.encode(text);
  var end = maxBytes;
  if (bytes.length <= end) return text;
  while ((bytes[end] & 0xc0) == 0x80) {
    end--;
  }
  return utf8.decode(bytes.sublist(0, end));
}
