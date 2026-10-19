import 'package:flutter_test/flutter_test.dart';
import 'package:lockbox/core/channels/lockbox_channel.dart';
import 'package:lockbox/core/channels/models/app_info.dart';
import 'package:lockbox/core/channels/models/lock_event.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/onboarding/domain/permission_state.dart';
import 'package:lockbox/features/onboarding/providers/onboarding_provider.dart';

class FakeLockboxChannel implements LockboxChannel {
  bool accessibility = false;
  bool notification = false;
  bool overlay = false;
  bool battery = false;
  bool samsung = false;

  @override
  Future<bool> isAccessibilityEnabled() async => accessibility;

  @override
  Future<void> openAccessibilitySettings() async {}

  @override
  Future<bool> isNotificationAccessEnabled() async => notification;

  @override
  Future<void> openNotificationSettings() async {}

  @override
  Future<bool> isOverlayPermissionGranted() async => overlay;

  @override
  Future<void> openOverlaySettings() async {}

  @override
  Future<bool> isBatteryOptimizationIgnored() async => battery;

  @override
  Future<void> requestBatteryOptimization() async {}

  @override
  Future<bool> isSamsungDevice() async => samsung;

  @override
  Future<List<AppInfo>> getInstalledApps({bool includeSystemApps = false}) async => [];

  @override
  Future<bool> setLockedApps(List<String> packageNames) async => true;

  @override
  Future<bool> setRelockPolicy({required RelockMode mode, int minutes = 1}) async => true;

  @override
  Future<RelockPolicy> getRelockPolicy() async =>
      const RelockPolicy(mode: RelockMode.immediate, minutes: 1);

  @override
  Stream<LockEvent> get lockEvents => const Stream.empty();
}

class FakeSecureStorage implements SecureStorageService {
  final Map<String, String> _map = {};

  @override
  Future<void> write({required String key, required String value}) async {
    _map[key] = value;
  }

  @override
  Future<String?> read({required String key}) async => _map[key];

  @override
  Future<void> delete({required String key}) async {
    _map.remove(key);
  }

  @override
  Future<Map<String, String>> readAll() async => Map.unmodifiable(_map);

  @override
  Future<void> deleteAll() async {
    _map.clear();
  }
}

void main() {
  group('OnboardingPermissionState', () {
    test('hasEssentialPermissions requires both accessibility and overlay', () {
      const state1 = OnboardingPermissionState(
        isAccessibilityGranted: true,
        isOverlayGranted: false,
      );
      expect(state1.hasEssentialPermissions, isFalse);

      const state2 = OnboardingPermissionState(
        isAccessibilityGranted: false,
        isOverlayGranted: true,
      );
      expect(state2.hasEssentialPermissions, isFalse);

      const state3 = OnboardingPermissionState(
        isAccessibilityGranted: true,
        isOverlayGranted: true,
      );
      expect(state3.hasEssentialPermissions, isTrue);
    });

    test('grantedCount accurately reflects granted permissions', () {
      const state = OnboardingPermissionState(
        isAccessibilityGranted: true,
        isNotificationGranted: true,
        isOverlayGranted: false,
        isBatteryExemptGranted: true,
      );
      expect(state.grantedCount, equals(3));
      expect(state.hasAllPermissions, isFalse);
    });

    test('essentialGrantedCount ignores optional permissions', () {
      const state = OnboardingPermissionState(
        isAccessibilityGranted: false,
        isNotificationGranted: true,
        isOverlayGranted: true,
        isBatteryExemptGranted: true,
      );
      expect(state.grantedCount, equals(3));
      expect(state.essentialGrantedCount, equals(1));
    });

    test('hasAllPermissions is true when all 4 are granted', () {
      const state = OnboardingPermissionState(
        isAccessibilityGranted: true,
        isNotificationGranted: true,
        isOverlayGranted: true,
        isBatteryExemptGranted: true,
      );
      expect(state.grantedCount, equals(4));
      expect(state.hasAllPermissions, isTrue);
    });
  });

  group('OnboardingNotifier', () {
    late FakeLockboxChannel fakeChannel;
    late FakeSecureStorage fakeStorage;
    late OnboardingNotifier notifier;

    setUp(() {
      fakeChannel = FakeLockboxChannel();
      fakeStorage = FakeSecureStorage();
      notifier = OnboardingNotifier(
        channel: fakeChannel,
        storage: fakeStorage,
      );
    });

    test('queries permissions and updates state', () async {
      fakeChannel.accessibility = true;
      fakeChannel.overlay = true;
      fakeChannel.samsung = true;

      await notifier.checkPermissions();

      expect(notifier.state.isAccessibilityGranted, isTrue);
      expect(notifier.state.isOverlayGranted, isTrue);
      expect(notifier.state.isNotificationGranted, isFalse);
      expect(notifier.state.isSamsungDevice, isTrue);
      expect(notifier.state.hasEssentialPermissions, isTrue);
    });

    test('acceptPlayDisclosure records to storage and updates state', () async {
      expect(notifier.state.isPlayDisclosureAccepted, isFalse);

      await notifier.acceptPlayDisclosure();

      expect(notifier.state.isPlayDisclosureAccepted, isTrue);
      final stored = await fakeStorage.read(
        key: OnboardingNotifier.keyPlayDisclosure,
      );
      expect(stored, equals('true'));
    });

    test('completeOnboarding records completion to storage', () async {
      expect(await notifier.isOnboardingCompleted(), isFalse);

      await notifier.completeOnboarding();

      expect(await notifier.isOnboardingCompleted(), isTrue);
      final stored = await fakeStorage.read(
        key: OnboardingNotifier.keyOnboardingComplete,
      );
      expect(stored, equals('true'));
    });
  });
}
