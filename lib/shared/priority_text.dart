import 'package:flutter/widgets.dart';
import 'package:tasks_order/domain/model/priority_labels.dart';
import 'package:tasks_order/l10n/l10n.dart';

/// The name a priority has on [scale], for example "High" (D1). The number
/// is not shown: a level keeps its number on every scale (ADR-17), so scale 3
/// would read 2, 5, 7.
///
/// The domain gives a logical key and the ARB files hold the words (ADR-11);
/// this is the table between them. `priority_text_test.dart` checks that it
/// covers every key.
String priorityName(AppLocalizations l10n, int priority, int scale) =>
    switch (PriorityLabels.key(priority, scale)) {
      'priority.s3.1' => l10n.priorityS3P1,
      'priority.s3.2' => l10n.priorityS3P2,
      'priority.s3.3' => l10n.priorityS3P3,
      'priority.s5.1' => l10n.priorityS5P1,
      'priority.s5.2' => l10n.priorityS5P2,
      'priority.s5.3' => l10n.priorityS5P3,
      'priority.s5.4' => l10n.priorityS5P4,
      'priority.s5.5' => l10n.priorityS5P5,
      'priority.s10.1' => l10n.priorityS10P1,
      'priority.s10.2' => l10n.priorityS10P2,
      'priority.s10.3' => l10n.priorityS10P3,
      'priority.s10.4' => l10n.priorityS10P4,
      'priority.s10.5' => l10n.priorityS10P5,
      'priority.s10.6' => l10n.priorityS10P6,
      'priority.s10.7' => l10n.priorityS10P7,
      'priority.s10.8' => l10n.priorityS10P8,
      'priority.s10.9' => l10n.priorityS10P9,
      'priority.s10.10' => l10n.priorityS10P10,
      final key => throw StateError('No text for $key'),
    };

/// The colour a priority has on [scale]: red for the first level of the
/// scale, green for Normal, blue for the last.
Color priorityColor(int priority, int scale) =>
    Color(PriorityLabels.color(priority, scale));
