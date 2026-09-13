part of '../../main.dart';

class MenuPane extends StatelessWidget {
  const MenuPane({super.key});
  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset('assets/brand/wordmark.png', width: 80, height: 34),
            IconButton(
              tooltip: 'Закрыть меню',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.chevron_left, color: ink),
            ),
          ],
        ),
        const SizedBox(height: 32),
        entry(context, 'envelope', 'Обратная связь', const FeedbackPage()),
        const Divider(color: Color(0xffe8d981)),
        entry(context, 'help', 'Часто задаваемые вопросы', const FaqPage()),
        const Divider(color: Color(0xffe8d981)),
        entry(context, 'settings', 'Настройки', const SettingsPage()),
      ],
    ),
  );
  Widget entry(BuildContext context, String icon, String title, Widget page) =>
      InkWell(
        onTap: () {
          Navigator.pop(context);
          open(page);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Row(
            children: [
              DesignIcon(icon, color: const Color(0xff583c26)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xff583c26),
                    height: 24 / 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key});
  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final name = TextEditingController(),
      email = TextEditingController(),
      message = TextEditingController();
  final form = GlobalKey<FormState>();
  final id = const Uuid().v4();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.call('POST', '/items/feedback', {
        'id': id,
        'data': {
          'name': name.text.trim(),
          'email': email.text.trim(),
          'text': message.text.trim(),
        },
      });
      if (mounted) {
        Navigator.pop(context);
        note('Спасибо! Ваше сообщение отправлено.');
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Обратная связь',
    child: ListView(
      padding: const EdgeInsets.all(15),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Мы очень любим животных и делаем всё, чтобы улучшить их жизнь, а также решать проблемы, с которыми Вы сталкиваетесь.\n\nПоэтому нам очень важно Ваше мнение об этом приложении.',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    height: 20 / 14,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: name,
                  enabled: !busy,
                  decoration: const InputDecoration(hintText: 'Имя'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Укажите имя' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Электронная почта',
                  ),
                  validator: (v) =>
                      RegExp(
                        r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                      ).hasMatch((v ?? '').trim())
                      ? null
                      : 'Укажите электронную почту',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: message,
                  enabled: !busy,
                  minLines: 8,
                  maxLines: 12,
                  decoration: const InputDecoration(hintText: 'Ваше мнение'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Напишите сообщение' : null,
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 20),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xfff5a623),
                    minimumSize: const Size(48, 54),
                  ),
                  onPressed: busy ? null : send,
                  child: Text(busy ? 'Отправка…' : 'Отправить'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class FaqPage extends StatelessWidget {
  const FaqPage({super.key});
  static const questions = {
    Ru.text132: Ru.text131,
    Ru.text130: Ru.text129,
    Ru.text128: Ru.text127,
    Ru.text126: Ru.text125,
    Ru.text124: Ru.text123,
    Ru.text122: Ru.text121,
    Ru.text120: Ru.text119,
    Ru.text118: Ru.text117,
    Ru.text116: Ru.text115,
  };
  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text114,
    child: ListView(
      padding: const EdgeInsets.all(18),
      children: questions.entries
          .map(
            (e) => Card(
              child: ExpansionTile(
                title: Text(e.key),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    child: Text(e.value, style: const TextStyle(height: 1.5)),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

class LegalPage extends StatefulWidget {
  final String kind;
  const LegalPage({super.key, required this.kind});
  @override
  State<LegalPage> createState() => _LegalPageState();
}

class _LegalPageState extends State<LegalPage> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = api.call('GET', '/legal/${widget.kind}');
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.kind == 'privacy' ? Ru.text97 : Ru.text96,
    child: FutureBuilder(
      future: future,
      builder: (c, s) {
        if (s.hasError) {
          return Failure(
            message: '${s.error}',
            retry: () => setState(
              () => future = api.call('GET', '/legal/${widget.kind}'),
            ),
          );
        }
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (s.data['approved'] != true)
              const Text(
                Ru.text113,
                style: TextStyle(color: orange, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 12),
            Text('Версия: ${s.data['version']}'),
            const SizedBox(height: 22),
            SelectableText(s.data['text'], style: const TextStyle(height: 1.6)),
          ],
        );
      },
    ),
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Map<String, dynamic>? settings;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final d = await api.call('GET', '/settings');
      if (mounted) setState(() => settings = Map<String, dynamic>.from(d));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> push(bool v) async {
    if (!v && !await confirm(Ru.text112, Ru.text111)) {
      return;
    }
    setState(() => busy = true);
    try {
      await api.call('PUT', '/settings', {'push': v});
      if (v) await platform.requestPermission();
      await platform.syncReminders(api);
      await load();
    } catch (e) {
      note(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    if (!await confirm(Ru.text110, Ru.text109)) {
      return;
    }
    await guarded(() async {
      await api.call('POST', '/auth/logout');
      await platform.clear();
      await api.clear();
    });
  }

  Future<void> remove() async {
    final c = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Ru.text108),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(Ru.text107),
            const SizedBox(height: 16),
            TextField(controller: c),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(Ru.text12),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text(Ru.text106),
          ),
        ],
      ),
    );
    if (value != Ru.text105) return;
    await guarded(() async {
      await api.call('DELETE', '/me', {'confirmation': value});
      await platform.clear();
      await api.clear();
    });
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text104,
    child: settings == null
        ? error != null
              ? Failure(message: error!, retry: load)
              : const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Card(
                child: SwitchListTile(
                  title: const Text(Ru.text103),
                  subtitle: const Text(Ru.text102),
                  value: settings!['push'] != false,
                  onChanged: busy ? null : push,
                ),
              ),
              if (platform.pushError != null)
                Text(platform.pushError!, style: const TextStyle(color: muted)),
              if (!kIsWeb)
                ListTile(
                  title: const Text(Ru.text101),
                  onTap: () => Geolocator.openAppSettings(),
                ),
              ListTile(
                title: const Text(Ru.text100),
                onTap: () => open(const RelationshipsPage(blocked: true)),
              ),
              ListTile(
                title: const Text(Ru.text99),
                subtitle: const Text(Ru.text98),
                onTap: () => open(const LinkContactPage()),
              ),
              for (final contact in api.me!['contacts'] ?? [])
                ListTile(
                  dense: true,
                  title: Text('$contact'),
                  leading: const Icon(Icons.check_circle_outline, color: muted),
                ),
              ListTile(
                title: const Text(Ru.text97),
                onTap: () => open(const LegalPage(kind: 'privacy')),
              ),
              ListTile(
                title: const Text(Ru.text96),
                onTap: () => open(const LegalPage(kind: 'terms')),
              ),
              ListTile(
                title: const Text(Ru.text95),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: Ru.text94,
                  applicationVersion: '0.1.0',
                ),
              ),
              const ExpansionTile(
                title: Text(Ru.text93),
                children: [
                  Padding(padding: EdgeInsets.all(16), child: Text(Ru.text92)),
                ],
              ),
              if (const String.fromEnvironment('APP_STORE_URL') != '')
                ListTile(
                  title: const Text(Ru.text91),
                  onTap: () => launchUrl(
                    Uri.parse(const String.fromEnvironment('APP_STORE_URL')),
                  ),
                ),
              const SizedBox(height: 18),
              OutlinedButton(onPressed: logout, child: const Text(Ru.text90)),
              const SizedBox(height: 10),
              TextButton(
                onPressed: remove,
                child: const Text(
                  Ru.text89,
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
  );
}

class LinkContactPage extends StatefulWidget {
  const LinkContactPage({super.key, this.initialContact = ''});
  final String initialContact;
  @override
  State<LinkContactPage> createState() => _LinkContactPageState();
}

class _LinkContactPageState extends State<LinkContactPage> {
  final contact = TextEditingController(), code = TextEditingController();
  Map<String, dynamic>? challenge;
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    contact.text = widget.initialContact;
  }

  @override
  void dispose() {
    contact.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      if (challenge == null) {
        challenge = Map<String, dynamic>.from(
          await api.call('POST', '/auth/request', {
            'contact': contact.text.trim(),
            'link': true,
          }),
        );
      } else {
        await api.call('POST', '/auth/verify', {
          'challenge_id': challenge!['challenge_id'],
          'code': code.text.trim(),
        });
        await api.refreshMe();
        if (mounted) Navigator.pop(context);
        note(Ru.text88);
      }
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text87,
    child: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(Ru.text86),
        const SizedBox(height: 20),
        TextField(
          controller: contact,
          enabled: challenge == null && !busy,
          decoration: const InputDecoration(labelText: Ru.text85),
        ),
        if (challenge != null) ...[
          const SizedBox(height: 20),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: const InputDecoration(labelText: Ru.text84),
          ),
          if (challenge!['dev_code'] != null)
            Text('DEV-код: ${challenge!['dev_code']}'),
          TextButton(
            onPressed: busy ? null : () => setState(() => challenge = null),
            child: const Text(Ru.text83),
          ),
        ],
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : submit,
          child: Text(
            busy
                ? Ru.text82
                : challenge == null
                ? Ru.text81
                : Ru.text70,
          ),
        ),
      ],
    ),
  );
}
