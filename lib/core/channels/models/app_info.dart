/// Data class representing an installed application.
class AppInfo {
  final String packageName;
  final String appName;
  final bool isSystemApp;

  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.isSystemApp,
  });

  factory AppInfo.fromMap(Map<String, dynamic> map) {
    return AppInfo(
      packageName: map['packageName'] as String,
      appName: map['appName'] as String,
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'isSystemApp': isSystemApp,
      };

  @override
  String toString() => 'AppInfo($appName, $packageName)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppInfo &&
          runtimeType == other.runtimeType &&
          packageName == other.packageName;

  @override
  int get hashCode => packageName.hashCode;
}
