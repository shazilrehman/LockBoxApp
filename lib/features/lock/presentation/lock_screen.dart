import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lockbox/core/services/local_auth_service.dart';
import 'package:lockbox/core/services/secure_storage_service.dart';
import 'package:lockbox/features/auth/domain/auth_models.dart';
import 'package:lockbox/features/auth/services/auth_service.dart';
import 'package:lockbox/features/lock/channels/lock_channel.dart';

// ════════════════════════════════════════════════════════════════
//  Lock Screen
// ════════════════════════════════════════════════════════════════

class LockScreen extends StatefulWidget {
  final LockScreenInfo info;
  final AuthService? authService;

  const LockScreen({
    super.key,
    required this.info,
    this.authService,
  });

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen>
    with SingleTickerProviderStateMixin {
  static const int _pinLength = 4;

  late final AuthService _authService;

  // ── State ─────────────────────────────────────────────
  String _entered = '';
  bool _hasPinStored = true;
  bool _verifying = false;
  String _statusMessage = 'Enter PIN to unlock';
  bool _isErrorStatus = false;

  // ── Lockout ───────────────────────────────────────────
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  // ── Shake animation ───────────────────────────────────
  late final AnimationController _shakeCtrl;
  late final Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _authService = widget.authService ??
        AuthService(
          storage: SecureStorageService(),
          localAuth: LocalAuthService(),
        );

    _initShake();
    _checkInitialState();
  }

