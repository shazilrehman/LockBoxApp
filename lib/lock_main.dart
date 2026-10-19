import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lockbox/features/lock/channels/lock_channel.dart';
import 'package:lockbox/features/lock/presentation/lock_screen.dart';

/// Separate Dart entrypoint executed by the pre-warmed lock [FlutterEngine].
///
/// Registered with `@pragma('vm:entry-point')` so the Kotlin
/// [DartExecutor] can find it by name.
@pragma('vm:entry-point')
void lockMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: LockApp()));
}

class LockApp extends StatefulWidget {
  const LockApp({super.key});

  @override
  State<LockApp> createState() => _LockAppState();
}

class _LockAppState extends State<LockApp> {
  LockScreenInfo? _info;
  Key _screenKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    LockChannel.init(onShowLockScreen: (info) {
      if (!mounted) return;
      setState(() {
        _info = info;
        _screenKey = UniqueKey(); // force a fresh LockScreen state
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: _info != null
          ? LockScreen(key: _screenKey, info: _info!)
          : const Scaffold(
              backgroundColor: Color(0xFF0A0A10),
              body: SizedBox.shrink(),
            ),
    );
  }
}
