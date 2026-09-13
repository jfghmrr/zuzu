part of '../../main.dart';

String relativeDay(DateTime due, DateTime now) {
  final a = DateTime.utc(due.year, due.month, due.day),
      b = DateTime.utc(now.year, now.month, now.day);
  final n = a.difference(b).inDays;
  if (n == 0) return Ru.text331;
  if (n == 1) return Ru.text330;
  if (n < 0) return Ru.text329;
  return 'Через $n дн.';
}

class RemindersPage extends StatefulWidget {
  const RemindersPage({super.key});
  @override
  State<RemindersPage> createState() => _RemindersPageState();
}

class _RemindersPageState extends State<RemindersPage> {
  DateTime selected = DateTime.now(),
      month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Map<String, dynamic>> rows = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final all = <Map<String, dynamic>>[];
      Map? cursor;
      do {
        var path = '/items/reminders?limit=50';
        if (cursor != null) {
          path +=
              '&before=${cursor['before']}&cursor_id=${cursor['cursor_id']}';
        }
        final r = await api.call('GET', path);
        all.addAll(
          (r['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        cursor = r['next'];
      } while (cursor != null);
      all.sort((a, b) => a['data']['due_at'].compareTo(b['data']['due_at']));
      if (mounted) {
        setState(() {
          rows = all;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> add() async {
    await open(
      ItemEditor(
        kind: 'reminders',
        defaults: {
          'due_at': DateTime(
            selected.year,
            selected.month,
            selected.day,
            10,
          ).toUtc().toIso8601String(),
        },
      ),
    );
    load();
  }

  Widget tile(Map<String, dynamic> i) {
    final d = i['data'], due = DateTime.parse(d['due_at']).toLocal();
    return Card(
      child: ListTile(
        leading: Checkbox(
          value: d['done'] == true,
          onChanged: (v) => guarded(() async {
            await api.call('PUT', '/item/${i['id']}', {
              'data': {...d, 'done': v},
            });
            await load();
            try {
              await platform.syncReminders(api);
            } catch (_) {
              note(Ru.text328);
            }
          }),
        ),
        title: Text(
          d['title'],
          style: TextStyle(
            decoration: d['done'] == true ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${DateFormat('d MMM, HH:mm', 'ru').format(due)} · ${relativeDay(due, DateTime.now())}',
        ),
        onTap: () async {
          await open(ItemPage(item: i));
          load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = DateUtils.getDaysInMonth(month.year, month.month),
        offset = (month.weekday - 1);
    final todayRows = rows
        .where(
          (i) => DateUtils.isSameDay(
            DateTime.parse(i['data']['due_at']).toLocal(),
            selected,
          ),
        )
        .toList();
    return PageFrame(
      title: Ru.text135,
      actions: [
        IconButton(
          tooltip: Ru.text208,
          onPressed: add,
          icon: const Icon(Icons.add),
        ),
      ],
      child: RefreshIndicator(
        onRefresh: load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              Ru.text327,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 28,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 18),
            if (kIsWeb || platform.permitted == false)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kIsWeb ? Ru.text326 : Ru.text325),
                      if (!kIsWeb)
                        TextButton(
                          onPressed: () => Geolocator.openAppSettings(),
                          child: const Text(Ru.text324),
                        ),
                    ],
                  ),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: Ru.text323,
                          onPressed: () => setState(
                            () => month = DateTime(month.year, month.month - 1),
                          ),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            DateFormat('LLLL yyyy', 'ru').format(month),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: Ru.text322,
                          onPressed: () => setState(
                            () => month = DateTime(month.year, month.month + 1),
                          ),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        for (final d in [
                          Ru.text321,
                          Ru.text320,
                          Ru.text319,
                          Ru.text318,
                          Ru.text317,
                          Ru.text316,
                          Ru.text315,
                        ])
                          Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: TextStyle(color: muted, fontSize: 12),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: days + offset,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            mainAxisExtent: 48,
                          ),
                      itemBuilder: (c, index) {
                        if (index < offset) return const SizedBox.shrink();
                        final date = DateTime(
                              month.year,
                              month.month,
                              index - offset + 1,
                            ),
                            active = DateUtils.isSameDay(date, selected),
                            marked = rows.any(
                              (i) => DateUtils.isSameDay(
                                DateTime.parse(i['data']['due_at']).toLocal(),
                                date,
                              ),
                            );
                        return Semantics(
                          label: DateFormat('d MMMM yyyy', 'ru').format(date),
                          selected: active,
                          button: true,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => setState(() => selected = date),
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: active ? orange : null,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '${date.day}',
                                    style: TextStyle(
                                      color: active ? Colors.white : brown,
                                    ),
                                  ),
                                  if (marked)
                                    Container(
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: active ? Colors.white : orange,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              DateFormat('d MMMM', 'ru').format(selected),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            if (loading)
              const Center(child: CircularProgressIndicator())
            else if (error != null)
              Failure(message: error!, retry: load)
            else if (todayRows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(Ru.text314, style: TextStyle(color: muted)),
              )
            else
              ...todayRows.map(tile),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text(Ru.text313),
            ),
            const SizedBox(height: 26),
            const Text(
              Ru.text312,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            ...rows.where((i) => i['data']['done'] != true).take(20).map(tile),
          ],
        ),
      ),
    );
  }
}
