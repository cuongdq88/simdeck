# Changelog

## Unreleased

- **Breaking:** `CommandExecImpl` is removed; use the `CommandExec()` factory.
- **Breaking:** `IsolateCommandExec` is removed; use `CommandExec.isolate(runner)`.
- `CommandExec()` kills the process when `timeout` elapses (the old
  `CommandExecImpl` left it running).
- `CommandExec()` and `IsolateRunner` close the child's stdin, so commands
  that read stdin see EOF instead of hanging.

## 1.0.0

- Initial release, extracted from the `simutil` app.
