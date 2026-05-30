// Field-level encryption for sensitive data (Phase 12).
//
// IMPORTANT: [KeyedFieldEncryptor] is a self-contained, dependency-free keyed
// stream cipher used as the DEFAULT/pluggable implementation. Production should
// inject an AES-GCM implementation (the Hive box is also AES-encrypted at rest).
// The point of this layer is that biometric embeddings and PII are NEVER
// serialized as plaintext — only as opaque ciphertext blobs.
import 'dart:convert';

abstract class FieldEncryptor {
  String encrypt(String plaintext);
  String decrypt(String ciphertext);
}

/// Encodes/decodes a face embedding to/from an encrypted blob.
class BiometricCodec {
  final FieldEncryptor encryptor;
  const BiometricCodec(this.encryptor);

  String encode(List<double> embedding) =>
      encryptor.encrypt(jsonEncode(embedding));

  List<double> decode(String blob) {
    final list = jsonDecode(encryptor.decrypt(blob)) as List;
    return list.map((e) => (e as num).toDouble()).toList();
  }
}

/// Keyed XOR stream cipher (xorshift32 keystream seeded from the secret).
/// Deterministic, reversible, keyed; swap for AES-GCM in production.
class KeyedFieldEncryptor implements FieldEncryptor {
  final int _seed;

  KeyedFieldEncryptor(String secret) : _seed = _fnv1a(secret);

  static int _fnv1a(String s) {
    int h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h == 0 ? 0x1234567 : h;
  }

  List<int> _xor(List<int> data) {
    int state = _seed;
    final out = List<int>.filled(data.length, 0);
    for (int i = 0; i < data.length; i++) {
      state ^= (state << 13) & 0xFFFFFFFF;
      state ^= state >> 17;
      state ^= (state << 5) & 0xFFFFFFFF;
      out[i] = data[i] ^ (state & 0xFF);
    }
    return out;
  }

  @override
  String encrypt(String plaintext) => base64.encode(_xor(utf8.encode(plaintext)));

  @override
  String decrypt(String ciphertext) => utf8.decode(_xor(base64.decode(ciphertext)));
}
