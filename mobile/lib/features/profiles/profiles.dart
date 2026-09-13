part of '../../main.dart';

class ProfileEditor extends StatefulWidget {
  final bool onboarding;
  const ProfileEditor({super.key, this.onboarding = false});
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final form = GlobalKey<FormState>();
  final controls = <String, TextEditingController>{};
  String status = Ru.text274, sex = Ru.text266;
  String? ownerPhoto, petPhoto, error;
  bool busy = false, approx = true;
  final ownerFields = const [
    FieldSpec('name', Ru.text50, required: true),
    FieldSpec('surname', Ru.text291),
    FieldSpec('handle', Ru.text290, required: true),
  ];
  final petFields = const [
    FieldSpec('pet_name', Ru.text289, required: true),
    FieldSpec('pet_handle', Ru.text288, required: true),
    FieldSpec('species', Ru.text287, required: true),
    FieldSpec('breed', Ru.text286),
    FieldSpec('city', Ru.text52, required: true),
    FieldSpec('description', Ru.text285, lines: 3),
    FieldSpec('height', Ru.text284, type: 'number'),
    FieldSpec('weight', Ru.text283, type: 'number'),
  ];
  @override
  void initState() {
    super.initState();
    final m = api.me!, o = m['owner'] as Map, p = m['pet'] as Map? ?? {};
    for (final f in [...ownerFields, ...petFields]) {
      final value = switch (f.key) {
        'handle' => m['handle'],
        'pet_name' => p['name'],
        'pet_handle' => p['handle'],
        'name' || 'surname' => o[f.key],
        _ => p[f.key],
      };
      controls[f.key] = TextEditingController(text: value?.toString() ?? '');
    }
    controls['age'] = TextEditingController(text: '${p['age_months'] ?? ''}');
    controls['birth_date'] = TextEditingController(
      text: '${p['birth_date'] ?? ''}',
    );
    status = o['status'] ?? status;
    sex = p['sex'] ?? sex;
    ownerPhoto = o['photo'];
    petPhoto = p['photo'];
    approx = p['birth_date'] == null;
  }