  void _initShake() {
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -12, end: 12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 12, end: -8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -4), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -4, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
  }

  Future<void> _checkInitialState() async {
    final lockout = await _authService.getLockoutStatus();
    if (!mounted) return;

    if (lockout.isLockedOut) {
      _startLockoutCountdown(lockout.remainingLockout.inSeconds);
      return;
    }

    final hasPin = await _authService.hasPin();
    if (!mounted) return;

    setState(() {
      _hasPinStored = hasPin;
      _statusMessage = hasPin ? 'Enter PIN to unlock' : 'Authenticate to unlock';
      _isErrorStatus = false;
    });

    if (!hasPin) {
      // No PIN set — trigger biometric prompt automatically
      _triggerBiometric();
    }
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() {
      _lockoutSeconds = seconds;
      _entered = '';
      _isErrorStatus = true;
      _statusMessage = 'Too many attempts. Retry in ${_lockoutSeconds}s';
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_lockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _lockoutSeconds = 0;
          _isErrorStatus = false;
          _statusMessage = 'Enter PIN to unlock';
        });
      } else {
        setState(() {
          _lockoutSeconds--;
          _statusMessage = 'Too many attempts. Retry in ${_lockoutSeconds}s';
        });
      }
    });
  }

  // ── Input handlers ────────────────────────────────────

  void _onDigit(int digit) {
    if (_lockoutSeconds > 0 || _entered.length >= _pinLength || _verifying) return;
    HapticFeedback.lightImpact();
    setState(() => _entered += digit.toString());
    if (_entered.length == _pinLength) {
      _verifyPin();
    }
  }

  void _onBackspace() {
    if (_lockoutSeconds > 0 || _entered.isEmpty || _verifying) return;
    HapticFeedback.lightImpact();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  void _onClearAll() {
    if (_lockoutSeconds > 0 || _entered.isEmpty || _verifying) return;
    HapticFeedback.mediumImpact();
    setState(() => _entered = '');
  }

  Future<void> _verifyPin() async {
    setState(() => _verifying = true);
    final result = await _authService.verifyPin(_entered);

    if (!mounted) return;

    if (result.isSuccess) {
      await LockChannel.unlockSuccess();
      return;
    }

    // Failure branch
    HapticFeedback.heavyImpact();
    _shakeCtrl.forward(from: 0);
    unawaited(LockChannel.reportFailedAttempt());

    if (result.failureReason == AuthFailureReason.lockedOut) {
      _startLockoutCountdown(result.lockoutDuration.inSeconds);
    } else {
      setState(() {
        _isErrorStatus = true;
        _statusMessage = result.message ?? 'Incorrect PIN';
      });
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) setState(() => _entered = '');
    }

    if (mounted) setState(() => _verifying = false);
  }

  Future<void> _triggerBiometric() async {
    if (_lockoutSeconds > 0) return;
    HapticFeedback.mediumImpact();

    // Call native Android BiometricPrompt (supports BIOMETRIC_STRONG + BIOMETRIC_WEAK for Samsung face)
    final ok = await LockChannel.triggerBiometric();
    if (!mounted) return;

    if (ok) {
      await _authService.resetLockout();
      await LockChannel.unlockSuccess();
    } else {
      // Biometric cancelled or failed — cleanly fallback to PIN
      setState(() {
        _isErrorStatus = false;
        _statusMessage = _hasPinStored ? 'Enter PIN to unlock' : 'Authentication cancelled';
      });
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeCtrl.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isLockedOut = _lockoutSeconds > 0;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A10),
        body: SafeArea(
          child: Column(
            children: [
              // ── Top exit button ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.topRight,
                  child: IconButton(
                    tooltip: 'Exit to Home',
                    icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 28),
                    onPressed: LockChannel.goHome,
                  ),
                ),
              ),
              const Spacer(),
              _AppIcon(iconBytes: widget.info.iconBytes),
              const SizedBox(height: 16),
              Text(
                widget.info.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Text(
                  _statusMessage,
                  key: ValueKey<String>(_statusMessage),
                  style: TextStyle(
                    color: _isErrorStatus
                        ? Colors.redAccent.shade100
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 14,
                    fontWeight: _isErrorStatus ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              const Spacer(),
              // ── PIN dots (with shake) ──
              AnimatedBuilder(
                animation: _shakeAnim,
                builder: (_, child) => Transform.translate(
                  offset: Offset(_shakeAnim.value, 0),
                  child: child,
                ),
                child: _PinDots(
                  length: _pinLength,
                  filled: _entered.length,
                  isError: _isErrorStatus && !isLockedOut,
                ),
              ),
              const SizedBox(height: 44),
              // ── Number pad ──
              Opacity(
                opacity: isLockedOut ? 0.35 : 1.0,
                child: IgnorePointer(
                  ignoring: isLockedOut,
                  child: _PinPad(
                    onDigit: _onDigit,
                    onBackspace: _onBackspace,
                    onClearAll: _onClearAll,
                    onBiometric: _triggerBiometric,
                  ),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  App icon
// ════════════════════════════════════════════════════════════════

class _AppIcon extends StatelessWidget {
  final Uint8List? iconBytes;
  const _AppIcon({required this.iconBytes});

  @override
  Widget build(BuildContext context) {
    if (iconBytes != null && iconBytes!.isNotEmpty) {
      return Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.indigo.withValues(alpha: 0.25),
              blurRadius: 24,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.memory(iconBytes!, fit: BoxFit.cover),
        ),
      );
    }
    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Icon(Icons.lock_rounded, color: Colors.white38, size: 36),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  PIN dots
// ════════════════════════════════════════════════════════════════

class _PinDots extends StatelessWidget {
  final int length;
  final int filled;
  final bool isError;

  const _PinDots({
    required this.length,
    required this.filled,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(length, (i) {
        final active = i < filled;
        final dotColor = isError
            ? Colors.redAccent
            : (active ? Colors.white : Colors.transparent);
        final borderColor = isError
            ? Colors.redAccent
            : (active ? Colors.white : Colors.white24);

        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: active ? 16 : 14,
          height: active ? 16 : 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: Border.all(color: borderColor, width: 2),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: (isError ? Colors.redAccent : Colors.indigo)
                          .withValues(alpha: 0.5),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
        );
      }),
    );
  }
}

// ════════════════════════════════════════════════════════════════
//  PIN pad
// ════════════════════════════════════════════════════════════════

class _PinPad extends StatelessWidget {
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClearAll;
  final VoidCallback onBiometric;

  const _PinPad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClearAll,
    required this.onBiometric,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int row = 0; row < 4; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _buildRow(row),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildRow(int row) {
    if (row < 3) {
      return List.generate(3, (col) {
        final digit = row * 3 + col + 1;
        return _PadButton(label: '$digit', onTap: () => onDigit(digit));
      });
    }
    // Bottom row: biometric · 0 · backspace
    return [
      _PadButton(icon: Icons.fingerprint_rounded, onTap: onBiometric),
      _PadButton(label: '0', onTap: () => onDigit(0)),
      _PadButton(
        icon: Icons.backspace_outlined,
        onTap: onBackspace,
        onLongPress: onClearAll,
      ),
    ];
  }
}

// ════════════════════════════════════════════════════════════════
//  Single pad button
// ════════════════════════════════════════════════════════════════

class _PadButton extends StatefulWidget {
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PadButton({
    this.label,
    this.icon,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scale;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
      lowerBound: 0.88,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scale.reverse(),
      onTapUp: (_) {
        _scale.forward();
        widget.onTap();
      },
      onTapCancel: () => _scale.forward(),
      onLongPress: widget.onLongPress,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.07),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          alignment: Alignment.center,
          child: widget.label != null
              ? Text(
                  widget.label!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w300,
                  ),
                )
              : Icon(
                  widget.icon,
                  color: Colors.white.withValues(alpha: 0.65),
                  size: 28,
                ),
        ),
      ),
    );
  }
}
