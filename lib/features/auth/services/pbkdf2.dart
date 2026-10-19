import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Pure Dart implementation of PBKDF2 with HMAC-SHA256 (RFC 2898 / RFC 8018).
class Pbkdf2 {
  final int iterations;
  final int keyLength;

  /// Default configuration uses 100,000 iterations and a 256-bit (32-byte) key.
  const Pbkdf2({
    this.iterations = 100000,
    this.keyLength = 32,
  });

  /// Generates a cryptographically secure random salt using [Random.secure].
  static Uint8List generateSalt([int length = 16]) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Derives a key from [password] and [salt] using PBKDF2 HMAC-SHA256.
  Uint8List derive(String password, Uint8List salt) {
    final passwordBytes = utf8.encode(password);
    final hmac = Hmac(sha256, passwordBytes);
    const hLen = 32; // SHA-256 digest length in bytes
    final l = (keyLength / hLen).ceil();
    final r = keyLength - (l - 1) * hLen;

    final derived = Uint8List(keyLength);
    int offset = 0;

    for (int i = 1; i <= l; i++) {
      // U_1 = PRF(P, S || INT_32_BE(i))
      final blockIndexBytes = ByteData(4)..setUint32(0, i, Endian.big);
      final initialInput = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..setRange(
          salt.length,
          salt.length + 4,
          blockIndexBytes.buffer.asUint8List(),
        );

      var u = Uint8List.fromList(hmac.convert(initialInput).bytes);
      final t = Uint8List.fromList(u);

      for (int c = 1; c < iterations; c++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }

      final copyLen = (i == l) ? r : hLen;
      derived.setRange(offset, offset + copyLen, t.sublist(0, copyLen));
      offset += copyLen;
    }

    return derived;
  }

  /// Converts a byte array to a lowercase hex string.
  static String bytesToHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final b in bytes) {
      buffer.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Parses a hex string into a [Uint8List].
  static Uint8List hexToBytes(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Constant-time comparison between two strings to mitigate timing attacks.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// Constant-time comparison between two byte sequences.
  static bool constantTimeBytesEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
