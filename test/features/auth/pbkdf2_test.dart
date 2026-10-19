import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lockbox/features/auth/services/pbkdf2.dart';

void main() {
  group('Pbkdf2', () {
    test('derives correct key matching RFC 6070 PBKDF2-HMAC-SHA256 vector (1 iteration)', () {
      const pbkdf2 = Pbkdf2(iterations: 1, keyLength: 32);
      final salt = Uint8List.fromList(utf8.encode('salt'));
      final key = pbkdf2.derive('password', salt);
      final hex = Pbkdf2.bytesToHex(key);

      expect(
        hex,
        equals('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'),
      );
    });

    test('derives correct key matching RFC 6070 PBKDF2-HMAC-SHA256 vector (2 iterations)', () {
      const pbkdf2 = Pbkdf2(iterations: 2, keyLength: 32);
      final salt = Uint8List.fromList(utf8.encode('salt'));
      final key = pbkdf2.derive('password', salt);
      final hex = Pbkdf2.bytesToHex(key);

      expect(
        hex,
        equals('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'),
      );
    });

    test('derives correct key matching RFC 6070 PBKDF2-HMAC-SHA256 vector (4096 iterations, 40 bytes)', () {
      const pbkdf2 = Pbkdf2(iterations: 4096, keyLength: 40);
      final salt = Uint8List.fromList(utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'));
      final key = pbkdf2.derive('passwordPASSWORDpassword', salt);
      final hex = Pbkdf2.bytesToHex(key);

      expect(
        hex,
        equals('348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9'),
      );
    });

    test('generateSalt generates 16 unique bytes', () {
      final salt1 = Pbkdf2.generateSalt(16);
      final salt2 = Pbkdf2.generateSalt(16);

      expect(salt1.length, equals(16));
      expect(salt2.length, equals(16));
      expect(salt1, isNot(equals(salt2)));
    });

    test('bytesToHex and hexToBytes roundtrip cleanly', () {
      final original = Uint8List.fromList([0x00, 0x01, 0x0f, 0xa0, 0xff, 0x42]);
      final hex = Pbkdf2.bytesToHex(original);
      expect(hex, equals('00010fa0ff42'));

      final parsed = Pbkdf2.hexToBytes(hex);
      expect(parsed, equals(original));
    });

    group('constantTimeEquals', () {
      test('returns true for identical strings', () {
        expect(Pbkdf2.constantTimeEquals('abcdef0123456789', 'abcdef0123456789'), isTrue);
        expect(Pbkdf2.constantTimeEquals('', ''), isTrue);
      });

      test('returns false for different length strings', () {
        expect(Pbkdf2.constantTimeEquals('abc', 'abcd'), isFalse);
        expect(Pbkdf2.constantTimeEquals('abcd', 'abc'), isFalse);
      });

      test('returns false for strings differing by one character', () {
        expect(Pbkdf2.constantTimeEquals('abcdef0123456789', 'abcdef0123456788'), isFalse);
        expect(Pbkdf2.constantTimeEquals('1234', '1235'), isFalse);
      });
    });

    group('constantTimeBytesEquals', () {
      test('returns true for identical byte lists', () {
        expect(Pbkdf2.constantTimeBytesEquals([1, 2, 3], [1, 2, 3]), isTrue);
        expect(Pbkdf2.constantTimeBytesEquals([], []), isTrue);
      });

      test('returns false for differing byte lists', () {
        expect(Pbkdf2.constantTimeBytesEquals([1, 2, 3], [1, 2, 4]), isFalse);
        expect(Pbkdf2.constantTimeBytesEquals([1, 2], [1, 2, 3]), isFalse);
      });
    });
  });
}
