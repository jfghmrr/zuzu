import 'core/ru.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:app_links/app_links.dart';
import 'core/api.dart';
import 'core/platform_services.dart';
part 'core/widgets.dart';
part 'core/design.dart';
part 'features/auth/auth.dart';
part 'features/auth/welcome.dart';
part 'features/profiles/profiles.dart';
part 'features/profiles/owner.dart';
part 'features/feed/feed.dart';
part 'features/stories/stories.dart';
part 'features/relationships/relationships.dart';
part 'features/chat/chat.dart';
part 'features/vet_records/vet_records.dart';
part 'features/reminders/reminders.dart';
part 'features/map/map.dart';
part 'features/notifications/notifications.dart';
part 'features/settings/settings.dart';

Api api = Api();
final platform = PlatformServices();
final nav = GlobalKey<NavigatorState>();
final messenger = GlobalKey<ScaffoldMessengerState>();
const brown = Color(0xff996440),
    orange = Color(0xffffb85c),
    yellow = Color(0xfffbeb90),
    paper = Color(0xfff6f6f6),
    ink = Color(0xff39434f),
    muted = Color(0xff6c7787),
    iconGrey = Color(0xffb3c0d2),
    divider = Color(0xffe6ebf1);
String? pendingRoute;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ZuzuApp());
}

void note(Object message) {
  messenger.currentState?.showSnackBar(SnackBar(content: Text('$message')));
}

Future<T?> open<T>(Widget page) =>
    nav.currentState!.push<T>(MaterialPageRoute(builder: (_) => page));
Future<void> routeTo(String raw) async {
  pendingRoute = raw;
  if (api.me == null || api.me!['pet'] == null) return;
  try {
    Map<String, dynamic> d;
    if (raw.startsWith('{')) {
      d = Map<String, dynamic>.from(jsonDecode(raw));
    } else {
      final u = Uri.parse(raw);
      final segments = [if (u.host.isNotEmpty) u.host, ...u.pathSegments];
      if (segments.length < 2) {
        throw ApiFailure(Ru.text340);
      }
      d = {'route': segments[0], 'target': segments[1]};
    }
    pendingRoute = null;
    switch (d['route']) {
      case 'profile':
        await open(
          PageFrame(
            title: Ru.text228,
            child: ProfilePane(account: d['target']),
          ),
        );
      case 'chat':
        await open(ChatPage(cid: d['target']));
      case 'reminder':
      case 'reminders':
      case 'item':
        final item = await api.call('GET', '/item/${d['target']}');
        await open(ItemPage(item: Map<String, dynamic>.from(item)));
      default:
        note(Ru.text339);
    }
  } catch (e) {
    note(e);
  }
}

class ZuzuApp extends StatefulWidget {
  const ZuzuApp({super.key});
  @override
  State<ZuzuApp> createState() => _ZuzuAppState();
}

class _ZuzuAppState extends State<ZuzuApp> with WidgetsBindingObserver {
  bool loading = true;
  String? error;
  StreamSubscription<Uri>? links;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    api.addListener(changed);
    boot();
  }

  void changed() {
    if (!mounted) return;
    if (api.token == null) {
      nav.currentState?.popUntil((r) => r.isFirst);
      platform.clear();
    }
    setState(() {});
  }

  Future<void> boot() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      platform.onRoute = routeTo;
      await api.init();
      try {
        await platform.init();
      } catch (_) {
        platform.pushError = Ru.text338;
      }
      if (!kIsWeb) {
        final appLinks = AppLinks();
        final initial = await appLinks.getInitialLink();
        if (initial != null) pendingRoute = initial.toString();
        links = appLinks.uriLinkStream.listen((u) => routeTo(u.toString()));
      }
      if (api.me != null) {
        await platform.connectPush(api);
        try {
          await platform.syncReminders(api);
        } catch (_) {}
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
    if (pendingRoute != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => routeTo(pendingRoute!),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && api.me != null) {
      api.invalidateImages();
      platform.syncReminders(api).catchError((_) {});
    }
  }

  @override
  void dispose() {
    api.removeListener(changed);
    links?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: Ru.text94,
    navigatorKey: nav,
    scaffoldMessengerKey: messenger,
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: zuzuTheme(),
    home: loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : error != null
        ? Scaffold(
            body: Center(
              child: Failure(message: error!, retry: boot),
            ),
          )
        : api.me == null
        ? const AuthPage()
        : api.me!['pet'] == null || (api.me!['owner'] as Map).isEmpty
        ? const ProfileEditor(onboarding: true)
        : const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final scaffold = GlobalKey<ScaffoldState>();
  int tab = 0;
  int revision = 0;
  Future<void> create() async {
    await open(const ItemEditor(kind: 'posts'));
    if (mounted) setState(() => revision++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffold,
    drawer: Drawer(
      width: MediaQuery.sizeOf(context).width * 308 / 375,
      backgroundColor: yellow,
      shape: const RoundedRectangleBorder(),
      child: const MenuPane(),
    ),
    drawerEnableOpenDragGesture: false,
    backgroundColor: tab == 1 || tab == 2 ? Colors.white : paper,
    appBar: AppBar(
      toolbarHeight: tab == 0 ? 54 : 46,
      title: tab == 2 || tab == 3
          ? Text(
              tab == 2 ? 'Чаты' : 'Карта',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            )
          : const BrandWordmark(),
      leading: tab == 2 || tab == 3
          ? null
          : tab == 1
          ? IconButton(
              tooltip: 'Создать публикацию',
              onPressed: create,
              icon: const DesignIcon('plus', color: ink),
            )
          : IconButton(
              tooltip: 'Мой питомец',
              onPressed: () => open(
                PageFrame(
                  title: Ru.text94,
                  child: ProfilePane(account: api.me!['id']),
                ),
              ),
              icon: Padding(
                padding: const EdgeInsets.all(5),
                child: Image.asset(
                  'assets/brand/welcome-logo.png',
                  width: 28,
                  height: 28,
                ),
              ),
            ),
      actions: [
        if (tab == 1)
          IconButton(
            tooltip: Ru.text103,
            onPressed: () => open(const NotificationsPage()),
            icon: const DesignIcon('bell', color: ink),
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      bottom: false,
      child: switch (tab) {
        0 => const OwnerPane(),
        1 => FeedPane(key: ValueKey(revision)),
        2 => const ChatsPane(),
        3 => const MapPane(),
        _ => const MenuPane(),
      },
    ),
    bottomNavigationBar: ZuzuNavigationBar(
      selected: tab,
      onSelected: (value) {
        if (value == 4) {
          scaffold.currentState!.openDrawer();
        } else {
          setState(() => tab = value);
        }
      },
    ),
  );
}
