import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lockbox/core/services/local_auth_service.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/auth/domain/auth_models.dart';
import 'package:lockbox/features/auth/services/pbkdf2.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  final localAuth = ref.watch(localAuthServiceProvider);
  return AuthService(storage: storage, localAuth: localAuth);
});

/// Core authentication service managing PBKDF2 PIN setup/verification,
/// biometric-only authentication, lockout progression, and secure storage persistence.
class AuthService {
  static const String keyPinHash = 'lockbox_pin_hash';
  static const String keyPinSalt = 'lockbox_pin_salt';
  static const String keyPinIterations = 'lockbox_pin_iterations';
  static const String keyFailedAttempts = 'lockbox_failed_attempts';
  static const String keyLockoutUntil = 'lockbox_lockout_until';

  static const int defaultIterations = 100000;
  static const int lockoutThreshold = 5;

  final SecureStorageService storage;
  final LocalAuthService localAuth;
  final Pbkdf2 _pbkdf2;

  AuthService({
    required this.storage,
    required this.localAuth,
    int iterations = defaultIterations,
  }) : _pbkdf2 = Pbkdf2(iterations: iterations);

  // ── PIN Setup ──────────────────────────────────────────

  /// Derives and securely stores a new PIN using PBKDF2 HMAC-SHA256 with
  /// a cryptographically random per-user salt.
  Future<void> setupPin(String pin) async {
    if (pin.trim().isEmpty) {
      throw ArgumentError('PIN cannot be empty');
    }

    final salt = Pbkdf2.generateSalt(16);
    final derived = _pbkdf2.derive(pin, salt);

    await Future.wait([
      storage.write(key: keyPinHash, value: Pbkdf2.bytesToHex(derived)),
      storage.write(key: keyPinSalt, value: Pbkdf2.bytesToHex(salt)),
      storage.write(
        key: keyPinIterations,
        value: _pbkdf2.iterations.toString(),
      ),
      resetLockout(),
    ]);
  }

  /// Whether a PIN has been initialized in secure storage.
  Future<bool> hasPin() async {
    final hash = await storage.read(key: keyPinHash);
    final salt = await storage.read(key: keyPinSalt);
    return hash != null &&
        hash.isNotEmpty &&
        salt != null &&
        salt.isNotEmpty;
  }

  /// Deletes the stored PIN and clears lockout tracking.
  Future<void> clearPin() async {
    await Future.wait([
      storage.delete(key: keyPinHash),
      storage.delete(key: keyPinSalt),
      storage.delete(key: keyPinIterations),
      resetLockout(),
    ]);
  }

  // ── PIN Verification ───────────────────────────────────

  /// Verifies [pin] against the stored PBKDF2 hash using constant-time comparison.
  /// Enforces lockout after [lockoutThreshold] failures with increasing delays.
  Future<AuthResult> verifyPin(String pin) async {
    // 1. Check if currently locked out
    final lockout = await getLockoutStatus();
    if (lockout.isLockedOut) {
      return AuthResult.lockedOut(
        remainingLockout: lockout.remainingLockout,
      );
    }

    // 2. Read credentials
    final storedHash = await storage.read(key: keyPinHash);
    final storedSaltHex = await storage.read(key: keyPinSalt);
    final iterationsStr = await storage.read(key: keyPinIterations);

    if (storedHash == null || storedSaltHex == null) {
      return AuthResult.noPinConfigured();
    }

    // 3. Compute derived key with stored salt & iterations
    final salt = Pbkdf2.hexToBytes(storedSaltHex);
    final iterations = int.tryParse(iterationsStr ?? '') ?? _pbkdf2.iterations;
    final pbkdf2 = (iterations == _pbkdf2.iterations)
        ? _pbkdf2
        : Pbkdf2(iterations: iterations);

    final computedKey = pbkdf2.derive(pin, salt);
    final computedHex = Pbkdf2.bytesToHex(computedKey);

    // 4. Constant-time equality check
    final matches = Pbkdf2.constantTimeEquals(computedHex, storedHash);

    if (matches) {
      await resetLockout();
      return AuthResult.success();
    }

    // 5. Handle failure & calculate tiered lockout delay
    return await _recordFailedAttempt(lockout.failedAttempts);
  }

