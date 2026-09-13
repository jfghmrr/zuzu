import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuzu/core/api.dart';
import 'package:zuzu/core/platform_services.dart';
import 'package:zuzu/main.dart';

void main() {
  test('calendar day labels use dates, not elapsed hours', () {
    expect(
      relativeDay(DateTime(2026, 9, 14, 0, 1), DateTime(2026, 9, 13, 23, 59)),
      'Завтра',
    );
    expect(
      relativeDay(DateTime(2026, 9, 13, 9), DateTime(2026, 9, 13, 22)),
      'Сегодня',
    );
    expect(
      relativeDay(DateTime(2026, 9, 12), DateTime(2026, 9, 13)),
      'Просрочено',
    );
  });
  test('notification identifiers are stable and bounded', () {
    final p = PlatformServices();
    expect(p.id('reminder-a'), p.id('reminder-a'));
    expect(p.id('reminder-a'), isNot(p.id('reminder-b')));
    expect(p.id('reminder-a'), inInclusiveRange(0, 0x7fffffff));
  });
  test(
    'API propagates Russian error and preserves idempotency payload',
    () async {
      String? body;
      final a = Api(
        client: MockClient((r) async {
          body = r.body;
          return http.Response(
            jsonEncode({'detail': 'Запись недоступна.'}),
            404,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await expectLater(
        a.call('POST', '/items/posts', {
          'id': 'stable-id',
          'data': {'text': 'Привет'},
        }),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.message,
            'message',
            'Запись недоступна.',
          ),
        ),
      );
      expect(jsonDecode(body!)['id'], 'stable-id');
    },
  );
  testWidgets('empty state fits a narrow device with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: ListView(
              children: const [
                Empty(
                  'Здоровье под заботой',
                  'Сохраните документы питомца. Их видите только вы.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Здоровье под заботой'), findsOneWidget);
  });
  testWidgets(
    'successful save leaves dirty form without a second confirmation',
    (tester) async {
      final original = api;
      api = Api(
        client: MockClient(
          (r) async => http.Response(
            jsonEncode({
              'id': 'saved',
              'kind': 'posts',
              'data': {'text': 'A moment'},
            }),
            200,
          ),
        ),
      );
      addTearDown(() {
        api = original;
      });
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          scaffoldMessengerKey: messenger,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ItemEditor(kind: 'posts'),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'A moment');
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();
      expect(find.byType(ItemEditor), findsNothing);
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
