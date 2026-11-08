import 'package:flutter_test/flutter_test.dart';
import 'package:pegavideo/src/format.dart';

void main() {
  test('formata duração', () {
    expect(formatDuration(65), '1:05');
    expect(formatDuration(3725), '1:02:05');
    expect(formatDuration(null), '—');
  });

  test('formata tamanho', () {
    expect(formatBytes(1024), '1,00 KB');
    expect(formatBytes(null), '—');
  });
}
