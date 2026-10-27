import 'dart:io';

/// `~/Movies/SimDeck` on macOS, `~/Videos/SimDeck` elsewhere; created on use.
String recordingsDirectory() {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';
  final dir = Directory(
    '$home${Platform.pathSeparator}${Platform.isMacOS ? 'Movies' : 'Videos'}'
    '${Platform.pathSeparator}SimDeck',
  )..createSync(recursive: true);
  return dir.path;
}
