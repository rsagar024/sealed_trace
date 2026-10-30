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

/// Reads the DER element starting at [offset] in [bytes].
///
/// Throws [FormatException] for truncated or malformed input.
DerElement readDerElement(Uint8List bytes, [int offset = 0]) {
  if (offset < 0 || offset + 2 > bytes.length) {
    throw const FormatException('Truncated DER data');
  }
  final tag = bytes[offset];
  var length = bytes[offset + 1];
  var position = offset + 2;
  if (length & 0x80 != 0) {
    final count = length & 0x7f;
    if (count == 0 || count > 4 || position + count > bytes.length) {
      throw const FormatException('Unsupported DER length');
    }
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | bytes[position++];
    }
  }
  if (position + length > bytes.length) {
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
BigInt readDerInteger(DerElement element) {
  if (element.tag != 0x02 || element.content.isEmpty) {
    throw const FormatException('Expected a DER INTEGER');
  }
  final bytes = element.content;
  if (bytes[0] & 0x80 != 0) {
    throw const FormatException('Negative INTEGER');
  }
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}
