import 'package:flutter/services.dart';
import 'package:lockbox/core/channels/models/app_info.dart';
import 'package:lockbox/core/channels/models/lock_event.dart';

/// Typed wrapper around the platform MethodChannel and EventChannel
/// that communicates with the Kotlin native layer.
///
/// Channel names:
///   MethodChannel → `com.lockbox/methods`
///   EventChannel  → `com.lockbox/events`
class LockboxChannel {
  LockboxChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ??
            const MethodChannel('com.lockbox/methods'),
        _event = eventChannel ??
            const EventChannel('com.lockbox/events');

  final MethodChannel _method;
  final EventChannel _event;

  // ─────────────────────── Methods ───────────────────────

  /// Returns every installed app on the device.
  /// Optionally filter out system apps with [includeSystemApps].
  Future<List<AppInfo>> getInstalledApps({
    bool includeSystemApps = false,
  }) async {
    final List<dynamic>? raw = await _method.invokeMethod(
      'getInstalledApps',
      {'includeSystemApps': includeSystemApps},
    );
    if (raw == null) return [];
    return raw
        .cast<Map<dynamic, dynamic>>()
        .map((e) => AppInfo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Persists the list of package names that should be locked.
  /// The native accessibility service reads this list to intercept launches.
  Future<bool> setLockedApps(List<String> packageNames) async {
    final result = await _method.invokeMethod<bool>(
      'setLockedApps',
      {'packageNames': packageNames},
    );
    return result ?? false;
  }

  /// Returns `true` when the app's accessibility service is enabled.
  Future<bool> isAccessibilityEnabled() async {
    final result = await _method.invokeMethod<bool>('isAccessibilityEnabled');
    return result ?? false;
  }

  /// Opens the system Accessibility settings page.
  Future<void> openAccessibilitySettings() async {
    await _method.invokeMethod<void>('openAccessibilitySettings');
  }

  /// Returns `true` when notification listener access has been granted.
  Future<bool> isNotificationAccessEnabled() async {
    final result =
        await _method.invokeMethod<bool>('isNotificationAccessEnabled');
    return result ?? false;
  }

  /// Opens the system Notification Listener Access settings page.
  Future<void> openNotificationSettings() async {
    await _method.invokeMethod<void>('openNotificationSettings');
  }

  /// Returns `true` if overlay (SYSTEM_ALERT_WINDOW / appear on top) permission is granted.
  Future<bool> isOverlayPermissionGranted() async {
    final result =
        await _method.invokeMethod<bool>('isOverlayPermissionGranted');
    return result ?? false;
  }

  /// Opens system "Appear on top" / Overlay permission settings.
  Future<void> openOverlaySettings() async {
    await _method.invokeMethod<void>('openOverlaySettings');
  }

  /// Returns `true` if the app is exempt from battery optimizations.
  Future<bool> isBatteryOptimizationIgnored() async {
    final result =
        await _method.invokeMethod<bool>('isBatteryOptimizationIgnored');
    return result ?? false;
  }

  /// Requests battery optimization exemption or opens battery settings.
  Future<void> requestBatteryOptimization() async {
    await _method.invokeMethod<void>('requestBatteryOptimization');
  }

  /// Returns `true` if running on a Samsung device (for specialized One UI guidance).
  Future<bool> isSamsungDevice() async {
    final result = await _method.invokeMethod<bool>('isSamsungDevice');
    return result ?? false;
  }

  /// Sets the re-lock timeout policy.
  ///
  /// [mode] must be one of `immediate`, `screen_off`, or `timed`.
  /// When [mode] is `timed`, [minutes] controls the unlock window.
  Future<bool> setRelockPolicy({
    required RelockMode mode,
    int minutes = 1,
  }) async {
    final result = await _method.invokeMethod<bool>(
      'setRelockPolicy',
      {
        'mode': mode.name.toUpperCase(),
        'minutes': minutes,
      },
    );
    return result ?? false;
  }

  /// Returns the current re-lock timeout policy.
  Future<RelockPolicy> getRelockPolicy() async {
    final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
      'getRelockPolicy',
    );
    if (raw == null) {
      return const RelockPolicy(mode: RelockMode.immediate, minutes: 1);
    }
    final map = Map<String, dynamic>.from(raw);
    return RelockPolicy.fromMap(map);
  }

  // ─────────────────── Event Stream ──────────────────────

  /// Continuous stream of [LockEvent]s pushed from the native
  /// accessibility / usage-stats service.
  Stream<LockEvent> get lockEvents {
    return _event.receiveBroadcastStream().map((dynamic raw) {
      final map = Map<String, dynamic>.from(raw as Map);
      return LockEvent.fromMap(map);
    });
  }
}

// ──────────────────── Re-lock policy models ────────────────

enum RelockMode {
  immediate,
  screenOff,
  timed;

  /// Convert from the Kotlin enum name (e.g. "SCREEN_OFF").
  static RelockMode fromNative(String value) {
    switch (value.toUpperCase()) {
      case 'IMMEDIATE':
        return RelockMode.immediate;
      case 'SCREEN_OFF':
        return RelockMode.screenOff;
      case 'TIMED':
        return RelockMode.timed;
      default:
        return RelockMode.immediate;
    }
  }

  /// Convert to the Kotlin enum name.
  String toNative() {
    switch (this) {
      case RelockMode.immediate:
        return 'IMMEDIATE';
      case RelockMode.screenOff:
        return 'SCREEN_OFF';
      case RelockMode.timed:
        return 'TIMED';
    }
  }
}

class RelockPolicy {
  final RelockMode mode;
  final int minutes;

  const RelockPolicy({required this.mode, required this.minutes});

  factory RelockPolicy.fromMap(Map<String, dynamic> map) {
    return RelockPolicy(
      mode: RelockMode.fromNative(map['mode'] as String? ?? 'IMMEDIATE'),
      minutes: map['minutes'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': mode.toNative(),
        'minutes': minutes,
      };

  @override
  String toString() => 'RelockPolicy($mode, ${minutes}min)';
}
