class LaunchOptions {
  const LaunchOptions({
    this.noAudio = false,
    this.wipeData = false,
    this.gpu = 'auto',
    this.noSnapshot = false,
  });

  factory LaunchOptions.fromJson(Map<String, dynamic> json) {
    return LaunchOptions(
      noAudio: json['noAudio'] as bool? ?? false,
      wipeData: json['wipeData'] as bool? ?? false,
      gpu: json['gpu'] as String? ?? 'auto',
      noSnapshot: json['noSnapshot'] as bool? ?? false,
    );
  }

  final bool noAudio;

  final bool wipeData;

  final String gpu;

  final bool noSnapshot;

  LaunchOptions copyWith({
    bool? noAudio,
    bool? wipeData,
    String? gpu,
    bool? noSnapshot,
  }) {
    return LaunchOptions(
      noAudio: noAudio ?? this.noAudio,
      wipeData: wipeData ?? this.wipeData,
      gpu: gpu ?? this.gpu,
      noSnapshot: noSnapshot ?? this.noSnapshot,
    );
  }

  List<String> toAndroidArgs() {
    final args = <String>[];
    if (noAudio) args.add('-no-audio');
    if (wipeData) args.add('-wipe-data');
    if (gpu != 'auto') args.addAll(['-gpu', gpu]);
    if (noSnapshot) args.add('-no-snapshot-load');
    return args;
  }

  Map<String, dynamic> toJson() {
    return {
      'noAudio': noAudio,
      'wipeData': wipeData,
      'gpu': gpu,
      'noSnapshot': noSnapshot,
    };
  }
}
