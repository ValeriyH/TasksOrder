import 'package:tasks_order/domain/model/task_size.dart';
import 'package:tasks_order/l10n/generated/app_localizations.dart';

/// The name of [size] (D21).
String sizeLabel(AppLocalizations l10n, TaskSize size) => switch (size) {
  TaskSize.small => l10n.sizeSmall,
  TaskSize.normal => l10n.sizeNormal,
  TaskSize.large => l10n.sizeLarge,
};

/// A load in half-slots as slots (D21): 3 → "1½", 1 → "½", 4 → "2".
String slotsText(int halfSlots) {
  final whole = halfSlots ~/ 2;
  if (halfSlots.isEven) return '$whole';
  return whole == 0 ? '½' : '$whole½';
}
