import 'package:flutter_test/flutter_test.dart';
import 'package:quran_imam_shahid/core/intents.dart';

void main() {
  group('AppIntent.fromJson (client-side allow-list)', () {
    test('parses a known intent', () {
      final i = AppIntent.fromJson({'action': 'open_ayah', 'surah': 2, 'ayah': 255});
      expect(i, isA<OpenAyahIntent>());
      expect((i as OpenAyahIntent).ayah, 255);
    });

    test('parses play_recitation with from/to', () {
      final i = AppIntent.fromJson(
          {'action': 'play_recitation', 'surah': 36, 'from': 1, 'to': 5});
      expect(i, isA<PlayRecitationIntent>());
    });

    test('drops an unknown action (never executes it)', () {
      final i = AppIntent.fromJson({'action': 'run_shell', 'cmd': 'rm -rf /'});
      expect(i, isNull);
    });

    test('answer keeps confidence + sources', () {
      final i = AppIntent.fromJson({
        'action': 'answer',
        'text': 'x',
        'confidence': 'grounded',
        'sources': [
          {'book': 'al-Mizan', 'author': 'Tabatabai', 'ref': '1:5', 'lang': 'en'}
        ],
      }) as AnswerIntent;
      expect(i.confidence, 'grounded');
      expect(i.sources, hasLength(1));
    });
  });
}
