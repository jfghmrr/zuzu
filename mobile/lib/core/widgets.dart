part of '../main.dart';

class PageFrame extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(child: child),
  );
}

class Failure extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const Failure({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36, color: muted),
        const SizedBox(height: 16),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: retry,
          icon: const Icon(Icons.refresh),
          label: const Text(Ru.text71),
        ),
      ],
    ),
  );
}

class Empty extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  const Empty(
    this.title,
    this.subtitle, {
    super.key,
    this.icon = Icons.pets_outlined,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 24),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(25),
          decoration: const BoxDecoration(
            color: yellow,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 38, color: brown),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, height: 1.5),
        ),
      ],
    ),
  );
}

class Photo extends StatelessWidget {
  final String? id;
  final double? width, height;
  final BoxFit fit;
  const Photo(
    this.id, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });
  @override
  Widget build(BuildContext context) {
    if (id == null || id!.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: yellow,
        child: const Icon(Icons.pets, color: brown, size: 36),
      );
    }
    return FutureBuilder<Uint8List>(
      future: api.photo(id!),
      builder: (context, s) {
        if (s.hasData) {
          return Image.memory(
            s.data!,
            width: width,
            height: height,
            fit: fit,
            gaplessPlayback: false,
          );
        }
        return Container(
          width: width,
          height: height,
          color: yellow.withValues(alpha: .5),
          child: Center(
            child: s.hasError
                ? const Icon(Icons.broken_image_outlined)
                : const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
          ),
        );
      },
    );
  }
}

class Avatar extends StatelessWidget {
  final String? id;
  final double size;
  const Avatar(this.id, {super.key, this.size = 52});
  @override
  Widget build(BuildContext context) => ClipOval(
    child: Photo(id, width: size, height: size),
  );
}

Future<bool> confirm(
  String title,
  String body, {
  String yes = Ru.text70,
}) async =>
    await showDialog<bool>(
      context: nav.currentContext!,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text(Ru.text12),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(yes),
          ),
        ],
      ),
    ) ??
    false;
String stamp(num value) => DateFormat(
  'd MMM, HH:mm',
  'ru',
).format(DateTime.fromMillisecondsSinceEpoch((value * 1000).toInt()));
Future<void> guarded(Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    note(e);
  }
}

class PagedList extends StatefulWidget {
  final String path, emptyTitle, emptyText;
  final Widget Function(Map<String, dynamic>) tile;
  final Widget? header;
  final int? pollSeconds;
  const PagedList({
    super.key,
    required this.path,
    required this.tile,
    this.emptyTitle = Ru.text69,
    this.emptyText = Ru.text68,
    this.header,
    this.pollSeconds,
  });
  @override
  State<PagedList> createState() => PagedListState();
}

class PagedListState extends State<PagedList> {
  List<Map<String, dynamic>> rows = [];
  dynamic next;
  bool loading = true, busy = false;
  String? error;
  Timer? timer;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    reload();
    if (widget.pollSeconds != null) {
      timer = Timer.periodic(Duration(seconds: widget.pollSeconds!), (_) {
        if (!busy) reload(silent: true);
      });
    }
  }

  @override
  void didUpdateWidget(covariant PagedList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) reload();
  }

  @override
  void dispose() {
    timer?.cancel();
    generation++;
    super.dispose();
  }

  Future<void> reload({bool more = false, bool silent = false}) async {
    if (more && busy) return;
    final gen = ++generation;
    busy = true;
    if (!silent && mounted) {
      setState(() {
        if (!more) loading = true;
        error = null;
      });
    }
    try {
      var path = widget.path;
      if (more && next != null) {
        final q = next is Map
            ? Uri(
                queryParameters: (next as Map).map(
                  (k, v) => MapEntry('$k', '$v'),
                ),
              ).query
            : 'offset=$next';
        path += '${path.contains('?') ? '&' : '?'}$q';
      }
      final data = await api.call('GET', path);
      if (!mounted || gen != generation) return;
      final fetched = (data['items'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        rows = more ? [...rows, ...fetched] : fetched;
        next = data['next'];
        loading = false;
        error = null;
      });
    } catch (e) {
      if (mounted && gen == generation) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    } finally {
      if (gen == generation) {
        busy = false;
        if (mounted) setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: reload,
    child: ListView(
      padding: const EdgeInsets.all(18),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (widget.header != null) widget.header!,
        if (loading)
          const Padding(
            padding: EdgeInsets.all(50),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          if (error != null) Failure(message: error!, retry: reload),
          if (rows.isEmpty && error == null)
            Empty(widget.emptyTitle, widget.emptyText),
          ...rows.map(widget.tile),
          if (next != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: OutlinedButton(
                onPressed: busy ? null : () => reload(more: true),
                child: Text(busy ? Ru.text67 : Ru.text66),
              ),
            ),
        ],
      ],
    ),
  );
}

