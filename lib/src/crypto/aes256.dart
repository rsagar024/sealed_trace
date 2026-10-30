import 'dart:typed_data';

/// AES-256 block encryption (FIPS 197). Encryption only: GCM never needs the
/// inverse cipher.
///
/// Written for this package and not audited. It uses table lookups and is not
/// constant-time; see the notes in the design documentation.
class Aes256 {
  /// Expands [key], which must be exactly 32 bytes.
  Aes256(Uint8List key) : _roundKeys = _expandKey(key);

  /// Bytes in one block.
  static const int blockSize = 16;

  /// Bytes in the key.
  static const int keySize = 32;

  static const int _rounds = 14;

  final Uint32List _roundKeys;

  /// Encrypts the 16 bytes at [inOffset] of [input] into [output] at
  /// [outOffset]. Input and output may be the same buffer.
  void encryptBlock(
    Uint8List input,
    int inOffset,
    Uint8List output,
    int outOffset,
  ) {
    final rk = _roundKeys;
    var s0 = _word(input, inOffset) ^ rk[0];
    var s1 = _word(input, inOffset + 4) ^ rk[1];
    var s2 = _word(input, inOffset + 8) ^ rk[2];
    var s3 = _word(input, inOffset + 12) ^ rk[3];

    var k = 4;
    for (var round = 1; round < _rounds; round++) {
      final t0 =
          _te0[s0 >>> 24] ^
          _te1[(s1 >>> 16) & 0xff] ^
          _te2[(s2 >>> 8) & 0xff] ^
          _te3[s3 & 0xff] ^
          rk[k];
      final t1 =
          _te0[s1 >>> 24] ^
          _te1[(s2 >>> 16) & 0xff] ^
          _te2[(s3 >>> 8) & 0xff] ^
          _te3[s0 & 0xff] ^
          rk[k + 1];
      final t2 =
          _te0[s2 >>> 24] ^
          _te1[(s3 >>> 16) & 0xff] ^
          _te2[(s0 >>> 8) & 0xff] ^
          _te3[s1 & 0xff] ^
          rk[k + 2];
      final t3 =
          _te0[s3 >>> 24] ^
          _te1[(s0 >>> 16) & 0xff] ^
          _te2[(s1 >>> 8) & 0xff] ^
          _te3[s2 & 0xff] ^
          rk[k + 3];
      s0 = t0;
      s1 = t1;
      s2 = t2;
      s3 = t3;
      k += 4;
    }

    final sb = _sbox;
    final o0 =
        ((sb[s0 >>> 24] << 24) |
            (sb[(s1 >>> 16) & 0xff] << 16) |
            (sb[(s2 >>> 8) & 0xff] << 8) |
            sb[s3 & 0xff]) ^
        rk[k];
    final o1 =
        ((sb[s1 >>> 24] << 24) |
            (sb[(s2 >>> 16) & 0xff] << 16) |
            (sb[(s3 >>> 8) & 0xff] << 8) |
            sb[s0 & 0xff]) ^
        rk[k + 1];
    final o2 =
        ((sb[s2 >>> 24] << 24) |
            (sb[(s3 >>> 16) & 0xff] << 16) |
            (sb[(s0 >>> 8) & 0xff] << 8) |
            sb[s1 & 0xff]) ^
        rk[k + 2];
    final o3 =
        ((sb[s3 >>> 24] << 24) |
            (sb[(s0 >>> 16) & 0xff] << 16) |
            (sb[(s1 >>> 8) & 0xff] << 8) |
            sb[s2 & 0xff]) ^
        rk[k + 3];

    _putWord(output, outOffset, o0);
    _putWord(output, outOffset + 4, o1);
    _putWord(output, outOffset + 8, o2);
    _putWord(output, outOffset + 12, o3);
  }

  static int _word(Uint8List b, int o) =>
      (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

  static void _putWord(Uint8List b, int o, int w) {
    b[o] = (w >>> 24) & 0xff;
    b[o + 1] = (w >>> 16) & 0xff;
    b[o + 2] = (w >>> 8) & 0xff;
    b[o + 3] = w & 0xff;
  }

  static Uint32List _expandKey(Uint8List key) {
    if (key.length != keySize) {
      throw ArgumentError.value(
        key.length,
        'key.length',
        'AES-256 needs a 32-byte key',
      );
    }
    const nk = 8;
    final total = 4 * (_rounds + 1);
    final w = Uint32List(total);
    for (var i = 0; i < nk; i++) {
      w[i] = _word(key, 4 * i);
    }
    var rcon = 1;
    for (var i = nk; i < total; i++) {
      var temp = w[i - 1];
      if (i % nk == 0) {
        temp =
            _subWord(((temp << 8) | (temp >>> 24)) & 0xffffffff) ^ (rcon << 24);
        rcon = _xtime(rcon);
      } else if (i % nk == 4) {
        temp = _subWord(temp);
      }
      w[i] = w[i - nk] ^ temp;
    }
    return w;
  }

  static int _subWord(int w) =>
      (_sbox[w >>> 24] << 24) |
      (_sbox[(w >>> 16) & 0xff] << 16) |
      (_sbox[(w >>> 8) & 0xff] << 8) |
      _sbox[w & 0xff];

  // Multiplication by x (0x02) in GF(2^8) modulo x^8 + x^4 + x^3 + x + 1.
  static int _xtime(int a) {
    final doubled = (a << 1) & 0xff;
    return (a & 0x80) != 0 ? doubled ^ 0x1b : doubled;
  }

  // The S-box is computed from its definition (multiplicative inverse in
  // GF(2^8) followed by the affine transform) instead of being typed in, so
  // there is no 256-entry literal to mistype.
  static final Uint8List _sbox = _buildSbox();

  static Uint8List _buildSbox() {
    int rotl8(int x, int shift) => ((x << shift) | (x >>> (8 - shift))) & 0xff;

    final box = Uint8List(256);
    var p = 1;
    var q = 1;
    do {
      // p *= 3.
      p = (p ^ ((p << 1) & 0xff) ^ ((p & 0x80) != 0 ? 0x1b : 0)) & 0xff;
      // q /= 3 (multiplication by 0xf6).
      q = (q ^ (q << 1)) & 0xff;
      q = (q ^ (q << 2)) & 0xff;
      q = (q ^ (q << 4)) & 0xff;
      if ((q & 0x80) != 0) q ^= 0x09;
      final affine = q ^ rotl8(q, 1) ^ rotl8(q, 2) ^ rotl8(q, 3) ^ rotl8(q, 4);
      box[p] = (affine ^ 0x63) & 0xff;
    } while (p != 1);
    box[0] = 0x63;
    return box;
  }

  // Combined SubBytes + MixColumns tables, one per byte position.
  static final Uint32List _te0 = _buildTe(0);
  static final Uint32List _te1 = _buildTe(8);
  static final Uint32List _te2 = _buildTe(16);
  static final Uint32List _te3 = _buildTe(24);

  static Uint32List _buildTe(int rotateRight) {
    final table = Uint32List(256);
    for (var x = 0; x < 256; x++) {
      final s = _sbox[x];
      final s2 = _xtime(s);
      final s3 = s2 ^ s;
      final word = (s2 << 24) | (s << 16) | (s << 8) | s3;
      table[x] = rotateRight == 0
          ? word
          : ((word >>> rotateRight) | (word << (32 - rotateRight))) &
                0xffffffff;
    }
    return table;
  }
}
