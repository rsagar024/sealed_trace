import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'aes256.dart';

/// AES-256-GCM encryption (NIST SP 800-38D) with a 96-bit IV.
///
/// Written for this package and not audited. It is not constant-time. In this
/// SDK every key encrypts exactly one message, which limits what a timing
/// observer could collect, but that is a mitigation, not a guarantee.
abstract final class AesGcm256 {
  /// Bytes in the only IV size supported.
  static const int ivSize = 12;

  /// Bytes in the authentication tag.
  static const int tagSize = 16;

  /// Called after every [encrypt] with the secret scratch buffers it wiped
  /// (the hash key H, the tag mask E_K(J0), the last keystream block, the
  /// counter and the expanded key), so tests can check they are zero.
  @visibleForTesting
  static void Function(List<Uint8List> wiped)? debugOnWipe;

  /// Encrypts [plaintext] under [key] (32 bytes) and [iv] (12 bytes),
  /// authenticating [aad] too when given.
  ///
  /// Returns the ciphertext (same length as the plaintext) and the 16-byte tag.
  /// Never reuse an [iv] with the same [key].
  static (Uint8List ciphertext, Uint8List tag) encrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
    Uint8List? aad,
  }) {
    if (iv.length != ivSize) {
      throw ArgumentError.value(
        iv.length,
        'iv.length',
        'GCM needs a 12-byte IV',
      );
    }
    final aes = Aes256(key);
    final hashKey = Uint8List(16);
    final counter = Uint8List(16);
    final tagMask = Uint8List(16);
    final keystream = Uint8List(16);
    _Ghash? ghash;
    try {
      return _encrypt(
        aes,
        iv,
        plaintext,
        aad,
        hashKey,
        counter,
        tagMask,
        keystream,
        (g) => ghash = g,
      );
    } finally {
      // Best effort: none of these may outlive the call (L4).
      aes.destroy();
      for (final b in [hashKey, counter, tagMask, keystream]) {
        b.fillRange(0, b.length, 0);
      }
      ghash?.destroy();
      debugOnWipe?.call([
        hashKey,
        counter,
        tagMask,
        keystream,
        aes.debugRoundKeys.buffer.asUint8List(),
        ?ghash?.debugState,
      ]);
    }
  }

  static (Uint8List, Uint8List) _encrypt(
    Aes256 aes,
    Uint8List iv,
    Uint8List plaintext,
    Uint8List? aad,
    Uint8List hashKey,
    Uint8List counter,
    Uint8List tagMask,
    Uint8List keystream,
    void Function(_Ghash) keep,
  ) {
    // H = E_K(0^128) and J0 = IV || 0x00000001.
    aes.encryptBlock(hashKey, 0, hashKey, 0);
    counter
      ..setRange(0, ivSize, iv)
      ..[15] = 1;
    aes.encryptBlock(counter, 0, tagMask, 0);

    // Counter mode starting at inc32(J0).
    final ciphertext = Uint8List(plaintext.length);
    var count = 1;
    for (var offset = 0; offset < plaintext.length; offset += 16) {
      count = (count + 1) & 0xffffffff;
      counter[12] = (count >>> 24) & 0xff;
      counter[13] = (count >>> 16) & 0xff;
      counter[14] = (count >>> 8) & 0xff;
      counter[15] = count & 0xff;
      aes.encryptBlock(counter, 0, keystream, 0);
      final end = offset + 16 < plaintext.length
          ? offset + 16
          : plaintext.length;
      for (var i = offset; i < end; i++) {
        ciphertext[i] = plaintext[i] ^ keystream[i - offset];
      }
    }

    // GHASH over A, C and the bit lengths, then mask with E_K(J0).
    final ghash = _Ghash(hashKey);
    keep(ghash);
    final data = aad ?? Uint8List(0);
    ghash.update(data);
    ghash.pad();
    ghash.update(ciphertext);
    ghash.pad();
    ghash.finishWithLengths(data.length * 8, ciphertext.length * 8);
    final tag = ghash.digest();
    for (var i = 0; i < 16; i++) {
      tag[i] ^= tagMask[i];
    }
    return (ciphertext, tag);
  }
}

/// GHASH, the GF(2^128) universal hash used by GCM. The 128-bit values are
/// four big-endian 32-bit words; word 0 holds the leftmost (bit 0) bits.
class _Ghash {
  _Ghash(Uint8List h)
    : _h0 = _word(h, 0),
      _h1 = _word(h, 4),
      _h2 = _word(h, 8),
      _h3 = _word(h, 12);

  // Not final, so destroy() can overwrite the hash key.
  int _h0;
  int _h1;
  int _h2;
  int _h3;