class Gallery extends StatefulWidget {
  final List<dynamic> ids;
  const Gallery(this.ids, {super.key});
  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  int current = 0;
  @override
  Widget build(BuildContext context) {
    if (widget.ids.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 1.14,
            child: PageView(
              onPageChanged: (v) => setState(() => current = v),
              children: widget.ids
                  .map(
                    (id) => GestureDetector(
                      onTap: () => open(
                        PageFrame(
                          title: Ru.text65,
                          child: Center(
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: Photo('$id', fit: BoxFit.contain),
                            ),
                          ),
                        ),
                      ),
                      child: Photo('$id'),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        if (widget.ids.length > 1)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              '${current + 1} / ${widget.ids.length}',
              style: const TextStyle(color: muted),
            ),
          ),
      ],
    );
  }
}

class FieldSpec {
  final String key, label;
  final bool required;
  final int lines;
  final List<String>? choices;
  final String type;
  const FieldSpec(
    this.key,
    this.label, {
    this.required = false,
    this.lines = 1,
    this.choices,
    this.type = 'text',
  });
}

List<FieldSpec> fieldsFor(String kind) => switch (kind) {
  'posts' ||
  'stories' ||
  'messages' => [const FieldSpec('text', Ru.text64, lines: 4)],
  'comments' || 'map_messages' => [
    const FieldSpec('text', Ru.text28, required: true, lines: 4),
  ],
  'vet' => [
    const FieldSpec('title', Ru.text63, required: true),
    const FieldSpec('visit_date', Ru.text62, required: true, type: 'date'),
    const FieldSpec('diagnosis', Ru.text61, lines: 3),
    const FieldSpec('recommendations', Ru.text60, lines: 3),
  ],
  'reminders' => [
    const FieldSpec('title', Ru.text59, required: true),
    const FieldSpec('due_at', Ru.text58, required: true, type: 'datetime'),
    const FieldSpec('note', Ru.text57, lines: 3),
  ],
  'markers' => [
    const FieldSpec('title', Ru.text56, required: true),
    const FieldSpec(
      'category',
      Ru.text55,
      choices: ['danger', 'lost', 'found', 'other'],
    ),
    const FieldSpec('city', Ru.text52, required: true),
    const FieldSpec('text', Ru.text54, lines: 4),
  ],
  'news' => [
    const FieldSpec('title', Ru.text53, required: true),
    const FieldSpec('city', Ru.text52, required: true),
    const FieldSpec('text', Ru.text51, required: true, lines: 5),
  ],
  'feedback' => [
    const FieldSpec('name', Ru.text50, required: true),
    const FieldSpec('email', Ru.text49, required: true),
    const FieldSpec('text', Ru.text48, required: true, lines: 5),
  ],
  'reports' => [
    const FieldSpec(
      'reason',
      Ru.text47,
      choices: [Ru.text46, Ru.text45, Ru.text44],
    ),
    const FieldSpec('text', Ru.text43, lines: 4),
  ],
  _ => [],
};
const categoryNames = {
  'danger': Ru.text42,
  'lost': Ru.text41,
  'found': Ru.text40,
  'other': Ru.text39,
};
String kindTitle(String k) =>
    const {
      'posts': Ru.text38,
      'stories': Ru.text37,
      'vet': Ru.text36,
      'reminders': Ru.text35,
      'markers': Ru.text34,
      'news': Ru.text33,
      'feedback': Ru.text32,
      'reports': Ru.text31,
      'comments': Ru.text30,
      'map_messages': Ru.text29,
    }[k] ??
    Ru.text28;

