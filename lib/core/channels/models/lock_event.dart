/// Event emitted by the native accessibility service when a locked app is detected.
class LockEvent {
  final String packageName;
  final String eventType; // "app_launched" | "app_blocked"
  final int timestamp;

  const LockEvent({
    required this.packageName,
    required this.eventType,
    required this.timestamp,
  });

  factory LockEvent.fromMap(Map<String, dynamic> map) {
    return LockEvent(
      packageName: map['packageName'] as String,
      eventType: map['eventType'] as String,
      timestamp: map['timestamp'] as int,
    );
  }

  @override
  String toString() => 'LockEvent($eventType, $packageName)';
}
