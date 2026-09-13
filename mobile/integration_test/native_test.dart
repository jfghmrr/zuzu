import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zuzu/core/api.dart';
import 'package:zuzu/core/platform_services.dart';
import 'package:zuzu/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native auth, Keychain, onboarding and navigation', (
    tester,
  ) async {
    final client = Api();
    await client.init();
    expect(client.health['demo'], isTrue);
    final previousToken = client.token;
    final services = PlatformServices();
    await services.init();
    expect(services.ready, isTrue);
    expect(services.zone, isNotEmpty);
    final challenge = await client.call('POST', '/auth/request', {
      'contact': 'native-${DateTime.now().microsecondsSinceEpoch}@example.test',
    });
    final session = await client.call('POST', '/auth/verify', {
      'challenge_id': challenge['challenge_id'],
      'code': challenge['dev_code'],
      'device': client.device,
      'privacy': client.health['legal_version'],
      'terms': client.health['legal_version'],
    });
    Future<void> settle() async {
      for (var i = 0; i < 80; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty && i > 8) {
          break;
        }
      }
    }

    try {
      await client.clear();
      app.main();
      await settle();
      expect(find.byType(app.WelcomePage), findsOneWidget);
      await binding.takeScreenshot('ios-welcome');
      await tester.tap(find.text('У вас уже есть аккаунт?'));
      await tester.pumpAndSettle();
      expect(find.text('Войти'), findsOneWidget);
      await binding.takeScreenshot('ios-login');
      app.nav.currentState!.pop();
      await tester.pumpAndSettle();
      await app.api.login(session['token']);
      await settle();
      final restored = Api();
      await restored.init();
      expect(restored.token, app.api.token);
      expect(restored.me!['id'], app.api.me!['id']);
      expect(restored.device, app.api.device);
      expect(find.text('Ваш профиль'), findsOneWidget);
      await binding.takeScreenshot('ios-onboarding-owner');
      await tester.enterText(find.byType(TextFormField).at(0), 'Тест');
      await tester.enterText(find.byType(TextFormField).at(1), 'Проверка');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Далее'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Луна');
      await tester.enterText(find.byType(TextFormField).at(1), 'Игуана');
      await tester.enterText(find.byType(TextFormField).at(4), 'Москва');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Готово'));
      await tester.tap(find.text('Готово'));
      await settle();
      expect(find.byType(app.HomePage), findsOneWidget);
      await binding.takeScreenshot('ios-owner-profile');
      await tester.tap(find.byTooltip('Лента'));
      await settle();
      expect(find.byType(app.FeedPane), findsOneWidget);
      await tester.tap(find.byTooltip('Чаты'));
      await settle();
      expect(find.byType(app.ChatsPane), findsOneWidget);
      await tester.tap(find.byTooltip('Меню'));
      await tester.pumpAndSettle();
      expect(find.text('Обратная связь'), findsOneWidget);
      await binding.takeScreenshot('ios-menu');
      expect(find.byType(app.Failure), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      // Remove the temporary native-test account and restore the user's session.
      await app.api.login(session['token']);
      await app.api.call('DELETE', '/me', {'confirmation': 'УДАЛИТЬ'});
      if (previousToken == null) {
        await app.api.clear();
      } else {
        await app.api.login(previousToken);
      }
    }
  });
}