String displayDate(String value, String type) {
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return DateFormat(
    type == 'datetime' ? 'd MMM yyyy, HH:mm' : 'd MMMM yyyy',
    'ru',
  ).format(type == 'datetime' ? date.toLocal() : date);
}

class ItemEditor extends StatefulWidget {
  final String kind;
  final String? target;
  final Map<String, dynamic>? item;
  final Map<String, dynamic> defaults;
  const ItemEditor({
    super.key,
    required this.kind,
    this.target,
    this.item,
    this.defaults = const {},
  });
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final form = GlobalKey<FormState>();
  final id = const Uuid().v4();
  late Map<String, dynamic> data;
  final controls = <String, TextEditingController>{};
  final dateDisplays = <String, TextEditingController>{};
  final media = <String>[];
  bool busy = false, dirty = false;
  String? error;
  @override
  void initState() {
    super.initState();
    data = {...widget.defaults, ...?widget.item?['data']};
    media.addAll(List<String>.from(data['media'] ?? []));
    for (final f in fieldsFor(widget.kind)) {
      controls[f.key] = TextEditingController(text: '${data[f.key] ?? ''}');
      if (f.type != 'text') {
        dateDisplays[f.key] = TextEditingController(
          text: displayDate(controls[f.key]!.text, f.type),
        );
      }
      if (f.choices != null) data[f.key] ??= f.choices!.first;
    }
  }

