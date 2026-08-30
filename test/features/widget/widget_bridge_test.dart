import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riyaz/domain/time/civil_date.dart';
import 'package:riyaz/features/home/today_view.dart';
import 'package:riyaz/features/widget/widget_bridge.dart';
import 'package:riyaz/features/widget/widget_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(WidgetBridge.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  const payload = WidgetPayload(
    dateLabel: 'Friday, Aug 28',
    progressLabel: '1/2',
    rows: [],
    isEmpty: false,
  );

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('pushes the encoded payload over the channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });

    // The bridge is Android-only; force the platform for the test.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await const WidgetBridge().push(payload), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, WidgetBridge.updateMethod);
    expect(calls.single.arguments, contains('"progressLabel":"1/2"'));
  });

  test('a refusing launcher does not break the app', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'WIDGET_UNAVAILABLE');
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    // Reports failure rather than throwing: the widget is a convenience, and
    // a launcher that says no must never take the running app down with it.
    expect(await const WidgetBridge().push(payload), isFalse);
  });

  test('a missing native side is not an error', () async {
    // No handler registered at all — desktop, web, or a stripped build.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(await const WidgetBridge().push(payload), isFalse);
  });

  test('does nothing at all off Android', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    expect(await const WidgetBridge().push(payload), isFalse);
    expect(calls, isEmpty, reason: 'no channel call should be attempted');
  });

  test('the channel name matches the Kotlin handler', () {
    // Contract with MainActivity.kt. If these drift the widget silently stops
    // updating, with no error anywhere.
    expect(WidgetBridge.channelName, 'dev.riyaz/widget');
    expect(WidgetBridge.updateMethod, 'update');
  });

  test('payload built from a real view encodes end to end', () {
    final built = WidgetPayload.fromView(
      const TodayView(date: CivilDate(2026, 8, 28), items: []),
      'Friday, Aug 28',
    );
    expect(built.encode(), contains('"dateLabel":"Friday, Aug 28"'));
  });

  group('requestPin', () {
    /// Android is the only platform with widgets, and the bridge must be inert
    /// everywhere else rather than throwing into a screen.
    void onAndroid() {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
    }

    test('asks the launcher and reports that it was asked', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      onAndroid();

      expect(await const WidgetBridge().requestPin(), isTrue);
      expect(calls.single.method, WidgetBridge.pinMethod);
    });

    test('a launcher that will not pin reports false, and does not throw',
        () async {
      // Plenty of launchers do not support pinning. The caller has to be able
      // to tell the user to place it by hand instead of appearing to do
      // nothing.
      messenger.setMockMethodCallHandler(channel, (call) async => false);
      onAndroid();
      expect(await const WidgetBridge().requestPin(), isFalse);
    });

    test('a null answer is false, never a crash', () async {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
      onAndroid();
      expect(await const WidgetBridge().requestPin(), isFalse);
    });

    test('a platform exception is swallowed like every other widget call',
        () async {
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => throw PlatformException(code: 'NOPE'),
      );
      onAndroid();
      // The widget is a convenience. Nothing about it may break the app
      // running in front of the user.
      expect(await const WidgetBridge().requestPin(), isFalse);
    });

    test('no native side at all is false, not an exception', () async {
      messenger.setMockMethodCallHandler(channel, null);
      onAndroid();
      expect(await const WidgetBridge().requestPin(), isFalse);
    });

    test('does nothing off Android', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return true;
      });
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(await const WidgetBridge().requestPin(), isFalse);
      expect(calls, isEmpty);
    });
  });
}
