import 'dart:convert';

import '../util/limits.dart';

/// Strips BOMs and normalises CRLF / lone CR to `\n`.
String normalizePgnText(String input) {
  var s = input.contains('﻿') ? input.replaceAll('﻿', '') : input;
  if (s.contains('\r')) {
    s = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
  return s;
}

/// UTF-8 length of [s] in bytes (cheap for the common cases).
int utf8Length(String s) {
  if (s.length > Limits.maxPgnBytes) return s.length; // already over any cap we use
  var ascii = true;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) > 0x7f) {
      ascii = false;
      break;
    }
  }
  return ascii ? s.length : utf8.encode(s).length;
}

/// Truncates [s] so its UTF-8 encoding is at most [maxBytes] bytes, never
/// cutting a code point in half.
String truncateUtf8(String s, int maxBytes) {
  if (s.length * 3 <= maxBytes || utf8Length(s) <= maxBytes) return s;
  var bytes = 0;
  var i = 0;
  while (i < s.length) {
    final cu = s.codeUnitAt(i);
    int unitBytes;
    int units = 1;
    if (cu < 0x80) {
      unitBytes = 1;
    } else if (cu < 0x800) {
      unitBytes = 2;
    } else if (cu >= 0xD800 && cu <= 0xDBFF && i + 1 < s.length) {
      unitBytes = 4;
      units = 2;
    } else {
      unitBytes = 3;
    }
    if (bytes + unitBytes > maxBytes) break;
    bytes += unitBytes;
    i += units;
  }
  return s.substring(0, i);
}