  // ── Biometric Authentication ───────────────────────────

  /// Prompts for biometrics using `biometricOnly: true`.
  /// If biometrics is unavailable or fails, returns a failure result
  /// indicating that the user should fall back to PIN.
  Future<AuthResult> authenticateBiometrics({
    String reason = 'Authenticate to unlock Lockbox',
  }) async {
    final lockout = await getLockoutStatus();
    if (lockout.isLockedOut) {
      return AuthResult.lockedOut(remainingLockout: lockout.remainingLockout);
    }

    final hasBiometrics = await localAuth.hasEnrolledBiometrics();
    if (!hasBiometrics) {
      return AuthResult.biometricUnavailable();
    }

    final success = await localAuth.authenticateBiometricOnly(reason: reason);
    if (success) {
      await resetLockout();
      return AuthResult.success();
    }

    return AuthResult.biometricFailed();
  }

  // ── Lockout Progression ────────────────────────────────

  /// Computes lockout delay based on number of consecutive failures:
  /// - 5th failure: 30 seconds
  /// - 6th failure: 60 seconds (1 min)
  /// - 7th failure: 120 seconds (2 min)
  /// - 8th failure: 300 seconds (5 min)
  /// - 9th+ failure: 900 seconds (15 min)
  Duration calculateLockoutDuration(int failedAttempts) {
    if (failedAttempts < lockoutThreshold) return Duration.zero;
    final excess = failedAttempts - lockoutThreshold;
    switch (excess) {
      case 0:
        return const Duration(seconds: 30);
      case 1:
        return const Duration(seconds: 60);
      case 2:
        return const Duration(seconds: 120);
      case 3:
        return const Duration(seconds: 300);
      default:
        return const Duration(seconds: 900);
    }
  }

  Future<AuthResult> _recordFailedAttempt(int currentFailures) async {
    final newFailures = currentFailures + 1;
    await storage.write(
      key: keyFailedAttempts,
      value: newFailures.toString(),
    );

    if (newFailures >= lockoutThreshold) {
      final delay = calculateLockoutDuration(newFailures);
      final lockoutUntil = DateTime.now().add(delay).millisecondsSinceEpoch;
      await storage.write(
        key: keyLockoutUntil,
        value: lockoutUntil.toString(),
      );
      return AuthResult.lockedOut(remainingLockout: delay);
    }

    final remaining = lockoutThreshold - newFailures;
    return AuthResult.wrongPin(remainingAttempts: remaining);
  }

  /// Returns current lockout status. Automatically clears expired lockout.
  Future<LockoutStatus> getLockoutStatus() async {
    final attemptsStr = await storage.read(key: keyFailedAttempts);
    final lockoutUntilStr = await storage.read(key: keyLockoutUntil);

    final attempts = int.tryParse(attemptsStr ?? '') ?? 0;
    final lockoutEpoch = int.tryParse(lockoutUntilStr ?? '');

    if (lockoutEpoch != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final diffMs = lockoutEpoch - now;

      if (diffMs > 0) {
        return LockoutStatus(
          isLockedOut: true,
          failedAttempts: attempts,
          remainingLockout: Duration(milliseconds: diffMs),
          lockoutUntil: DateTime.fromMillisecondsSinceEpoch(lockoutEpoch),
        );
      } else {
        // Lockout expired; clear timestamp so retry is allowed
        await storage.delete(key: keyLockoutUntil);
      }
    }

    return LockoutStatus(
      isLockedOut: false,
      failedAttempts: attempts,
    );
  }

  /// Clears failed attempts and active lockout.
  Future<void> resetLockout() async {
    await Future.wait([
      storage.delete(key: keyFailedAttempts),
      storage.delete(key: keyLockoutUntil),
    ]);
  }
}
