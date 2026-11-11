/// Shim kompatibilitas diagnostik (Tahap 3): mesin WebView BotGuard/EJS
/// telah diproduksikan ke `services/direct_web_engine.dart`
/// ([DirectWebEngine]). Nama-nama lama laboratorium tetap hidup di sini
/// sebagai alias agar harness Diagnostik Putar (v3.13) tidak berubah
/// perilaku sedikit pun — widget yang sama, state yang sama.
library;

import '../services/direct_web_engine.dart';

export '../services/direct_web_engine.dart';

typedef PoTokenLabState = DirectWebEngineState;
typedef PoSessionResult = DirectSessionResult;
typedef PoMintResult = DirectMintResult;

/// Widget laboratorium = mesin produksi itu sendiri, dengan kabel kemajuan
/// diagnostik terpasang.
class PoTokenLab extends DirectWebEngine {
  const PoTokenLab({super.key, required super.onProgress});
}
