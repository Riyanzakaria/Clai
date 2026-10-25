import 'package:flutter/widgets.dart';

import 'app_localizations.dart';
import 'app_localizations_id.dart';

export 'app_localizations.dart';

/// Akses lokalisasi dari BuildContext: `context.l10n.someKey`.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

AppLocalizations? _current;

/// Instance lokalisasi aktif untuk kode non-UI (service/handler) yang
/// menghasilkan teks menghadap pengguna. Diatur ClaiApp setiap build dari
/// locale yang terpilih; sebelum itu (dan di tes) jatuh ke Bahasa Indonesia —
/// redaksi persis sama dengan perilaku sebelum i18n.
AppLocalizations get l10n => _current ?? AppLocalizationsId();

void setCurrentL10n(AppLocalizations value) => _current = value;
