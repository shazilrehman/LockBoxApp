import 'package:flutter/material.dart';

/// Prominent disclosure modal dialog strictly compliant with Google Play
/// Accessibility API policies.
///
/// Must be presented to the user BEFORE requesting or directing to the
/// AccessibilityService settings screen.
class PlayDisclosureDialog extends StatelessWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const PlayDisclosureDialog({
    super.key,
    required this.onAccept,
    required this.onDecline,
  });

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PlayDisclosureDialog(
        onAccept: () => Navigator.of(ctx).pop(true),
        onDecline: () => Navigator.of(ctx).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF161622),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Icon & Title ──
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.indigo.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.indigo.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.accessibility_new_rounded,
                    color: Colors.indigoAccent,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'Accessibility Service\nProminent Disclosure',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Purpose Section ──
              _DisclosureSection(
                icon: Icons.security_rounded,
                iconColor: Colors.blueAccent,
                title: 'Why Lockbox needs Accessibility',
                body:
                    'Lockbox uses the Android AccessibilityService API solely to detect when a locked application opens in the foreground, allowing Lockbox to immediately display the PIN/Biometric lock screen and protect your privacy.',
              ),
              const SizedBox(height: 14),

              // ── Data Accessed Section ──
              _DisclosureSection(
                icon: Icons.visibility_outlined,
                iconColor: Colors.amberAccent,
                title: 'Data Accessed',
                body:
                    'The service monitors window state change events to read the package name of the currently active app. No other window or screen contents are accessed.',
              ),
              const SizedBox(height: 14),

              // ── Privacy Guarantee ──
              const _DisclosureSection(
                icon: Icons.shield_outlined,
                iconColor: Color(0xFF10B981),
                title: 'Your Privacy Is Protected',
                body:
                    '• Lockbox does NOT collect, store, or transmit your personal data.\n'
                    '• Lockbox does NOT read your keystrokes, messages, or screen text.\n'
                    '• Lockbox is 100% offline and has no internet access.',
              ),
              const SizedBox(height: 28),

              // ── Action Buttons ──
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white60,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onDecline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.indigoAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onAccept,
                      child: const Text(
                        'I Understand & Accept',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisclosureSection extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  const _DisclosureSection({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
