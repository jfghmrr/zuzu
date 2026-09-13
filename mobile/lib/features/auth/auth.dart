part of '../../main.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final contact = TextEditingController(), code = TextEditingController();
  bool email = true, busy = false, privacy = false, terms = false;
  Map<String, dynamic>? challenge;
  String? error;
  int cooldown = 0;
  Timer? timer;
  @override
  void dispose() {
    contact.dispose();
    code.dispose();
    timer?.cancel();
    super.dispose();
  }

  Future<void> request() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      challenge = Map<String, dynamic>.from(
        await api.call('POST', '/auth/request', {
          'contact': contact.text.trim(),
        }),
      );
      cooldown = 60;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => cooldown = cooldown > 0 ? cooldown - 1 : 0);
      });
    } catch (e) {
      error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await api.call('POST', '/auth/verify', {
        'challenge_id': challenge!['challenge_id'],
        'code': code.text.trim(),
        'device': api.device,
        'privacy': privacy ? api.health['legal_version'] : null,
        'terms': terms ? api.health['legal_version'] : null,
      });
      await api.login(v['token']);
      await platform.connectPush(api);
      if (pendingRoute != null) await routeTo(pendingRoute!);
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> document(String kind) async {
    await open(LegalPage(kind: kind));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: yellow,
                  borderRadius: BorderRadius.circular(36),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.pets, size: 64, color: brown),
                    SizedBox(height: 12),
                    Text(
                      Ru.text94,
                      style: TextStyle(
                        fontSize: 58,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -3,
                      ),
                    ),
                    Text(Ru.text179, style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              Text(
                challenge == null ? Ru.text178 : Ru.text177,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 1.16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                challenge == null ? Ru.text176 : Ru.text175,
                style: const TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              if (api.health['demo'] == true)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: Text(
                    Ru.text174,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ),
              if (challenge == null) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Email')),
                    ButtonSegment(value: false, label: Text(Ru.text173)),
                  ],
                  selected: {email},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() {
                          email = v.first;
                          contact.clear();
                        }),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: contact,
                  enabled: !busy,
                  keyboardType: email
                      ? TextInputType.emailAddress
                      : TextInputType.phone,
                  autofillHints: email
                      ? [AutofillHints.email]
                      : [AutofillHints.telephoneNumber],
                  decoration: InputDecoration(
                    labelText: email ? Ru.text172 : Ru.text171,
                    hintText: email ? 'you@example.com' : '+7 999 123-45-67',
                  ),
                ),
              ] else ...[
                Text(
                  contact.text,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                AutofillGroup(
                  child: TextField(
                    controller: code,
                    enabled: !busy,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    style: const TextStyle(fontSize: 30, letterSpacing: 9),
                    decoration: const InputDecoration(labelText: Ru.text170),
                    onSubmitted: (_) => verify(),
                  ),
                ),
                if (challenge!['dev_code'] != null)
                  SelectableText(
                    'DEV-код: ${challenge!['dev_code']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
              ],
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: privacy,
                onChanged: busy ? null : (v) => setState(() => privacy = v!),
                title: const Text(Ru.text169, style: TextStyle(fontSize: 13)),
                subtitle: TextButton(
                  onPressed: () => document('privacy'),
                  child: const Text(Ru.text168),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: terms,
                onChanged: busy ? null : (v) => setState(() => terms = v!),
                title: const Text(Ru.text167, style: TextStyle(fontSize: 13)),
                subtitle: TextButton(
                  onPressed: () => document('terms'),
                  child: const Text(Ru.text166),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton(
                onPressed: busy || !privacy || !terms
                    ? null
                    : challenge == null
                    ? request
                    : verify,
                child: Text(
                  busy
                      ? Ru.text82
                      : challenge == null
                      ? Ru.text81
                      : Ru.text165,
                ),
              ),
              if (challenge != null) ...[
                TextButton(
                  onPressed: busy || cooldown > 0 ? null : request,
                  child: Text(
                    cooldown > 0 ? 'Повторить через $cooldown с' : Ru.text164,
                  ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          challenge = null;
                          code.clear();
                          error = null;
                        }),
                  child: const Text(Ru.text163),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
