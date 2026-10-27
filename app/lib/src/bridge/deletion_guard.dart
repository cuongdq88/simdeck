/// The guard lives in `simutil_shared` so the TUI and CLI of the same fork
/// run the identical checks (spec §10); this re-export keeps app imports.
library;

export 'package:simutil_shared/src/deletion_guard.dart';