  @override
  void dispose() {
    for (final c in controls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> photo(bool pet) async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (file == null) return;
      setState(() => busy = true);
      final id = await api.upload(await file.readAsBytes(), 'public');
      if (mounted) {
        setState(() {
          if (pet) {
            petPhoto = id;
          } else {
            ownerPhoto = id;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is PlatformException ? Ru.text282 : '$e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final owner = {
        'name': controls['name']!.text.trim(),
        'surname': controls['surname']!.text.trim(),
        'handle': controls['handle']!.text.trim(),
        'status': status,
        if (ownerPhoto != null) 'photo': ownerPhoto,
      };
      final pet = <String, dynamic>{
        'name': controls['pet_name']!.text.trim(),
        'handle': controls['pet_handle']!.text.trim(),
        'sex': sex,
        if (petPhoto != null) 'photo': petPhoto,
      };
      for (final key in ['species', 'breed', 'city', 'description']) {
        pet[key] = controls[key]!.text.trim();
      }
      for (final key in ['height', 'weight']) {
        if (controls[key]!.text.isNotEmpty) {
          final v = double.tryParse(controls[key]!.text.replaceAll(',', '.'));
          if (v == null) throw ApiFailure(Ru.text281);
          pet[key] = v;
        }
      }
      if (approx && controls['age']!.text.isNotEmpty) {
        final age = int.tryParse(controls['age']!.text);
        if (age == null) throw ApiFailure(Ru.text280);
        pet['approx_months'] = age;
      }
      if (!approx && controls['birth_date']!.text.isNotEmpty) {
        pet['birth_date'] = controls['birth_date']!.text;
      }
      await api.call('PUT', '/me/profile', owner);
      await api.call(
        api.me!['pet'] == null ? 'POST' : 'PUT',
        api.me!['pet'] == null ? '/pets' : '/me/pet',
        pet,
      );
      await api.refreshMe();
      if (mounted && !widget.onboarding) Navigator.pop(context, true);
      if (pendingRoute != null) await routeTo(pendingRoute!);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget field(FieldSpec f) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controls[f.key],
      enabled: !busy,
      decoration: InputDecoration(labelText: f.label),
      minLines: f.lines,
      maxLines: f.lines,
      keyboardType: f.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      validator: (v) =>
          f.required && (v ?? '').trim().isEmpty ? Ru.text279 : null,
    ),
  );
  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.onboarding ? Ru.text278 : Ru.text252,
    child: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Text(
            Ru.text277,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Center(
            child: Column(
              children: [
                Avatar(ownerPhoto, size: 90),
                TextButton(
                  onPressed: busy ? null : () => photo(false),
                  child: const Text(Ru.text276),
                ),
              ],
            ),
          ),
          ...ownerFields.map(field),
          DropdownButtonFormField<String>(
            initialValue: status,
            isExpanded: true,
            decoration: const InputDecoration(labelText: Ru.text275),
            items: [
              Ru.text274,
              Ru.text273,
              Ru.text272,
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: busy ? null : (v) => setState(() => status = v!),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              Ru.text271,
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            Ru.text270,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          const Text(Ru.text269, style: TextStyle(color: muted)),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                Avatar(petPhoto, size: 105),
                TextButton(
                  onPressed: busy ? null : () => photo(true),
                  child: const Text(Ru.text268),
                ),
              ],
            ),
          ),
          ...petFields.map(field),
          DropdownButtonFormField<String>(
            initialValue: sex,
            decoration: const InputDecoration(labelText: Ru.text267),
            items: [
              Ru.text266,
              Ru.text265,
              Ru.text264,
            ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: busy ? null : (v) => setState(() => sex = v!),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(Ru.text263),
            value: approx,
            onChanged: busy ? null : (v) => setState(() => approx = v),
          ),
          if (approx)
            TextFormField(
              controller: controls['age'],
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: Ru.text262),
            )
          else
            TextFormField(
              controller: controls['birth_date'],
              readOnly: true,
              decoration: const InputDecoration(
                labelText: Ru.text261,
                suffixIcon: Icon(Icons.calendar_month),
              ),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(controls['birth_date']!.text) ??
                      DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (d != null) {
                  controls['birth_date']!.text = DateFormat(
                    'yyyy-MM-dd',
                  ).format(d);
                }
              },
            ),
          const SizedBox(height: 22),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(
              busy
                  ? Ru.text2
                  : widget.onboarding
                  ? Ru.text260
                  : Ru.text1,
            ),
          ),
        ],
      ),
    ),
  );
}

class ProfilePane extends StatefulWidget {
  final String account;
  const ProfilePane({super.key, required this.account});
  @override
  State<ProfilePane> createState() => _ProfilePaneState();
}

