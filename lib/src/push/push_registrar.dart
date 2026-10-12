import 'dart:io' show Platform;

import '../transport/rest_client.dart';

/// Registers device push tokens with the Chatly backend.
///
/// Detects platform (APNs vs FCM) automatically so app code only has to pass
/// the raw token. Calling [register] twice with the same token is a no-op.
class ChatlyPushRegistrar {
  /// Creates a registrar bound to [_rest].
  ChatlyPushRegistrar(this._rest);

  final ChatlyRestClient _rest;
  String? _lastToken;

  /// Sends [token] to the backend together with the detected platform.
  ///
  /// Pass `platformOverride` to bypass platform autodetection (useful for
  /// hybrid stacks that route both APNs and FCM through one app instance).
  Future<void> register(String token, {String? platformOverride}) async {
    if (token.isEmpty || token == _lastToken) return;
    final platform = platformOverride ?? _detectPlatform();
    await _rest.registerPushToken(token: token, platform: platform);
    _lastToken = token;
  }

  /// Clears the cached token so the next [register] call always sends.
  void reset() {
    _lastToken = null;
  }

  String _detectPlatform() {
    try {
      if (Platform.isIOS) return 'apns';
      if (Platform.isAndroid) return 'fcm';
      if (Platform.isMacOS) return 'apns';
    } catch (_) {
      // Platform may throw on web; fall through to fcm as the safest default.
    }
    return 'fcm';
  }
}
