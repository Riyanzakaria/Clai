import 'package:audio_service/audio_service.dart';

import '../player/queue_engine.dart' as qe;

/// Keadaan visual tombol acak Player (Ronde 8051 — cacat pemilik
/// 2026-11-10 20:40: "aku nyalain acak cerdas, acak biasa ikut nyala").
///
/// Mesin antrean punya TIGA mode acak (mati/murni/cerdas) yang berbagi
/// satu keadaan, tetapi tombol Player lama hanya menggambar dua keadaan
/// (menyala/tidak) — mode cerdas terlihat PERSIS seperti murni, sehingga
/// tombol mengklaim "acak biasa menyala" padahal mesin menjalankan Acak
/// Cerdas. Pemetaan murni ini adalah satu-satunya sumber kebenaran
/// tampilan + ketuk tombol itu, dikunci tes `shuffle_button_8051_test`.
enum ShuffleButtonLook { off, pure, smart }

/// Mode engine → wujud tombol: mati = redup; murni = aktif biasa
/// (Volt + titik); cerdas = aktif + lencana berlian Volt di sudut ikon.
ShuffleButtonLook shuffleButtonLook(qe.ShuffleMode mode) => switch (mode) {
      qe.ShuffleMode.off => ShuffleButtonLook.off,
      qe.ShuffleMode.pure => ShuffleButtonLook.pure,
      qe.ShuffleMode.smart => ShuffleButtonLook.smart,
    };

/// Sasaran ketuk tombol acak Player — perilaku paling jujur & sederhana:
/// ketuk MEMATIKAN mode yang sedang aktif (murni maupun cerdas — tidak
/// pernah diam-diam menukar cerdas menjadi murni); dari mati, ketuk
/// menyalakan MURNI. Mode cerdas hanya dinyalakan dari kartu Acak Cerdas
/// di layar Antrian (dan Pengaturan), bukan dari tombol ini.
AudioServiceShuffleMode shuffleTapTarget(qe.ShuffleMode mode) =>
    mode == qe.ShuffleMode.off
        ? AudioServiceShuffleMode.all
        : AudioServiceShuffleMode.none;
