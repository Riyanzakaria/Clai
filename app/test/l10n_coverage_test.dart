import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Gerbang cakupan string PRD Bab 3 (ditegakkan sejak ronde 2006):
/// kunci ARB id↔en harus sama persis, tidak ada nilai kosong, dan setiap
/// placeholder yang dipakai teks Indonesia juga ada di teks Inggris
/// (dan sebaliknya) — string yang hilang di satu bahasa = rilis gagal.
void main() {
  test('cakupan string id↔en lengkap & simetris', () {
    final idArb = jsonDecode(File('lib/l10n/app_id.arb').readAsStringSync())
        as Map<String, dynamic>;
    final enArb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, dynamic>;
    final idKeys = idArb.keys.where((k) => !k.startsWith('@')).toSet();
    final enKeys = enArb.keys.where((k) => !k.startsWith('@')).toSet();
    expect(enKeys, idKeys, reason: 'kunci ARB id dan en harus identik');
    expect(idKeys.length, greaterThan(100),
        reason: 'sanitasi: katalog string harus besar');
    final ph = RegExp(r'\{(\w+)[}:]');
    for (final k in idKeys) {
      final idText = idArb[k] as String;
      final enText = enArb[k] as String;
      expect(idText.trim(), isNotEmpty, reason: 'id "$k" kosong');
      expect(enText.trim(), isNotEmpty, reason: 'en "$k" kosong');
      final idPh = ph.allMatches(idText).map((m) => m.group(1)).toSet();
      final enPh = ph.allMatches(enText).map((m) => m.group(1)).toSet();
      expect(enPh, idPh, reason: 'placeholder "$k" tidak simetris');
    }
  });
}