  /// Overwrites the hash key, the running state and the partial block.
  void destroy() {
    _h0 = _h1 = _h2 = _h3 = 0;
    _y0 = _y1 = _y2 = _y3 = 0;
    _partial.fillRange(0, 16, 0);
    _partialLength = 0;
  }

  /// H, the state and the partial block as bytes, for tests of [destroy].
  Uint8List get debugState {
    final out = Uint8List(32 + 16);
    final view = ByteData.sublistView(out);
    var o = 0;
    for (final w in [_h0, _h1, _h2, _h3, _y0, _y1, _y2, _y3]) {
      view.setUint32(o, w);
      o += 4;
    }
    out.setRange(32, 48, _partial);
    return out;
  }

  int _y0 = 0;
  int _y1 = 0;
  int _y2 = 0;
  int _y3 = 0;

  final Uint8List _partial = Uint8List(16);
  int _partialLength = 0;

  static int _word(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  /// 0xffffffff when [bit] is 1, 0 when it is 0, without a branch. Holds on
  /// the VM (64-bit ints) and on JavaScript (32-bit bitwise operations).
  static int _mask(int bit) => (-bit) & 0xffffffff;

  /// Absorbs [data] as part of the current run of blocks.
  void update(Uint8List data) {
    var offset = 0;
    if (_partialLength > 0) {
      while (offset < data.length && _partialLength < 16) {
        _partial[_partialLength++] = data[offset++];
      }
      if (_partialLength == 16) {
        _absorb(_partial, 0);
        _partialLength = 0;
      }
    }
    while (offset + 16 <= data.length) {
      _absorb(data, offset);
      offset += 16;
    }
    while (offset < data.length) {
      _partial[_partialLength++] = data[offset++];
    }
  }

  /// Zero-pads the data absorbed so far to a whole block.
  void pad() {
    if (_partialLength == 0) return;
    _partial.fillRange(_partialLength, 16, 0);
    _absorb(_partial, 0);
    _partialLength = 0;
  }

  /// Absorbs the final block holding both lengths, in bits, as 64-bit values.
  void finishWithLengths(int aadBits, int cipherBits) {
    final block = Uint8List(16);
    final view = ByteData.sublistView(block);
    // Written as two 32-bit halves so it also holds on JavaScript.
    view.setUint32(0, (aadBits ~/ 0x100000000) & 0xffffffff);
    view.setUint32(4, aadBits & 0xffffffff);
    view.setUint32(8, (cipherBits ~/ 0x100000000) & 0xffffffff);
    view.setUint32(12, cipherBits & 0xffffffff);
    _absorb(block, 0);
  }

  Uint8List digest() {
    final out = Uint8List(16);
    final view = ByteData.sublistView(out);
    view.setUint32(0, _y0);
    view.setUint32(4, _y1);
    view.setUint32(8, _y2);
    view.setUint32(12, _y3);
    return out;
  }

  void _absorb(Uint8List block, int offset) {
    final x0 = _y0 ^ _word(block, offset);
    final x1 = _y1 ^ _word(block, offset + 4);
    final x2 = _y2 ^ _word(block, offset + 8);
    final x3 = _y3 ^ _word(block, offset + 12);

    // Z = X * H, one bit of X at a time from the leftmost bit. Branch-free
    // (L5): each step uses an all-ones or all-zeros mask derived from the
    // bit instead of an `if`, so the work does not depend on X or H.
    var z0 = 0;
    var z1 = 0;
    var z2 = 0;
    var z3 = 0;
    var v0 = _h0;
    var v1 = _h1;
    var v2 = _h2;
    var v3 = _h3;
    for (var word = 0; word < 4; word++) {
      final x = word == 0
          ? x0
          : word == 1
          ? x1
          : word == 2
          ? x2
          : x3;
      for (var bit = 31; bit >= 0; bit--) {
        final take = _mask((x >>> bit) & 1);
        z0 ^= v0 & take;
        z1 ^= v1 & take;
        z2 ^= v2 & take;
        z3 ^= v3 & take;
        final reduce = _mask(v3 & 1);
        v3 = ((v3 >>> 1) | ((v2 & 1) << 31)) & 0xffffffff;
        v2 = ((v2 >>> 1) | ((v1 & 1) << 31)) & 0xffffffff;
        v1 = ((v1 >>> 1) | ((v0 & 1) << 31)) & 0xffffffff;
        v0 = (v0 >>> 1) ^ (0xe1000000 & reduce);
      }
    }
    _y0 = z0 & 0xffffffff;
    _y1 = z1 & 0xffffffff;
    _y2 = z2 & 0xffffffff;
    _y3 = z3 & 0xffffffff;
  }
}
