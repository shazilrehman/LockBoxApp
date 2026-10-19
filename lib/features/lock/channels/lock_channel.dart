import 'package:flutter/services.dart';

/// Data pushed from Kotlin when [LockActivity] attaches to the engine.
class LockScreenInfo {
  final String packageName;
  final String appName;
  final Uint8List? iconBytes;

  const LockScreenInfo({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });

  factory LockScreenInfo.fromMap(Map<String, dynamic> map) {
    return LockScreenInfo(
      packageName: map['packageName'] as String? ?? '',
      appName: map['appName'] as String? ?? '',
      iconBytes: map['iconBytes'] as Uint8List?,
    );
  }
}

/// MethodChannel bridge between the lock-screen Dart isolate and Kotlin.
///
/// Channel name: `com.lockbox/lock`
///
/// ```
/// Kotlin → Dart:  showLockScreen({packageName, appName, iconBytes})
/// Dart → Kotlin:  unlockSuccess() | goHome() | triggerBiometric() | reportFailedAttempt()
/// ```
class LockChannel {
  static const MethodChannel _channel = MethodChannel('com.lockbox/lock');

  /// Register the Kotlin→Dart handler.
  /// [onShowLockScreen] fires every time a new lock event arrives.
  static void init({
    required void Function(LockScreenInfo info) onShowLockScreen,
  }) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'showLockScreen') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        onShowLockScreen(LockScreenInfo.fromMap(args));
      }
    });
  }

  /// Tell Kotlin the user authenticated successfully.
  static Future<void> unlockSuccess() async {
    await _channel.invokeMethod('unlockSuccess');
  }

  /// Tell Kotlin to send the user to the home screen.
  static Future<void> goHome() async {
    await _channel.invokeMethod('goHome');
  }

  /// Ask Kotlin to show the system BiometricPrompt.
  /// Returns `true` on success, `false` on error/cancel.
  static Future<bool> triggerBiometric() async {
    final result = await _channel.invokeMethod<bool>('triggerBiometric');
    return result ?? false;
  }

  /// Record a wrong PIN in the intruder log. Kotlin decides whether a photo
  /// is taken (requires explicit consent + CAMERA permission). Never throws.
  static Future<void> reportFailedAttempt() async {
    try {
      await _channel.invokeMethod('reportFailedAttempt');
    } on PlatformException {
      // Logging must never block the lock screen.
    } on MissingPluginException {
      // Running outside LockActivity (tests / previews).
    }
  }
}
