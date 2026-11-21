import 'dart:typed_data';

/// One DER element: its tag, content bytes, and the offset just past it.
class DerElement {
  /// Creates an element.
  const DerElement(this.tag, this.content, this.end);

  /// The tag byte, e.g. `0x30` for a SEQUENCE.
  final int tag;

  /// The content octets.
  final Uint8List content;

  /// Offset in the source buffer just after this element.
  final int end;
}

/// Longest long-form length accepted, in bytes: three, so at most 16 MiB.
/// Keys and certificates are a few kilobytes.
const int maxDerLengthBytes = 3;

/// Reads the DER element starting at [offset] in [bytes].
///
/// Strict DER (L9): the tag must use the low-tag-number form, the length
/// must be definite and minimal (short form below 128, no leading zero
/// bytes) and at most [maxDerLengthBytes] long. The length is built with
/// arithmetic rather than shifts, so it cannot turn negative on the web.
/// Throws [FormatException], never [RangeError], for truncated or malformed
/// input.
DerElement readDerElement(Uint8List bytes, [int offset = 0]) {
  if (offset < 0 || offset > bytes.length - 2) {
    throw const FormatException('Truncated DER data');
  }
  final tag = bytes[offset];
  if (tag & 0x1f == 0x1f) {
    throw const FormatException('High tag numbers are not supported');
  }
  var length = bytes[offset + 1];
  var position = offset + 2;
  if (length & 0x80 != 0) {
    final count = length & 0x7f;
    if (count == 0) {
      throw const FormatException('Indefinite DER length');
    }
    if (count > maxDerLengthBytes) {
      throw const FormatException('Unsupported DER length');
    }
    if (count > bytes.length - position) {
      throw const FormatException('Truncated DER length');
    }
    if (bytes[position] == 0) {
      throw const FormatException('Non-minimal DER length');
    }
    length = 0;
    for (var i = 0; i < count; i++) {
      length = length * 256 + bytes[position++];
    }
    if (length < 0x80) {
      throw const FormatException('Non-minimal DER length');
    }
  }
  if (length > bytes.length - position) {
    throw const FormatException('DER element exceeds its container');
  }
  return DerElement(
    tag,
    Uint8List.sublistView(bytes, position, position + length),
    position + length,
  );
}

/// Reads all child elements of a constructed element such as a SEQUENCE.
List<DerElement> readDerChildren(DerElement parent) {
  final children = <DerElement>[];
  var offset = 0;
  while (offset < parent.content.length) {
    final child = readDerElement(parent.content, offset);
    children.add(child);
    offset = child.end;
  }
  return children;
}

/// Interprets [element] as a non-negative INTEGER.
///
/// Rejects negative values and redundant leading zero bytes (a `0x00` is
/// allowed only when the next byte has its top bit set), as DER requires.
BigInt readDerInteger(DerElement element) {
  if (element.tag != 0x02 || element.content.isEmpty) {
    throw const FormatException('Expected a DER INTEGER');
  }
  final bytes = element.content;
  if (bytes[0] & 0x80 != 0) {
    throw const FormatException('Negative INTEGER');
  }
  if (bytes.length > 1 && bytes[0] == 0 && bytes[1] & 0x80 == 0) {
    throw const FormatException('Non-minimal INTEGER');
  }
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}
