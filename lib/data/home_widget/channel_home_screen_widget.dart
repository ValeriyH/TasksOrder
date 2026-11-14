import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:tasks_order/domain/repository/home_screen_widget.dart';

/// [HomeScreenWidget] over a method channel to `MainActivity.kt`, Android
/// only (T-601). No package: the native side is a few lines (ADR-22).
class ChannelHomeScreenWidget implements HomeScreenWidget {
  ChannelHomeScreenWidget([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel(channelName);

  /// Must match `MainActivity.kt`.
  static const channelName = 'tasks_order/home_widget';

  final MethodChannel _channel;

  @override
  bool get isSupported => !kIsWeb && Platform.isAndroid;

  @override
  Future<void> update(String payload) async {
    if (!isSupported) return;
    await _channel.invokeMethod<void>('update', payload);
  }
}