class _ProfilePaneState extends State<ProfilePane> {
  late Future<dynamic> future;
  final list = GlobalKey<PagedListState>();
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = api.call('GET', '/profiles/${widget.account}');
  }

  void refresh() {
    if (mounted) setState(load);
    list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (c, s) {
      if (s.hasError) return Failure(message: '${s.error}', retry: refresh);
      if (!s.hasData) return const Center(child: CircularProgressIndicator());
      final p = Map<String, dynamic>.from(s.data as Map),
          pet = Map<String, dynamic>.from(p['pet'] ?? {}),
          owner = Map<String, dynamic>.from(p['owner']);
      final own = p['id'] == api.me!['id'];
      return PagedList(
        key: list,
        path: '/items/posts?owner=${p['id']}',
        emptyTitle: Ru.text259,
        emptyText: own ? Ru.text258 : Ru.text257,
        tile: (i) => PostCard(item: i, changed: refresh),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: yellow,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Column(
                children: [
                  SizedBox(
                    width: 155,
                    height: 132,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4,
                          top: 0,
                          child: Avatar(pet['photo'], size: 124),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: yellow,
                              shape: BoxShape.circle,
                            ),
                            child: Avatar(owner['photo'], size: 52),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '${pet['name'] ?? owner['name'] ?? Ru.text256}',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '@${pet['handle'] ?? p['handle'] ?? ''}',
                    style: const TextStyle(color: muted),
                  ),
                  const SizedBox(height: 10),
                  Text('${pet['species'] ?? ''} · ${pet['city'] ?? ''}'),
                  if ((pet['description'] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        pet['description'],
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 20),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 24,
                    runSpacing: 14,
                    children: [
                      _stat('${p['friends']}', Ru.text255),
                      _stat('${p['followers']}', Ru.text254),
                      _stat('${p['achievements']}', Ru.text253),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(owner['photo']),
              title: Text('${owner['name'] ?? ''} ${owner['surname'] ?? ''}'),
              subtitle: Text('${owner['status'] ?? ''} · ${p['level']}'),
            ),
            if (own) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  await open(const ProfileEditor());
                  refresh();
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text(Ru.text252),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.folder_outlined, size: 18),
                    label: const Text(Ru.text136),
                    onPressed: () => open(const VetPage()),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.event_outlined, size: 18),
                    label: const Text(Ru.text135),
                    onPressed: () => open(const RemindersPage()),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.people_outline, size: 18),
                    label: const Text(Ru.text251),
                    onPressed: () => open(const RelationshipsPage()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await open(const ItemEditor(kind: 'posts'));
                  refresh();
                },
                icon: const Icon(Icons.add),
                label: const Text(Ru.text250),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    onPressed: () => guarded(() async {
                      await api.call(
                        'PUT',
                        '/relationships/${p['id']}/follow',
                        {'active': p['following'] != true},
                      );
                      refresh();
                    }),
                    child: Text(
                      p['following'] == true ? Ru.text249 : Ru.text248,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () => guarded(() async {
                      await api.call(
                        'PUT',
                        '/relationships/${p['id']}/friend',
                        {'operation': 'request'},
                      );
                      note(Ru.text247);
                    }),
                    child: const Text(Ru.text246),
                  ),
                  OutlinedButton(
                    onPressed: () => startChat(p['id']),
                    child: const Text(Ru.text245),
                  ),
                ],
              ),
              TextButton(
                onPressed: () => guarded(() async {
                  if (await confirm(Ru.text244, Ru.text243)) {
                    await api.call('PUT', '/relationships/${p['id']}/block', {
                      'active': true,
                    });
                    api.invalidateImages();
                    refresh();
                  }
                }),
                child: const Text(Ru.text242),
              ),
            ],
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: 'zuzu://profile/${pet['handle'] ?? p['id']}',
                  ),
                );
                note(Ru.text241);
              },
              icon: const Icon(Icons.link),
              label: const Text(Ru.text240),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 18, bottom: 10),
              child: Text(
                Ru.text239,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _stat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
      ),
      Text(label, style: const TextStyle(fontSize: 12, color: muted)),
    ],
  );
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final query = TextEditingController();
  Timer? timer;
  String q = '';
  @override
  void dispose() {
    timer?.cancel();
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text238,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(18),
          child: TextField(
            controller: query,
            decoration: InputDecoration(
              hintText: Ru.text237,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                tooltip: Ru.text236,
                icon: const Icon(Icons.close),
                onPressed: () {
                  query.clear();
                  setState(() => q = '');
                },
              ),
            ),
            onChanged: (v) {
              timer?.cancel();
              timer = Timer(
                const Duration(milliseconds: 350),
                () => setState(() => q = v),
              );
            },
          ),
        ),
        Expanded(
          child: PagedList(
            path: '/profiles?q=${Uri.encodeComponent(q)}',
            emptyTitle: Ru.text235,
            emptyText: Ru.text234,
            tile: (p) => Card(
              child: ListTile(
                leading: Avatar(p['pet']?['photo']),
                title: Text(p['pet']?['name'] ?? ''),
                subtitle: Text(
                  '@${p['pet']?['handle'] ?? ''} · ${p['pet']?['city'] ?? ''}',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => open(
                  PageFrame(
                    title: Ru.text228,
                    child: ProfilePane(account: p['id']),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
