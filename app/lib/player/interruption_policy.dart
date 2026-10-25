/// Kebijakan lanjut-otomatis pasca-interupsi (USER-FLOW-DAN-LOGIKA 2.2;
/// laporan perangkat riyan 2026-10-24). Fungsi murni — diuji unit.
///
/// Aturan mengikat:
/// - Hak lanjut-otomatis HANYA lahir bila interupsi sistem menjeda putaran
///   yang sedang berbunyi (handler mencatat hak + waktu saat interupsi
///   mulai). Jeda yang sudah ada sebelum interupsi tidak melahirkan hak.
/// - Jeda manual pengguna bersifat lengket: membatalkan hak kapan pun,
///   termasuk bila ditekan di tengah jeda interupsi (handler menghapus hak
///   di pause()).
/// - Hak berlaku satu kali (dikonsumsi saat interupsi berakhir), hanya bila
///   pengaturan lanjut-otomatis aktif dan jeda interupsi < 30 menit.
bool mayAutoResume({
  required bool granted,
  required bool settingEnabled,
  required DateTime? pausedAt,
  required DateTime now,
}) {
  if (!granted || !settingEnabled || pausedAt == null) return false;
  return now.difference(pausedAt) < const Duration(minutes: 30);
}

/// Bendera permintaan fokus untuk setelan perilaku fokus (PRD 5.13;
/// USER-FLOW 2.2). Fungsi murni — diuji unit.
///
/// Android hanya MENGIRIM peristiwa kehilangan
/// AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK ke pemegang fokus bila permintaan
/// fokusnya menyatakan akan menjeda saat di-duck
/// (AudioFocusRequest.setWillPauseWhenDucked /
/// AUDIOFOCUS_FLAG_PAUSES_ON_DUCKABLE_LOSS). Tanpa bendera itu, framework
/// men-duck sendiri secara senyap — MediaFocusControl mencatat kehilangan
/// CAN_DUCK dengan `notified: false` dan pendengar interupsi tidak pernah
/// menerima apa pun, sehingga setelan 'Jeda' mustahil bekerja untuk
/// perebut kelas duck (story WA, TikTok). Terbukti di pentasan build 2012
/// (builds/bukti-regresi-interupsi/pentasan/RINGKASAN-PENTASAN.md).
///
/// Maka: setelan 'pause' ('Jeda') → true — peristiwa terkirim,
/// audio_session memetakannya sebagai interupsi tipe jeda, dan kebijakan
/// 2.2 menjeda + memberi hak lanjut seperti interupsi sementara lain.
/// Setelan 'duck' ('Redam') atau belum terpasang → false — framework yang
/// men-duck, persis perilaku semua build sebelumnya.
bool willPauseWhenDuckedForFocusBehavior(String? focusBehavior) =>
    focusBehavior == 'pause';
