import 'dart:io';

abstract class CommandExec {
  Future<String> run(
    String command, {
    List<String> arguments,
    String? workingDirectory,
  });
}

class CommandExecImpl implements CommandExec {
  @override
  Future<String> run(
    String command, {
    List<String> arguments = const [],
    String? workingDirectory,
  }) async {
    final result = await Process.run(
      command,
      arguments,
      workingDirectory: workingDirectory,
    );
    return result.stdout;
  }
}
