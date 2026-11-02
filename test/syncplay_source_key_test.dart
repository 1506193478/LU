import 'package:flutter_test/flutter_test.dart';
import 'package:XL/services/player/syncplay_source_key.dart';

void main() {
  group('syncPlaySourceKey', () {
    test('LU 自己的标记能解析出番剧 id 与集数', () {
      final key = syncPlaySourceKey('12345[7]');
      expect(key, isNotNull);
      expect(key!.kind, 'lu');
      expect(key.title, '12345');
      expect(key.episode, 7);
    });

    test('真实文件名能抽出集数并剥掉画质噪音', () {
      final key = syncPlaySourceKey(
        '[Lilith-Raws] Shingeki no Kyojin - 05 [Baha][WEB-DL][1080p][AVC AAC][CHT].mp4',
      );
      expect(key, isNotNull);
      expect(key!.kind, 'file');
      expect(key.episode, 5);
      expect(key.title.contains('shingeki'), isTrue);
      expect(key.title.contains('1080p'), isFalse);
      expect(key.title.contains('web-dl'), isFalse);
    });

    test('S01E02 形态', () {
      expect(syncPlaySourceKey('Frieren.S01E02.2160p.mkv')!.episode, 2);
    });

    test('中文「第 N 集」形态', () {
      expect(syncPlaySourceKey('葬送的芙莉莲 第12集.mkv')!.episode, 12);
    });

    test('空值不产生 key', () {
      expect(syncPlaySourceKey(''), isNull);
      expect(syncPlaySourceKey(null), isNull);
      expect(syncPlaySourceKey('   '), isNull);
    });
  });

  group('syncPlaySourcesDiffer', () {
    test('同一集不同清晰度不算「在看别的」', () {
      // 这是原来最刺眼的一条：同一个源换清晰度，文件名不同，被判成两边在看不同的东西。
      expect(
        syncPlaySourcesDiffer(
          '[Group] Show - 05 [1080p].mkv',
          '[Group] Show - 05 [720p].mkv',
        ),
        isFalse,
      );
    });

    test('集数不同就是不同', () {
      expect(
        syncPlaySourcesDiffer('[Group] Show - 05 [1080p].mkv',
            '[Group] Show - 06 [1080p].mkv'),
        isTrue,
      );
    });

    test('换了番剧就是不同', () {
      expect(syncPlaySourcesDiffer('12345[3]', '99999[3]'), isTrue);
    });

    test('同一个番剧同一集不算不同', () {
      expect(syncPlaySourcesDiffer('12345[3]', '12345[3]'), isFalse);
    });

    test('LU 标记和真实文件名混用时不误报', () {
      // 房间里混进官方 Syncplay 客户端时上传的是真实文件名，两者标题无从
      // 对齐，只能靠集数判断；集数一致就不该报「有人在看别的」。
      expect(
        syncPlaySourcesDiffer('12345[5]', 'Some Anime - 05 [1080p].mkv'),
        isFalse,
      );
    });

    test('信息不足时不报（宁可漏报）', () {
      expect(syncPlaySourcesDiffer(null, '12345[5]'), isFalse);
      expect(syncPlaySourcesDiffer('12345[5]', null), isFalse);
    });

    test('同名但不同番剧（无集数可比）能区分', () {
      expect(
        syncPlaySourcesDiffer(
          '[A] Sword Art Online [1080p].mkv',
          '[B] Sword Art Online II [1080p].mkv',
        ),
        isTrue,
      );
    });
  });
}
