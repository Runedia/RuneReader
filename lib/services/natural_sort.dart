final _chunk = RegExp(r'(\d+)|(\D+)');

/// Compares strings so that embedded numbers sort numerically
/// (`2.jpg` < `10.jpg`), case-insensitively.
int naturalCompare(String a, String b) {
  final ca = _chunk.allMatches(a.toLowerCase()).toList();
  final cb = _chunk.allMatches(b.toLowerCase()).toList();
  for (var i = 0; i < ca.length && i < cb.length; i++) {
    final x = ca[i], y = cb[i];
    final xd = x.group(1), yd = y.group(1);
    int c;
    if (xd != null && yd != null) {
      c = BigInt.parse(xd).compareTo(BigInt.parse(yd));
      if (c == 0) c = xd.length.compareTo(yd.length);
    } else {
      c = x.group(0)!.compareTo(y.group(0)!);
    }
    if (c != 0) return c;
  }
  return ca.length.compareTo(cb.length);
}
