import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the per-workspace visitor token in secure storage.
///
/// Keys are namespaced by `publicId` so multiple Chatly workspaces can coexist
/// in a single app without colliding.
class ChatlyTokenStore {
  /// Creates a token store rooted at [publicId]. Optionally inject a custom
  /// [FlutterSecureStorage] for testing.
  ChatlyTokenStore({
    required this.publicId,
    FlutterSecureStorage? storage,
  }) : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// Public widget id used as the namespace.
  final String publicId;
  final FlutterSecureStorage _storage;

  String get _key => 'chatly_vt_$publicId';

  /// Returns the persisted token, or null if none has been stored.
  Future<String?> read() => _storage.read(key: _key);

  /// Persists [token] under the workspace-scoped key.
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  /// Clears any persisted token for this workspace.
  Future<void> clear() => _storage.delete(key: _key);
}
