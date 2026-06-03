// NHAI SDK — platform channel registration.
//
// Binds the host↔Flutter MethodChannel to the [NhaiSdkBridge]. The host (React
// Native, native Android/iOS, or any Flutter add-to-app embedder) invokes the
// five SDK methods by name; each call is forwarded to the bridge and the
// [SdkResult] is returned as a plain JSON map across the channel.
//
// Pure glue — no business logic, no changes to the frozen AI/attendance modules.
library;

import 'package:flutter/services.dart';

import 'nhai_sdk_bridge.dart';

class NhaiSdkChannel {
  /// Channel name shared with the host native module (see the React Native
  /// example under example_react_native/).
  static const String channelName = 'ai.nhai.biometric/sdk';

  final NhaiSdkBridge bridge;
  final MethodChannel _channel;

  NhaiSdkChannel(this.bridge, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Starts handling host calls. Each returns the [SdkResult] JSON map.
  void register() {
    _channel.setMethodCallHandler((call) async {
      final result = await bridge.handle(call.method, call.arguments);
      return result.toJson();
    });
  }

  /// Stops handling host calls.
  Future<void> dispose() async => _channel.setMethodCallHandler(null);
}