  @override
  void dispose() {
    for (final c in [...controls.values, ...dateDisplays.values]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get canMedia =>
      ['posts', 'stories', 'vet', 'messages'].contains(widget.kind);
  Future<void> choose(bool camera) async {
    try {
      final picker = ImagePicker();
      final files = camera
          ? [
              await picker.pickImage(
                source: ImageSource.camera,
                imageQuality: 90,
              ),
            ]
          : widget.kind == 'stories'
          ? [
              await picker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
              ),
            ]
          : await picker.pickMultiImage(imageQuality: 90);
      final selected = files.whereType<XFile>().toList();
      if (selected.isEmpty) return;
      if (media.length + selected.length > (widget.kind == 'stories' ? 1 : 8)) {
        throw ApiFailure(Ru.text27);
      }
      setState(() => busy = true);
      for (final f in selected) {
        final mid = await api.upload(
          await f.readAsBytes(),
          widget.kind == 'vet'
              ? 'vet'
              : widget.kind == 'messages'
              ? 'chat'
              : 'public',
        );
        media.add(mid);
      }
      if (mounted) setState(() => dirty = true);
    } catch (e) {
      if (mounted) {
        setState(() => error = e is PlatformException ? Ru.text26 : '$e');
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
      for (final f in fieldsFor(widget.kind)) {
        if (f.choices == null) data[f.key] = controls[f.key]!.text.trim();
      }
      if (canMedia) data['media'] = media;
      if (widget.kind == 'reminders') {
        data['timezone'] ??= platform.zone;
        data['done'] ??= false;
        data['tasks'] ??= [];
      }
      final result = widget.item == null
          ? await api.call('POST', '/items/${widget.kind}', {
              'id': id,
              'data': data,
              'target': widget.target,
            })
          : await api.call('PUT', '/item/${widget.item!['id']}', {
              'data': data,
            });
      if (widget.kind == 'reminders') {
        try {
          await platform.syncReminders(api);
        } catch (_) {
          note(Ru.text25);
        }
      }
      if (mounted) {
        setState(() {
          dirty = false;
          busy = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, result);
        });
        note(
          widget.kind == 'reports'
              ? Ru.text24
              : widget.kind == 'feedback'
              ? Ru.text23
              : Ru.text22,
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> chooseDate(FieldSpec f) async {
    final initial =
        DateTime.tryParse(controls[f.key]!.text)?.toLocal() ?? DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2120),
    );
    if (day == null || !mounted) return;
    var dt = day;
    if (f.type == 'datetime') {
      final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(initial),
      );
      if (t == null) return;
      dt = DateTime(day.year, day.month, day.day, t.hour, t.minute);
    }
    controls[f.key]!.text = f.type == 'datetime'
        ? dt.toUtc().toIso8601String()
        : DateFormat('yyyy-MM-dd').format(dt);
    dateDisplays[f.key]?.text = displayDate(controls[f.key]!.text, f.type);
    setState(() => dirty = true);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy && !dirty,
    onPopInvokedWithResult: (did, result) async {
      if (did || busy) return;
      if (await confirm(Ru.text21, Ru.text20, yes: Ru.text19)) {
        if (!mounted) return;
        setState(() => dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: PageFrame(
      title: kindTitle(widget.kind),
      child: Form(
        key: form,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            22,
            20,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            if (widget.kind == 'vet')
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(Ru.text18, style: TextStyle(color: muted)),
              ),
            if (widget.kind == 'stories')
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(Ru.text17),
              ),
            for (final f in fieldsFor(widget.kind))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: f.choices != null
                    ? DropdownButtonFormField<String>(
                        initialValue: data[f.key],
                        decoration: InputDecoration(labelText: f.label),
                        isExpanded: true,
                        items: f.choices!
                            .map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child: Text(categoryNames[v] ?? v),
                              ),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) => setState(() {
                                data[f.key] = v;
                                dirty = true;
                              }),
                      )
                    : TextFormField(
                        controller: dateDisplays[f.key] ?? controls[f.key],
                        enabled: !busy,
                        minLines: f.lines,
                        maxLines: f.lines,
                        readOnly: f.type != 'text',
                        onTap: f.type != 'text' ? () => chooseDate(f) : null,
                        onChanged: (_) => setState(() => dirty = true),
                        decoration: InputDecoration(
                          labelText: f.label,
                          suffixIcon: f.type != 'text'
                              ? const Icon(Icons.calendar_today_outlined)
                              : null,
                        ),
                        validator: (v) => f.required && (v ?? '').trim().isEmpty
                            ? Ru.text16
                            : (v ?? '').length > 5000
                            ? Ru.text15
                            : null,
                      ),
              ),
            if (widget.kind == 'reminders') ...[
              Text(
                'Часовой пояс: ${data['timezone'] ?? platform.zone}',
                style: const TextStyle(color: muted),
              ),
              ...List<Map<String, dynamic>>.from(
                (data['tasks'] ?? []).map((e) => Map<String, dynamic>.from(e)),
              ).asMap().entries.map(
                (e) => CheckboxListTile(
                  value: e.value['done'] == true,
                  title: Text(e.value['title']),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                          data['tasks'][e.key]['done'] = v;
                          dirty = true;
                        }),
                  secondary: IconButton(
                    tooltip: Ru.text14,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      data['tasks'].removeAt(e.key);
                      dirty = true;
                    }),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        final c = TextEditingController();
                        final value = await showDialog<String>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text(Ru.text13),
                            content: TextField(controller: c, maxLength: 120),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text(Ru.text12),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, c.text.trim()),
                                child: const Text(Ru.text11),
                              ),
                            ],
                          ),
                        );
                        if (value != null && value.isNotEmpty) {
                          setState(() {
                            data['tasks'] = [
                              ...data['tasks'] ?? [],
                              {'title': value, 'done': false},
                            ];
                            dirty = true;
                          });
                        }
                      },
                icon: const Icon(Icons.add),
                label: const Text(Ru.text10),
              ),
              TextButton.icon(
                onPressed: () => guarded(() async {
                  final granted = await platform.requestPermission();
                  note(granted ? Ru.text9 : Ru.text8);
                }),
                icon: const Icon(Icons.notifications_outlined),
                label: const Text(Ru.text7),
              ),
            ],
            if (canMedia) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: media
                    .map(
                      (mid) => Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Photo(mid, width: 95, height: 95),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton.filled(
                              tooltip: Ru.text6,
                              onPressed: busy
                                  ? null
                                  : () => setState(() {
                                      media.remove(mid);
                                      dirty = true;
                                    }),
                              icon: const Icon(Icons.close, size: 18),
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => choose(false),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text(Ru.text5),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => choose(true),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text(Ru.text4),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (dirty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  Ru.text3,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? Ru.text2 : Ru.text1),
            ),
          ],
        ),
      ),
    ),
  );
}
