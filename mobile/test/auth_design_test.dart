import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zuzu/main.dart';

void main() {
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
        theme: ThemeData(useMaterial3: true),
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
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MaterialApp));
      await precacheImage(
        const AssetImage('assets/brand/welcome-logo.png'),
        context,
      );
      await precacheImage(
        const AssetImage('assets/brand/horizontal-logo.png'),
        context,
      );
    });
    await tester.pumpAndSettle();
  }

  testWidgets('welcome leads to the separate registration form', (
    tester,
  ) async {
    await screen(tester, const AuthPage());
    expect(find.byType(TextField), findsNothing);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/welcome.png'),
    );
    await tester.tap(find.text('Регистрация'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byType(Checkbox), findsNWidgets(3));
    await expectLater(
      find.byType(Scaffold).last,
      matchesGoldenFile('goldens/registration.png'),
    );
    await tester.tap(find.text('Получить код-пароль'));
    await tester.pumpAndSettle();
    expect(
      find.text('Подтвердите каждое согласие перед регистрацией.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('login has separate phone and email modes', (tester) async {
    await screen(tester, const AuthFormPage(registering: false));
    expect(find.text('Телефон'), findsOneWidget);
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/login-phone.png'),
    );
    await tester.tap(find.text('Войти с помощью электронной почты'));
    await tester.pumpAndSettle();
    expect(find.text('Почта'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auth supports enlarged text without overflow', (tester) async {
    await screen(tester, const AuthFormPage(registering: true), scale: 1.5);
    expect(tester.takeException(), isNull);
    await screen(tester, const AuthPage(), scale: 1.5);
    expect(tester.takeException(), isNull);
  });
}
