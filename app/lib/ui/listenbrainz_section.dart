import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app.dart';
import '../core/clai_icons.dart';
import '../core/tokens.dart';
import '../l10n/l10n.dart';
import 'widgets.dart';

/// Seksi Pengaturan: ListenBrainz (F2). Token adalah milik pengguna, diisi
/// sendiri; fitur MATI secara default dan tidak mengirim apa pun sebelum
/// diaktifkan + token tersimpan. Yang dikirim hanya metadata dengar
/// (judul, artis, album, waktu). (Teks penjelas seksi pensiun di Ronde
/// 8084 mengikuti §13.2 — yang tinggal hanya kendali + status token.)
class ListenBrainzSettingsSection extends ConsumerStatefulWidget {
  const ListenBrainzSettingsSection({super.key});
  @override
  ConsumerState<ListenBrainzSettingsSection> createState() =>
      _ListenBrainzSettingsSectionState();
}

class _ListenBrainzSettingsSectionState
    extends ConsumerState<ListenBrainzSettingsSection> {
  bool _enabled = false;
  bool _loaded = false;
  bool _checking = false;
  String? _tokenStatus;
  final _tokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = ref.read(listenBrainzServiceProvider);
    final en = await svc.enabled;
    final tok = await svc.token;
    if (mounted) {
      setState(() {
        _enabled = en;
        _tokenCtrl.text = tok ?? '';
        _loaded = true;
      });
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.read(listenBrainzServiceProvider);
    if (!_loaded) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ronde 8084: baris terkunci 60 / label 15/600; subjudul
        // penjelas lbSub DIBUANG (§13.2 — penjelasan bukan state).
        SwitchListTile(
          minTileHeight: 60,
          secondary: rowLeadIcon(ClaiIcons.history, size: 40, iconSize: 24),
          title: Text(maxLines: 1, overflow: TextOverflow.ellipsis, 
            context.l10n.lbTitle,
            style: rowTitleStyle(),
          ),
          value: _enabled,
          onChanged: (v) async {
            await svc.setEnabled(v);
            if (mounted) setState(() => _enabled = v);
          },
        ),
        // Ronde 8084: padding horizontal dari PANEL pembungkus
        // (settingsSectionPanel, 20) — bukan 16 sendiri; isian
        // formulir konsisten filled surface2 r12.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 4),
          child: TextField(
            controller: _tokenCtrl,
            obscureText: true,
            style: const TextStyle(color: ClaiColors.ink),
            decoration: claiFieldDecoration(
              labelText: context.l10n.lbTokenLabel,
              hintText: context.l10n.lbTokenHint,
            ).copyWith(fillColor: ClaiColors.surface2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
          // Wrap (bukan Row kaku): teks status turun ke baris berikut
          // bila ruang sempit — Row lama meluber 40px pada lebar 390
          // (tertangkap tes perapian 8083; di font uji makin lebar).
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  backgroundColor: ClaiColors.surface3,
                  foregroundColor: ClaiColors.signal,
                ),
                onPressed: _checking
                    ? null
                    : () async {
                        setState(() {
                          _checking = true;
                          _tokenStatus = null;
                        });
                        await svc.setToken(_tokenCtrl.text);
                        final ok = await svc.validateToken(
                          _tokenCtrl.text.trim(),
                        );
                        if (mounted) {
                          setState(() {
                            _checking = false;
                            _tokenStatus = ok
                                ? context.l10n.lbTokenValid
                                : context.l10n.lbTokenInvalid;
                          });
                        }
                      },
                child: Text(
                  _checking
                      ? context.l10n.commonChecking
                      : context.l10n.lbSaveCheck,
                  style: const TextStyle(color: ClaiColors.signal),
                ),
              ),
              if (_tokenStatus != null)
                Text(
                  _tokenStatus!,
                  style: const TextStyle(
                    color: ClaiColors.inkSecondary,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        // Ronde 8084: seluruh baris penjelas lbSafeTitle/lbSafeSub
        // DIBUANG (§13.2 — penjelasan privasi bukan state baris;
        // status/kesalahan fungsional token di atas tetap).
      ],
    );
  }
}
