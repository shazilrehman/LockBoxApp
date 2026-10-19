import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

final localAuthServiceProvider = Provider<LocalAuthService>((ref) {
  return LocalAuthService();
});

class LocalAuthService {
  final LocalAuthentication _auth;

  LocalAuthService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Returns true when hardware supports biometrics.
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  /// Returns true when biometrics can be checked on this device.
  Future<bool> canCheckBiometrics() => _auth.canCheckBiometrics;

  /// Returns the list of enrolled biometric types (e.g. fingerprint, face, weak).
  Future<List<BiometricType>> availableBiometrics() =>
      _auth.getAvailableBiometrics();

  /// Whether any biometric credentials are enrolled.
  Future<bool> hasEnrolledBiometrics() async {
    try {
      final list = await availableBiometrics();
      return list.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  /// Triggers the biometric prompt strictly requiring biometric authentication
  /// ([biometricOnly: true]). Device PIN/Pattern will NOT satisfy this check,
  /// ensuring security control remains with Lockbox's own PBKDF2 PIN.
  ///
  /// Uses [AndroidAuthMessages] for localized prompt text and seamless PIN fallback.
  Future<bool> authenticateBiometricOnly({
    String reason = 'Authenticate to unlock',
  }) async {
    try {
      final canCheck = await canCheckBiometrics();
      final isSupported = await isDeviceSupported();
      if (!canCheck && !isSupported) return false;

      return await _auth.authenticate(
        localizedReason: reason,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Lockbox Authentication',
            biometricHint: 'Verify your fingerprint or face',
            cancelButton: 'Use PIN',
          ),
        ],
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }

  /// Fallback or general authentication with credential support if required.
  Future<bool> authenticate({String reason = 'Authenticate to continue'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
