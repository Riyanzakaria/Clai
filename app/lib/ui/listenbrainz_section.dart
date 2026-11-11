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
/// (judul, artis, album, waktu) — dinyatakan terbuka di teks seksi ini.
class ListenBrainzSettingsSection extends ConsumerStatefulWidget {
  const ListenBrainzSettingsSection({super.key});
  @override
  ConsumerState<ListenBrainzSettingsSection> createState() => _ListenBrainzSettingsSectionState();
}

class _ListenBrainzSettingsSectionState extends ConsumerState<ListenBrainzSettingsSection> {
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
    if (mounted) setState(() { _enabled = en; _tokenCtrl.text = tok ?? ''; _loaded = true; });
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
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SwitchListTile(
        secondary: tonalIconBox(ClaiIcons.history, size: 40, iconSize: 20),
        title: Text(context.l10n.lbTitle, style: const TextStyle(color: ClaiColors.ink)),
        subtitle: Text(context.l10n.lbSub,
            style: const TextStyle(color: ClaiColors.inkSecondary)),
        value: _enabled,
        onChanged: (v) async { await svc.setEnabled(v); if (mounted) setState(() => _enabled = v); },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: TextField(
          controller: _tokenCtrl,
          obscureText: true,
          style: const TextStyle(color: ClaiColors.ink),
          decoration: claiFieldDecoration(
            labelText: context.l10n.lbTokenLabel,
            hintText: context.l10n.lbTokenHint,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: ClaiColors.surface3,
              foregroundColor: ClaiColors.accent,
            ),
            onPressed: _checking ? null : () async {
              setState(() { _checking = true; _tokenStatus = null; });
              await svc.setToken(_tokenCtrl.text);
              final ok = await svc.validateToken(_tokenCtrl.text.trim());
              if (mounted) setState(() { _checking = false; _tokenStatus = ok ? context.l10n.lbTokenValid : context.l10n.lbTokenInvalid; });
            },
            child: Text(_checking ? context.l10n.commonChecking : context.l10n.lbSaveCheck, style: const TextStyle(color: ClaiColors.accent)),
          ),
          if (_tokenStatus != null)
            Expanded(child: Text(_tokenStatus!, style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13))),
        ]),
      ),
      ListTile(
        leading: tonalIconBox(ClaiIcons.shield, size: 40, iconSize: 20, color: ClaiColors.inkFaint),
        title: Text(context.l10n.lbSafeTitle, style: const TextStyle(color: ClaiColors.ink, fontSize: 13)),
        subtitle: Text(context.l10n.lbSafeSub,
            style: const TextStyle(color: ClaiColors.inkSecondary, fontSize: 13)),
      ),
    ]);
  }
}
