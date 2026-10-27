/// A business error from the `emu` helper: the code is what the UI switches
/// on, the message and hint are shown to the user.
class EmuException implements Exception {
  const EmuException(this.code, this.message, {this.hint});

  final String code;
  final String message;
  final String? hint;

  @override
  String toString() =>
      'EmuException($code): $message${hint == null ? '' : ' ($hint)'}';
}
