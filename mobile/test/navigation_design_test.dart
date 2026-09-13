import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zuzu/core/api.dart';
import 'package:zuzu/main.dart';

void main() {
  late Api previous;
  late Map<String, dynamic> profile;
  late List<http.Request> requests;
  setUpAll(() async {
    final font = FontLoader('NotoSans');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/NotoSans-$weight.ttf'));
    }
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  setUp(() {
    previous = api;
    requests = [];
    profile = {
      'id': 'design-test',
      'created': 1700000000,
      'handle': 'owner_test',
      'level': 'Новый друг',
      'achievements': 0,
      'friends': 0,
      'followers': 0,
      'owner': {
        'name': 'Анна',
        'surname': 'Иванова',
        'status': 'Заботливый хозяин',
      },
      'pet': {
        'name': 'Луна',
        'handle': 'luna_test',
        'species': 'Игуана',
        'city': 'Москва',
        'description': '',
      },
    };
    api = Api(
      client: MockClient((r) async {
        requests.add(r);
        dynamic response = {'items': [], 'next': null};
        if (r.method == 'PUT' && r.url.path == '/me/profile') {
          profile['owner'] = jsonDecode(r.body);
        }
        if (r.method == 'POST' && r.url.path == '/pets') {
          profile['pet'] = jsonDecode(r.body);
        }
        if (r.url.path == '/me' || r.url.path.startsWith('/profiles/')) {
          response = profile;
        }
        return http.Response(
          jsonEncode(response),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..me = profile;
  });
  tearDown(() {
    api.client.close();
    api = previous;
  });

  Future<void> screen(
    WidgetTester tester,
    Widget page, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        scaffoldMessengerKey: messenger,
        theme: zuzuTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 44, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 44, bottom: 34),
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: page,
      ),
    );
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MaterialApp));
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final path in manifest.listAssets().where(
        (s) => s.startsWith('assets/') && s.endsWith('.png'),
      )) {
        await precacheImage(AssetImage(path), context);
      }
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'two onboarding steps retain owner data and save arbitrary species',
    (tester) async {
      profile['owner'] = <String, dynamic>{};
      profile['pet'] = null;
      profile['handle'] = null;
      await screen(tester, const ProfileEditor(onboarding: true));
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/onboarding-owner.png'),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Анна');
      await tester.enterText(find.byType(TextFormField).at(1), 'Иванова');
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      expect(find.text('Вид питомца'), findsOneWidget);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/onboarding-pet.png'),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Луна');
      await tester.enterText(find.byType(TextFormField).at(1), 'Игуана');
      await tester.enterText(find.byType(TextFormField).at(4), 'Москва');
      await tester.ensureVisible(find.text('Готово'));
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      final owner = jsonDecode(
        requests.singleWhere((r) => r.method == 'PUT').body,
      );
      final pet = jsonDecode(
        requests.singleWhere((r) => r.method == 'POST').body,
      );
      expect(owner['name'], 'Анна');
      expect(owner['surname'], 'Иванова');
      expect(pet['species'], 'Игуана');
      expect(pet['name'], 'Луна');
      expect(owner['handle'], startsWith('u_'));
      expect(pet['handle'], startsWith('p_'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('native navigation keeps sections and opens Figma menu drawer', (
    tester,
  ) async {
    await screen(tester, const HomePage());
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/owner-profile.png'),
    );
    await tester.tap(find.byTooltip('Лента'));
    await tester.pumpAndSettle();
    expect(find.byType(FeedPane), findsOneWidget);
    await tester.tap(find.byTooltip('Чаты'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatsPane), findsOneWidget);
    await tester.tap(find.byTooltip('Меню'));
    await tester.pumpAndSettle();
    expect(find.text('Обратная связь'), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/menu.png'),
    );
    await tester.tap(find.byTooltip('Закрыть меню'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatsPane), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owner onboarding and navigation fit enlarged text', (
    tester,
  ) async {
    await screen(tester, const HomePage(), scale: 1.5);
    expect(tester.takeException(), isNull);
    await screen(tester, const ProfileEditor(onboarding: true), scale: 1.5);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
