

class AppSettings {
  const AppSettings({
    this.themeName = 'dark',
    this.lastSelectedDeviceId,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      themeName: json['themeName'] as String? ?? 'dark',
      lastSelectedDeviceId: json['lastSelectedDeviceId'] as String?,
    );
  }
  final String themeName;

  final String? lastSelectedDeviceId;

  AppSettings copyWith({
    String? themeName,
    String? lastSelectedDeviceId,
  }) {
    return AppSettings(
      themeName: themeName ?? this.themeName,
      lastSelectedDeviceId: lastSelectedDeviceId ?? this.lastSelectedDeviceId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeName': themeName,
      'lastSelectedDeviceId': lastSelectedDeviceId,
    };
  }
}
