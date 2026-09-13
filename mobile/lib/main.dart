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
part 'features/auth/auth.dart';
part 'features/profiles/profiles.dart';
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
const brown = Color(0xff583a2b),
    orange = Color(0xffbe541a),
    yellow = Color(0xffffedb7),
    paper = Color(0xfffffdf9),
    muted = Color(0xff746b62);
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
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: paper,
      colorScheme: ColorScheme.fromSeed(
        seedColor: orange,
        primary: orange,
        secondary: brown,
        surface: paper,
      ),
      textTheme: ThemeData.light().textTheme.apply(
        bodyColor: brown,
        displayColor: brown,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: yellow,
        foregroundColor: brown,
        centerTitle: false,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xffeee8dd)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffddd5ca)),
        ),
        contentPadding: const EdgeInsets.all(18),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: yellow,
      ),
    ),
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
  int tab = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        Ru.text94,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 30,
          letterSpacing: -1,
        ),
      ),
      actions: [
        IconButton(
          tooltip: Ru.text337,
          onPressed: () => open(const SearchPage()),
          icon: const Icon(Icons.search),
        ),
        IconButton(
          tooltip: Ru.text103,
          onPressed: () => open(const NotificationsPage()),
          icon: const Icon(Icons.notifications_none),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (api.health['demo'] == true)
            Container(
              width: double.infinity,
              color: yellow.withValues(alpha: .45),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: const Text(
                Ru.text336,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, letterSpacing: 1.6),
              ),
            ),
          Expanded(
            child: switch (tab) {
              0 => ProfilePane(account: api.me!['id']),
              1 => const FeedPane(),
              2 => const ChatsPane(),
              3 => const MapPane(),
              _ => const MenuPane(),
            },
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.pets_outlined),
          label: Ru.text228,
        ),
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          label: Ru.text335,
        ),
        NavigationDestination(
          icon: Icon(Icons.chat_bubble_outline),
          label: Ru.text334,
        ),
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          label: Ru.text333,
        ),
        NavigationDestination(icon: Icon(Icons.menu), label: Ru.text332),
      ],
    ),
  );
}
