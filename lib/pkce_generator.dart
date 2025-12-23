import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:localstorage/localstorage.dart';
import 'package:crypto/crypto.dart' as crypto;

abstract class PkceCache {
  Future<void> saveVerifier(String verifier);
  Future<String?> readVerifier();
}

class LocalStoragePkceCache implements PkceCache {
  LocalStoragePkceCache(this._storage);
  final LocalStorage _storage;
  static const _cvKey = 'cv';

  @override
  Future<void> saveVerifier(String verifier) async => _storage.setItem(_cvKey, verifier);

  @override
  Future<String?> readVerifier() async => _storage.getItem(_cvKey);
}

class PkcePair {
  final String codeVerifier;
  final String codeChallenge;

  const PkcePair(this.codeVerifier, this.codeChallenge);

  @override
  String toString() => 'PkcePair(verifier: $codeVerifier, challenge: $codeChallenge)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PkcePair && runtimeType == other.runtimeType && codeVerifier == other.codeVerifier && codeChallenge == other.codeChallenge;

  @override
  int get hashCode => Object.hash(codeVerifier, codeChallenge);
}

abstract class RandomBytesSource {
  Uint8List nextBytes(int length);
}

class SecureRandomBytesSource implements RandomBytesSource {
  SecureRandomBytesSource([Random? rng]) : _rng = rng ?? Random.secure();
  final Random _rng;

  @override
  Uint8List nextBytes(int length) => Uint8List.fromList(List<int>.generate(length, (_) => _rng.nextInt(256)));
}

abstract class Hasher {
  Uint8List hash(Uint8List data);
}

class Sha256Hasher implements Hasher {
  @override
  Uint8List hash(Uint8List data) => Uint8List.fromList(crypto.sha256.convert(data).bytes);
}

/// Generates PKCE pairs per RFC 7636, with injectable dependencies.
class PkceGenerator {
  static const int minVerifierLength = 43;
  static const int maxVerifierLength = 128;

  PkceGenerator({RandomBytesSource? rng, Hasher? hasher}) : _rng = rng ?? SecureRandomBytesSource(), _hasher = hasher ?? Sha256Hasher();

  final RandomBytesSource _rng;
  final Hasher _hasher;

  /// Generate a PKCE pair. [verifierLength] must be 43..128.
  PkcePair generate({int verifierLength = 64}) {
    _validateLength(verifierLength);
    final verifier = _generateCodeVerifier(verifierLength);
    final challenge = _createCodeChallenge(verifier);
    return PkcePair(verifier, challenge);
  }

  void _validateLength(int length) {
    if (length < minVerifierLength || length > maxVerifierLength) {
      throw ArgumentError.value(length, 'verifierLength', 'Must be between $minVerifierLength and $maxVerifierLength');
    }
  }

  String _generateCodeVerifier(int targetLength) {
    // Estimate bytes needed for a base64url string of approx targetLength:
    int bytesNeeded = ((targetLength * 3) / 4).ceil();

    while (true) {
      final candidate = base64Url.encode(_rng.nextBytes(bytesNeeded)).replaceAll('=', '');

      if (candidate.length >= targetLength) {
        // Trimming is allowed by the spec; no padding.
        return candidate.substring(0, targetLength);
      }

      // If too short, bump bytesNeeded and try again.
      bytesNeeded = (bytesNeeded * 1.25).ceil();
    }
  }

  String _createCodeChallenge(String codeVerifier) {
    final digest = _hasher.hash(Uint8List.fromList(utf8.encode(codeVerifier)));

    return base64Url.encode(digest).replaceAll('=', '');
  }
}
