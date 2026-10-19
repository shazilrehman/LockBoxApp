import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lockbox/features/onboarding/presentation/widgets/live_permission_checklist.dart';
import 'package:lockbox/features/onboarding/presentation/widgets/permission_card.dart';
import 'package:lockbox/features/onboarding/presentation/widgets/play_disclosure_sheet.dart';
import 'package:lockbox/features/onboarding/providers/onboarding_provider.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDisclosure();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-check all permissions automatically when user returns from settings
      ref.read(onboardingProvider.notifier).checkPermissions();
    }
  }

  Future<void> _checkDisclosure() async {
    // Wait for persisted state to load; otherwise the default
    // (not accepted) would re-show the disclosure on every launch.
    await ref.read(onboardingProvider.notifier).checkPermissions();
    if (!mounted) return;
    final state = ref.read(onboardingProvider);
    if (!state.isPlayDisclosureAccepted) {
      final accepted = await PlayDisclosureDialog.show(context);
      if (accepted == true) {
        await ref.read(onboardingProvider.notifier).acceptPlayDisclosure();
      }
    }
  }

  Future<void> _onFinish() async {
    final state = ref.read(onboardingProvider);

    if (!state.hasEssentialPermissions) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Accessibility and Appear on Top are required to lock apps.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!state.hasAllPermissions) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161624),
          title: const Text('Optional Permissions Skipped'),
          content: const Text(
            'Notification hiding and background battery exemption are recommended for full vault protection. Do you want to continue anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Configure Now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (proceed != true) return;
    }

    await ref.read(onboardingProvider.notifier).completeOnboarding();
    if (!mounted) return;
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    final notifier = ref.read(onboardingProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C14),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header Icon & Title ──
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [Colors.indigoAccent, Colors.purpleAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.indigoAccent.withValues(alpha: 0.35),
                                blurRadius: 16,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Setup & Permissions',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            Text(
                              'Activate Lockbox protection',
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ── Samsung Detection Banner ──
                    if (state.isSamsungDevice) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.cyan.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.cyanAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.smartphone_rounded,
                                color: Colors.cyanAccent, size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Samsung Galaxy detected. Tailored One UI step-by-step guides are highlighted below.',
                                style: TextStyle(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Live Status Checklist ──
                    LivePermissionChecklist(state: state),
                    const SizedBox(height: 20),

                    const Text(
                      'Guided Setup Steps',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Step 1: Accessibility Service ──
                    PermissionCard(
                      stepNumber: 1,
                      title: 'Accessibility Service',
                      description:
                          'Detects when locked apps launch in the foreground to present the lock screen.',
                      tag: 'REQUIRED',
                      isTagRequired: true,
                      icon: Icons.accessibility_new_rounded,
                      iconColor: Colors.blueAccent,
                      isGranted: state.isAccessibilityGranted,
                      onGrant: () async {
                        if (!state.isPlayDisclosureAccepted) {
                          final ok = await PlayDisclosureDialog.show(context);
                          if (ok == true) {
                            await notifier.acceptPlayDisclosure();
                            notifier.requestAccessibility();
                          }
                        } else {
                          notifier.requestAccessibility();
                        }
                      },
                      isSamsungDevice: state.isSamsungDevice,
                      samsungSteps: const [
                        'In Accessibility settings, tap "Installed apps" (or "Installed services").',
                        'Locate and tap "Lockbox".',
                        'Turn the toggle switch ON and tap "Allow" on the prompt.',
                      ],
                    ),

                    // ── Step 2: Appear on Top (Overlay) ──
                    PermissionCard(
                      stepNumber: 2,
                      title: 'Appear on Top (Overlay)',
                      description:
                          'Enables Lockbox to smoothly display the lock screen over protected apps.',
                      tag: 'REQUIRED',
                      isTagRequired: true,
                      icon: Icons.layers_rounded,
                      iconColor: Colors.purpleAccent,
                      isGranted: state.isOverlayGranted,
                      onGrant: notifier.requestOverlayPermission,
                      isSamsungDevice: state.isSamsungDevice,
                      samsungSteps: const [
                        'In the "Appear on top" settings list, find "Lockbox".',
                        'Switch the toggle to ON.',
                      ],
                    ),

                    // ── Step 3: Notification Privacy ──
                    PermissionCard(
                      stepNumber: 3,
                      title: 'Notification Privacy',
                      description:
                          'Hides incoming notification previews from locked apps until authenticated.',
                      tag: 'RECOMMENDED',
                      isTagRequired: false,
                      icon: Icons.notifications_active_rounded,
                      iconColor: Colors.amberAccent,
                      isGranted: state.isNotificationGranted,
                      onGrant: notifier.requestNotificationAccess,
                      isSamsungDevice: state.isSamsungDevice,
                      samsungSteps: const [
                        'In Notification access settings, find "Lockbox".',
                        'Turn the switch ON and tap "Allow".',
                      ],
                    ),

                    // ── Step 4: Battery Optimization Exemption ──
                    PermissionCard(
                      stepNumber: 4,
                      title: 'Background Protection',
                      description:
                          'Prevents Android and Samsung Device Care from stopping Lockbox in the background.',
                      tag: 'ESSENTIAL',
                      isTagRequired: false,
                      icon: Icons.battery_charging_full_rounded,
                      iconColor: Colors.greenAccent,
                      isGranted: state.isBatteryExemptGranted,
                      onGrant: notifier.requestBatteryExemption,
                      isSamsungDevice: state.isSamsungDevice,
                      samsungSteps: const [
                        'Go to Settings > Apps > Lockbox > Battery.',
                        'Select "Unrestricted" (instead of Optimized).',
                        'Ensure Lockbox is not under Device care > Background limits > Deep sleeping apps.',
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom Action Bar ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF13131F),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: state.hasEssentialPermissions
                        ? Colors.indigoAccent
                        : Colors.white12,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _onFinish,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        state.hasEssentialPermissions
                            ? 'Complete Setup & Enter Vault'
                            : 'Grant Required Permissions (${state.essentialGrantedCount}/2)',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
