import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'widget_payload.dart';

/// Pushes today's state to the Android home-screen widget.
///
/// A plain [MethodChannel] rather than a plugin: the whole contract is one
/// method taking one JSON string, and the native side is thirty lines of
/// Kotlin. Adding a package for that would cost more than it saves.
///
/// Failures are swallowed on purpose. The widget is a convenience; a launcher
/// that refuses an update, or a platform with no widget at all, must never
/// break the app that is running in front of the user.
class WidgetBridge {
  const WidgetBridge({this.channel = const MethodChannel(channelName)});

  static const String channelName = 'dev.riyaz/widget';
  static const String updateMethod = 'update';
  static const String pinMethod = 'pinWidget';

  final MethodChannel channel;

  Future<bool> push(WidgetPayload payload) async {
    if (!_supported) return false;
    try {
      await channel.invokeMethod<void>(updateMethod, payload.encode());
      return true;
    } on PlatformException catch (e) {
      debugPrint('Widget update refused: ${e.message}');
      return false;
    } on MissingPluginException {
      // No native side registered — desktop, web, or a test.
      return false;
    }
  }

  /// Asks the launcher to offer the user a one-tap "add this widget".
  ///
  /// Returns false when the platform has no widgets, when the launcher does
  /// not support pinning — plenty do not — or when it simply declines. The
  /// caller has to say something in that case rather than appear to do
  /// nothing, because the whole point of this path is that the manual route
  /// (long-press the wallpaper, find Widgets, scroll an alphabetical list of
  /// every app on the phone) is one most people never complete.
  ///
  /// A `true` result means the launcher *showed its dialog*, not that the user
  /// accepted. Android gives no callback for the choice, so the app must not
  /// claim the widget was added.
  Future<bool> requestPin() async {
    if (!_supported) return false;
    try {
      return await channel.invokeMethod<bool>(pinMethod) ?? false;
    } on PlatformException catch (e) {
      debugPrint('Widget pin refused: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}
