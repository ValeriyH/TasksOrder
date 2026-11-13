import 'package:flutter/widgets.dart';
import 'package:tasks_order/l10n/generated/app_localizations.dart';

export 'package:tasks_order/l10n/generated/app_localizations.dart';

/// `context.l10n.tabToday` instead of `AppLocalizations.of(context).tabToday`.
extension L10nContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
