import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lockbox/core/channels/lockbox_channel.dart';
import 'package:lockbox/core/channels/models/lock_event.dart';

/// Singleton [LockboxChannel] instance.
final lockboxChannelProvider = Provider<LockboxChannel>((ref) {
  return LockboxChannel();
});

/// Exposes the native lock-event stream as a Riverpod StreamProvider.
final lockEventsProvider = StreamProvider<LockEvent>((ref) {
  final channel = ref.watch(lockboxChannelProvider);
  return channel.lockEvents;
});
