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
  int onboardingStep = 0;
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
    if (widget.onboarding) {
      if (controls['handle']!.text.isEmpty) {
        controls['handle']!.text =
            'u_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      }
      if (controls['pet_handle']!.text.isEmpty) {
        controls['pet_handle']!.text =
            'p_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';
      }
    }
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
  Widget onboardingField(String key, String hint, {bool required = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controls[key],
          enabled: !busy,
          style: const TextStyle(fontSize: 16, height: 22 / 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontSize: 16,
              color: Color(0xff8e9baa),
              height: 22 / 16,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 15,
              vertical: 15,
            ),
          ),
          validator: (v) =>
              required && (v ?? '').trim().isEmpty ? Ru.text279 : null,
        ),
      );
  Widget onboarding(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        onboardingStep == 0 ? 'Ваш профиль' : 'Профиль питомца',
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      ),
      leading: onboardingStep == 1
          ? BackButton(onPressed: () => setState(() => onboardingStep = 0))
          : null,
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: divider),
                ),
                padding: const EdgeInsets.fromLTRB(14, 26, 14, 20),
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: InkWell(
                          onTap: busy ? null : () => photo(onboardingStep == 1),
                          child: Semantics(
                            button: true,
                            label: onboardingStep == 0
                                ? 'Добавить своё фото'
                                : 'Добавить фото питомца',
                            child: Avatar(
                              onboardingStep == 0 ? ownerPhoto : petPhoto,
                              size: 116,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (onboardingStep == 0) ...[
                        onboardingField('name', 'Имя', required: true),
                        onboardingField('surname', 'Фамилия'),
                        const Text(
                          'Статус',
                          style: TextStyle(color: muted, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final value in [
                              Ru.text273,
                              Ru.text272,
                              Ru.text274,
                            ])
                              Semantics(
                                selected: status == value,
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(0, 32),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    backgroundColor: status == value
                                        ? const Color(0xfffff8ed)
                                        : paper,
                                    foregroundColor: status == value
                                        ? const Color(0xfff5a623)
                                        : ink,
                                    shape: const StadiumBorder(),
                                  ),
                                  onPressed: busy
                                      ? null
                                      : () => setState(() => status = value),
                                  child: Text(
                                    value,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      height: 20 / 14,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ] else ...[
                        onboardingField('pet_name', 'Кличка', required: true),
                        onboardingField(
                          'species',
                          'Вид питомца',
                          required: true,
                        ),
                        onboardingField('breed', 'Порода'),
                        onboardingField(
                          'description',
                          'Статус (немного о питомце)',
                        ),
                        onboardingField('city', 'Город', required: true),
                      ],
                      if (error != null)
                        Text(error!, style: const TextStyle(color: Colors.red)),
                      const Spacer(),
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xfff5a623),
                          minimumSize: const Size(48, 54),
                        ),
                        onPressed: busy
                            ? null
                            : () {
                                if (!form.currentState!.validate()) return;
                                if (onboardingStep == 0) {
                                  setState(() {
                                    onboardingStep = 1;
                                    error = null;
                                  });
                                } else {
                                  save();
                                }
                              },
                        child: Text(
                          busy
                              ? Ru.text2
                              : onboardingStep == 0
                              ? 'Далее'
                              : 'Готово',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => widget.onboarding
      ? onboarding(context)
      : PageFrame(
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
                  items: [Ru.text274, Ru.text273, Ru.text272]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
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
                  items: [Ru.text266, Ru.text265, Ru.text264]
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
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

  Future<void> menu(String action, Map p) => guarded(() async {
    switch (action) {
      case 'edit':
        await open(const ProfileEditor());
        refresh();
      case 'copy':
        await Clipboard.setData(
          ClipboardData(
            text: 'zuzu://profile/${p['pet']?['handle'] ?? p['id']}',
          ),
        );
        note(Ru.text241);
      case 'blocked':
        await open(const RelationshipsPage(blocked: true));
      case 'friend':
        await api.call('PUT', '/relationships/${p['id']}/friend', {
          'operation': 'request',
        });
        note(Ru.text247);
      case 'block':
        if (await confirm(Ru.text244, Ru.text243)) {
          await api.call('PUT', '/relationships/${p['id']}/block', {
            'active': true,
          });
          api.invalidateImages();
          refresh();
        }
    }
  });
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
        padding: EdgeInsets.zero,
        emptyTitle: Ru.text259,
        emptyText: own ? Ru.text258 : Ru.text257,
        tile: (i) => PostCard(item: i, changed: refresh),
        contentBuilder: (items) => Wrap(
          children: [
            for (final item in items)
              SizedBox(
                width: MediaQuery.sizeOf(context).width / 2,
                height: MediaQuery.sizeOf(context).width / 2,
                child: InkWell(
                  onTap: () => open(
                    PageFrame(
                      title: 'Публикация',
                      child: SingleChildScrollView(
                        child: PostCard(item: item, changed: refresh),
                      ),
                    ),
                  ),
                  child: (item['data']['media'] as List? ?? []).isNotEmpty
                      ? Photo(item['data']['media'][0])
                      : Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(15),
                          child: Center(
                            child: Text(
                              '${item['data']['text'] ?? ''}',
                              maxLines: 6,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                ),
              ),
          ],
        ),
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 75),
                  padding: const EdgeInsets.fromLTRB(15, 64, 15, 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${pet['name'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 24 / 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${pet['handle'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 16 / 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '${pet['breed']?.isNotEmpty == true ? pet['breed'] : pet['species'] ?? ''}',
                        style: const TextStyle(fontSize: 14, height: 20 / 14),
                      ),
                      if ((pet['description'] ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            pet['description'],
                            style: const TextStyle(
                              fontSize: 14,
                              height: 20 / 14,
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '${pet['city'] ?? ''}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: muted,
                          height: 16 / 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 18,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: PairedAvatar(
                      pet: pet['photo'],
                      owner: owner['photo'],
                      size: 112,
                      ownerSize: 40,
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 5,
                  child: PopupMenuButton<String>(
                    tooltip: 'Действия с профилем',
                    onSelected: (v) => menu(v, p),
                    icon: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                      child: const Icon(
                        Icons.more_vert,
                        size: 20,
                        color: muted,
                      ),
                    ),
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: own ? 'edit' : 'friend',
                        child: Text(
                          own ? 'Редактировать' : 'Добавить в друзья',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'copy',
                        child: Text('Скопировать ссылку'),
                      ),
                      PopupMenuItem(
                        value: own ? 'blocked' : 'block',
                        child: Text(own ? 'Чёрный список' : 'Заблокировать'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _panel(
              Row(
                children: [
                  Expanded(
                    child: _pill(
                      own
                          ? 'Вет паспорт'
                          : p['following'] == true
                          ? '✓ Вы подписаны'
                          : 'Подписаться',
                      () => own
                          ? open(const VetPage())
                          : guarded(() async {
                              await api.call(
                                'PUT',
                                '/relationships/${p['id']}/follow',
                                {'active': p['following'] != true},
                              );
                              refresh();
                            }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _pill(
                      own ? 'Напоминания' : 'Написать',
                      () => own
                          ? open(const RemindersPage())
                          : startChat(p['id']),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _panel(
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      '${p['friends']}',
                      'Друзья',
                      own ? () => open(const RelationshipsPage()) : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _stat(
                      '${p['followers']}',
                      'Подписчики',
                      own ? () => open(const RelationshipsPage()) : null,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: child,
  );
  Widget _pill(String title, VoidCallback onTap) => TextButton(
    style: TextButton.styleFrom(
      backgroundColor: paper,
      foregroundColor: ink,
      minimumSize: const Size(48, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      shape: const StadiumBorder(),
    ),
    onPressed: onTap,
    child: Text(
      title,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14),
    ),
  );
  Widget _stat(String value, String label, VoidCallback? onTap) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          Text(label, style: const TextStyle(fontSize: 14, color: muted)),
        ],
      ),
    ),
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
