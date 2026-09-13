# Внешние интеграции и выпуск

Все значения без секретов перечислены в `.env.example`. Клиентские `--dart-define` не предназначены для привилегированных ключей.

| Интеграция | Статус | Что требуется |
|---|---|---|
| Локальный API и SQLite | Реализована и проверена автоматическими тестами и частью UI smoke | Python, команда README |
| PostgreSQL / Docker Compose | Реализована, требуется проверка развёртывания | Работающий Docker, пароль, хост и регион |
| OTP в локальном режиме | Временный деморежим | AUTH_MODE=dev; код виден на экране |
| Реальные SMS/email | Реализован webhook-адаптер, нужны провайдер и конфигурация; реальная доставка не проверена | OTP_WEBHOOK_URL/TOKEN; выбор страны и провайдера |
| Карта Flutter Map | Реализована; тайлы проверены в браузере, данные/географический фильтр проверены API | MAP_TILE_URL, MAP_ATTRIBUTION; согласованный поставщик тайлов для выпуска |
| Камера и фото | Реализованы платформенные адаптеры; серверная загрузка/ACL проверены | Проверка на реальных iOS/Android; разрешения |
| Локальные напоминания | Код реализован, системная доставка не проверена | Разрешения ОС, smoke на устройстве, смена timezone/DST |
| FCM/APNs | Клиент, токены устройств и серверный outbox реализованы; нужны Firebase/APNs и push bridge | ENABLE_PUSH=true, Firebase native config, APNs key, сервер доставки |
| Юридические документы | Утверждённый контент не предоставлен | LEGAL_DIR/privacy.txt, terms.txt и LEGAL_VERSION |
| TestFlight | Не загружено | Apple Developer, signing, provisioning и релизная проверка |
| Ссылка оценки магазина | Реализовано условное открытие, URL не настроен | APP_STORE_URL после создания карточки приложения |

## OTP bridge

`AUTH_MODE=webhook` отправляет HTTPS POST на `OTP_WEBHOOK_URL` с `Authorization: Bearer <OTP_WEBHOOK_TOKEN>` и JSON:

```json
{"contact":"+79991234567","code":"123456","expires_in":300,"id":"challenge-uuid"}
```

Bridge определяет email/телефон, вызывает выбранного провайдера и возвращает 2xx **после принятия провайдером**. Не логируйте код или контакт. `id` используйте как ключ идемпотентности. Ошибка bridge приводит к сообщению о недоступности доставки; клиент не получает успех. Срок кода — 5 минут, до 5 попыток, интервал повторной отправки 60 секунд, ограничения на контакт и IP. Коды не сохраняются открытым текстом. Непроверенный контакт не добавляется в способы входа.

В production задайте APP_ENV=production, AUTH_MODE=webhook и утверждённые документы. Startup отказывает при dev-авторизации или отсутствии файлов/версий. Доставка через конкретного поставщика и антифрод по номеру/региону требуют отдельной проверки.

## Push bridge и Firebase

1. Создайте Firebase project с iOS bundle `app.zuzu.zuzu` и Android application id `app.zuzu.zuzu` (либо измените оба до выпуска).
2. Добавьте `GoogleService-Info.plist` в target Runner и `google-services.json` в Android app. Не публикуйте серверный service-account key в клиенте. Для Android подключите Google Services Gradle plugin по актуальной Firebase-инструкции.
3. Apple Developer → App ID: Push Notifications. В Xcode Signing & Capabilities добавьте Push Notifications и Background Modes → Remote notifications. Загрузите APNs authentication key в Firebase.
4. Собирайте с `--dart-define=ENABLE_PUSH=true`. Без этого ключа подключение к Firebase не имитируется.
5. `PUSH_WEBHOOK_URL/TOKEN` — защищённый серверный bridge, принимающий `{id,tokens,notification:{title,body},data:{route,target}}`. Он вызывает FCM HTTP v1, удаляет invalid/unregistered device tokens по контракту выбранного bridge и дедуплицирует event id. Payload не содержит текста личного сообщения. Повторное уведомление при неопределённом timeout предотвращает bridge.
6. Запустите один worker. Проверьте background/terminated delivery и переход после авторизации. Выход удаляет привязку текущего устройства; блокировка и настройка push проверяются перед отправкой.

Документация: https://firebase.google.com/docs/cloud-messaging/flutter/get-started и https://firebase.google.com/docs/cloud-messaging/send/v1-api . Реальная доставка ещё не подтверждена.

## iOS / TestFlight

После установки полного Xcode и simulator runtime:

```sh
cd mobile
flutter pub get
flutter build ios --release --no-codesign
open ios/Runner.xcworkspace
```

В Xcode: выберите Team, уникальный Bundle Identifier, signing certificate и профиль provisioning. Добавьте capabilities Push и Keychain Sharing при необходимости выбранной версии secure storage; проверьте entitlement и privacy manifests зависимостей. URL scheme `zuzu` и описания камеры/фото/геолокации подготовлены. HTTP разрешён только для локального окружения; production API должен использовать HTTPS.

Для архива: Product → Archive → Validate → Distribute → App Store Connect. Заполните privacy labels по реально включённым SDK, предоставьте review account, контакты поддержки, утверждённые правила и процесс модерации. Проверить UGC, блокировки, удаление аккаунта и полноту функций по https://developer.apple.com/app-store/review/guidelines/ и https://developer.apple.com/support/offering-account-deletion-in-your-app . Здесь нет утверждения о соответствии магазинам или приёмке Apple.

## Android

Установите Android SDK и JDK, совместимый с текущим Gradle. Разрешения и local notifications receivers подготовлены, cleartext разрешён только в debug. Release signing намеренно не использует debug key. Создайте keystore вне репозитория, задайте release signingConfig. Проверьте системную кнопку «Назад», восстановление activity после image picker, запрет камеры/фото, approximate location, Android notification permission, background restrictions и работу ссылок. Общий код не заменяет проверку устройства.
