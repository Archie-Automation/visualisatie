import 'fireplace_status.dart';
import 'fireplace_virtual.dart';
import 'media_api.dart';
import 'models.dart';

bool deviceLightIsOn(Device d, Map<String, dynamic> busValues) {
  switch (d.type) {
    case DeviceType.lightSwitch:
    case DeviceType.lightDimmer:
      final swGa = d.ga['switch_status'] ?? d.ga['switch'];
      if (swGa == null) return false;
      final v = busValues[swGa];
      return v == true || v == 1;
    case DeviceType.rgbwWw:
      final ga = d.ga['on'];
      if (ga == null) return false;
      final v = busValues[ga];
      return v == true || v == 1;
    default:
      return false;
  }
}

bool deviceHeaterIsActive(Device d, Map<String, dynamic> busValues) {
  if (d.type != DeviceType.universal) return false;
  final cfg = d.raw['universal'] as Map<String, dynamic>?;
  if (cfg == null) return false;
  if ((cfg['icon'] as String?) != 'heater') return false;
  final buttons =
      (cfg['buttons'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  for (final b in buttons) {
    final ga = b['statusGa'] as String?;
    if (ga == null) continue;
    final v = busValues[ga];
    if (v == true || v == 1) return true;
  }
  return false;
}

bool deviceFireplaceIsOn(
  Device d,
  Map<String, dynamic> busValues,
  Map<String, bool> fireplaceVirtual,
) {
  if (d.type != DeviceType.fireplace) return false;
  final cfg = d.raw['fireplace'] as Map<String, dynamic>?;
  if (cfg == null) return false;
  final workingOn = fireplaceWorkingOn(cfg, busValues);
  if (workingOn != null) return workingOn;
  final onOff = cfg['onOff'];
  if (onOff is! Map) return false;
  final ga = (onOff['statusGa'] ?? onOff['ga']) as String?;
  if (ga == null) return false;
  final busOn = busValues[ga] == true || busValues[ga] == 1;
  final discreteMode =
      cfg['controlMode'] == 'discrete' && cfg['discreteLevel'] != null;
  return FireplaceVirtualStore.resolveOn(
    discreteMode: discreteMode,
    virtual: fireplaceVirtual,
    deviceId: d.id,
    busOn: busOn,
  );
}

bool deviceAcIsOn(Device d, Map<String, dynamic> busValues) {
  if (d.type != DeviceType.ac) return false;
  final cfg = d.raw['ac'] as Map<String, dynamic>?;
  if (cfg == null) return false;
  final onOff = cfg['onOff'];
  if (onOff is! Map) return false;
  final ga = (onOff['statusGa'] ?? onOff['ga']) as String?;
  if (ga == null) return false;
  final v = busValues[ga];
  return v == true || v == 1;
}

bool deviceMediaIsPlaying(Device d, Map<String, MediaState> mediaStates) {
  if (!d.type.isMedia) return false;
  final ms = mediaStates[d.id];
  if (ms != null && ms.transport.isActive) return true;
  if (ms != null && ms.groupRole == MediaGroupRole.member) {
    final coordId = ms.groupCoordinatorId;
    if (coordId == null) return false;
    final coord = mediaStates[coordId];
    return coord != null && coord.transport.isActive;
  }
  return false;
}

/// Same "aan"-criteria as the dashboard header status icons, scoped to a
/// house system. Unknown slugs are treated as not-active so a query flag
/// cannot accidentally dump every device.
bool isHouseActivityDeviceOn({
  required String systemSlug,
  required Device device,
  required Map<String, dynamic> busValues,
  required Map<String, MediaState> mediaStates,
  required Map<String, bool> fireplaceVirtual,
}) {
  switch (systemSlug) {
    case 'verlichting':
      return deviceLightIsOn(device, busValues);
    case 'openhaard':
      return deviceFireplaceIsOn(device, busValues, fireplaceVirtual);
    case 'audio':
      return deviceMediaIsPlaying(device, mediaStates);
    case 'klimaat':
      return deviceAcIsOn(device, busValues);
    case 'diverse':
      return deviceHeaterIsActive(device, busValues);
    default:
      return false;
  }
}
