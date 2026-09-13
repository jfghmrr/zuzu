part of '../../main.dart';

class FeedPane extends StatefulWidget {
  const FeedPane({super.key});
  @override
  State<FeedPane> createState() => _FeedPaneState();
}

class _FeedPaneState extends State<FeedPane> {
  final key = GlobalKey<PagedListState>();
  @override
  Widget build(BuildContext context) => PagedList(
    key: key,
    path: '/items/posts',
    emptyTitle: Ru.text233,
    emptyText: Ru.text232,
    tile: (i) => PostCard(item: i, changed: () => key.currentState?.reload()),
    header: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          Ru.text231,
          style: TextStyle(
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 18),
        const StoryStrip(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () async {
                  await open(const ItemEditor(kind: 'posts'));
                  key.currentState?.reload();
                },
                icon: const Icon(Icons.add),
                label: const Text(Ru.text230),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.outlined(
              tooltip: Ru.text229,
              onPressed: () => open(const SearchPage()),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    ),
  );
}

class PostCard extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback changed;
  const PostCard({super.key, required this.item, required this.changed});
  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool expanded = false, busy = false;
  late Map<String, dynamic> item;
  @override
  void initState() {
    super.initState();
    item = widget.item;
  }

  @override
  void didUpdateWidget(covariant PostCard old) {
    super.didUpdateWidget(old);
    item = widget.item;
  }

  Future<void> like() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final r = await api.call('PUT', '/item/${item['id']}/like', {
        'active': item['liked'] != true,
      });
      if (mounted) setState(() => item = Map<String, dynamic>.from(r));
    } catch (e) {
      note(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = item['data'] as Map, text = '${d['text'] ?? ''}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Avatar(item['avatar'], size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => open(
                      PageFrame(
                        title: Ru.text228,
                        child: ProfilePane(account: item['owner_id']),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['author'],
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          stamp(item['created']),
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: Ru.text227,
                  onSelected: (v) => guarded(() async {
                    if (v == 'delete') {
                      if (await confirm(
                        Ru.text226,
                        Ru.text225,
                        yes: Ru.text106,
                      )) {
                        await api.call('DELETE', '/item/${item['id']}');
                        api.invalidateImages();
                        widget.changed();
                      }
                    } else {
                      await open(
                        ItemEditor(kind: 'reports', target: item['id']),
                      );
                    }
                  }),
                  itemBuilder: (_) => [
                    if (item['owner_id'] == api.me!['id'])
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text(Ru.text106),
                      ),
                    const PopupMenuItem(
                      value: 'report',
                      child: Text(Ru.text146),
                    ),
                  ],
                ),
              ],
            ),
            if ((d['media'] as List? ?? []).isNotEmpty) ...[
              const SizedBox(height: 14),
              Gallery(List<dynamic>.from(d['media'])),
            ],
            if (text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                text,
                maxLines: expanded ? null : 4,
                overflow: expanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: const TextStyle(height: 1.45),
              ),
              if (text.length > 160)
                TextButton(
                  onPressed: () => setState(() => expanded = !expanded),
                  child: Text(expanded ? Ru.text224 : Ru.text223),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                IconButton(
                  tooltip: item['liked'] == true ? Ru.text222 : Ru.text221,
                  onPressed: busy ? null : like,
                  icon: Icon(
                    item['liked'] == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: item['liked'] == true ? orange : brown,
                  ),
                ),
                TextButton(
                  onPressed: () => open(
                    PeoplePage(
                      title: Ru.text220,
                      path: '/item/${item['id']}/likes',
                    ),
                  ),
                  child: Text('${item['likes']}'),
                ),
                TextButton.icon(
                  onPressed: () => open(CommentsPage(post: item['id'])),
                  icon: const Icon(Icons.mode_comment_outlined),
                  label: const Text(Ru.text219),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class CommentsPage extends StatefulWidget {
  final String post;
  const CommentsPage({super.key, required this.post});
  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  final key = GlobalKey<PagedListState>();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text219,
    actions: [
      IconButton(
        tooltip: Ru.text218,
        onPressed: () async {
          await open(ItemEditor(kind: 'comments', target: widget.post));
          key.currentState?.reload();
        },
        icon: const Icon(Icons.add),
      ),
    ],
    child: PagedList(
      key: key,
      path: '/items/comments?target=${widget.post}&parent=root',
      emptyTitle: Ru.text217,
      emptyText: Ru.text216,
      tile: (i) =>
          CommentTile(item: i, refresh: () => key.currentState?.reload()),
    ),
  );
}

class CommentTile extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback refresh;
  const CommentTile({super.key, required this.item, required this.refresh});
  @override
  State<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<CommentTile> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final i = widget.item, d = i['data'];
    return Padding(
      padding: EdgeInsets.only(left: d['parent_id'] == null ? 0 : 24),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${i['author']} · ${stamp(i['created'])}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (d['parent_id'] != null)
                const Text(
                  Ru.text215,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              const SizedBox(height: 8),
              Text(d['text']),
              Wrap(
                spacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: Ru.text214,
                    onPressed: busy
                        ? null
                        : () => guarded(() async {
                            setState(() => busy = true);
                            try {
                              await api.call('PUT', '/item/${i['id']}/like', {
                                'active': i['liked'] != true,
                              });
                              widget.refresh();
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          }),
                    icon: Icon(
                      i['liked'] == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: orange,
                    ),
                  ),
                  Text('${i['likes']}'),
                  TextButton(
                    onPressed: () async {
                      await open(
                        ItemEditor(
                          kind: 'comments',
                          target: i['target'],
                          defaults: {'parent_id': d['parent_id'] ?? i['id']},
                        ),
                      );
                      widget.refresh();
                    },
                    child: const Text(Ru.text213),
                  ),
                  PopupMenuButton<String>(
                    tooltip: Ru.text212,
                    onSelected: (v) => guarded(() async {
                      if (v == 'delete') {
                        if (await confirm(Ru.text211, Ru.text210)) {
                          await api.call('DELETE', '/item/${i['id']}');
                          widget.refresh();
                        }
                      } else {
                        await open(
                          ItemEditor(kind: 'reports', target: i['id']),
                        );
                      }
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Text(Ru.text146),
                      ),
                      if (i['owner_id'] == api.me!['id'])
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(Ru.text106),
                        ),
                    ],
                  ),
                ],
              ),
              if (d['parent_id'] == null)
                ExpansionTile(
                  title: const Text(Ru.replies),
                  children: [
                    SizedBox(
                      height: 300,
                      child: PagedList(
                        key: ValueKey('replies-${i['id']}-${i['updated']}'),
                        path:
                            '/items/comments?target=${i['target']}&parent=${i['id']}',
                        emptyTitle: Ru.noReplies,
                        emptyText: Ru.replyHint,
                        tile: (reply) =>
                            CommentTile(item: reply, refresh: widget.refresh),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ItemPage extends StatefulWidget {
  final Map<String, dynamic> item;
  const ItemPage({super.key, required this.item});
  @override
  State<ItemPage> createState() => _ItemPageState();
}

class _ItemPageState extends State<ItemPage> {
  late Future<dynamic> future;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    reload();
    timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(reload);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void reload() {
    future = api.call('GET', '/item/${widget.item['id']}');
  }

  void refresh() {
    if (mounted) setState(reload);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: kindTitle(widget.item['kind']),
    child: FutureBuilder(
      future: future,
      builder: (c, s) {
        if (s.hasError) return Failure(message: '${s.error}', retry: refresh);
        if (!s.hasData) return const Center(child: CircularProgressIndicator());
        final i = Map<String, dynamic>.from(s.data as Map),
            d = Map<String, dynamic>.from(i['data']),
            kind = i['kind'],
            own = i['owner_id'] == api.me!['id'];
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            if (kind == 'posts')
              PostCard(item: i, changed: refresh)
            else ...[
              Text(
                d['title'] ?? i['author'] ?? '',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(stamp(i['created']), style: const TextStyle(color: muted)),
              const SizedBox(height: 18),
              if (kind == 'stories')
                Text(
                  'Доступна до ${stamp(i['expires'])}',
                  style: const TextStyle(color: muted),
                ),
              if (d['media'] != null) Gallery(List<dynamic>.from(d['media'])),
              for (final f in fieldsFor(kind))
                if ((d[f.key] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.label,
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          f.type == 'date' || f.type == 'datetime'
                              ? displayDate('${d[f.key]}', f.type)
                              : categoryNames[d[f.key]] ?? '${d[f.key]}',
                          style: const TextStyle(fontSize: 17, height: 1.4),
                        ),
                      ],
                    ),
                  ),
              if (kind == 'vet') ...[
                const Text(
                  Ru.text209,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => open(
                    ItemEditor(
                      kind: 'reminders',
                      defaults: {
                        'vet_id': i['id'],
                        'title': 'После: ${d['title']}',
                      },
                    ),
                  ),
                  icon: const Icon(Icons.notifications_none),
                  label: const Text(Ru.text208),
                ),
              ],
              if (kind == 'reminders') ...[
                Text('Часовой пояс: ${d['timezone']}'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(Ru.text207),
                  value: d['done'] == true,
                  onChanged: (v) => guarded(() async {
                    await api.call('PUT', '/item/${i['id']}', {
                      'data': {...d, 'done': v},
                    });
                    await platform.syncReminders(api);
                    refresh();
                  }),
                ),
                ...List<dynamic>.from(d['tasks'] ?? []).asMap().entries.map(
                  (e) => CheckboxListTile(
                    value: e.value['done'] == true,
                    title: Text(e.value['title']),
                    onChanged: (v) => guarded(() async {
                      final tasks = List<dynamic>.from(d['tasks']);
                      tasks[e.key] = {...e.value, 'done': v};
                      await api.call('PUT', '/item/${i['id']}', {
                        'data': {...d, 'tasks': tasks},
                      });
                      refresh();
                    }),
                  ),
                ),
              ],
              if (kind == 'stories') ...[
                TextButton.icon(
                  onPressed: () => guarded(() async {
                    await api.call('PUT', '/item/${i['id']}/like', {
                      'active': i['liked'] != true,
                    });
                    refresh();
                  }),
                  icon: Icon(
                    i['liked'] == true
                        ? Icons.favorite
                        : Icons.favorite_outline,
                  ),
                  label: Text('${i['likes']}'),
                ),
                if (own)
                  OutlinedButton(
                    onPressed: () => open(
                      PeoplePage(
                        title: Ru.text206,
                        path: '/stories/${i['id']}/views',
                      ),
                    ),
                    child: const Text(Ru.text205),
                  )
                else
                  FilledButton(
                    onPressed: () => startChat(i['owner_id'], story: i['id']),
                    child: const Text(Ru.text204),
                  ),
              ],
              if (kind == 'markers') ...[
                Text(
                  d['status'] == 'closed' ? Ru.text203 : Ru.text202,
                  style: const TextStyle(color: muted),
                ),
                FilledButton(
                  onPressed: () => open(MapDiscussion(marker: i['id'])),
                  child: const Text(Ru.text29),
                ),
                if (own && d['status'] != 'closed')
                  TextButton(
                    onPressed: () => guarded(() async {
                      await api.call('PUT', '/item/${i['id']}', {
                        'data': {...d, 'status': 'closed'},
                      });
                      refresh();
                    }),
                    child: const Text(Ru.text201),
                  ),
              ],
              if (!['vet', 'reminders'].contains(kind))
                TextButton(
                  onPressed: () => open(
                    PageFrame(
                      title: Ru.text200,
                      child: ProfilePane(account: i['owner_id']),
                    ),
                  ),
                  child: const Text(Ru.text199),
                ),
            ],
            if (own) ...[
              const SizedBox(height: 20),
              if (!['stories', 'posts', 'messages'].contains(kind))
                OutlinedButton.icon(
                  onPressed: () async {
                    await open(ItemEditor(kind: kind, item: i));
                    refresh();
                  },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text(Ru.text198),
                ),
              TextButton.icon(
                onPressed: () => guarded(() async {
                  if (await confirm(Ru.text197, Ru.text196, yes: Ru.text106)) {
                    await api.call('DELETE', '/item/${i['id']}');
                    api.invalidateImages();
                    if (kind == 'reminders') await platform.syncReminders(api);
                    if (context.mounted) Navigator.pop(context);
                  }
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text(Ru.text106),
              ),
            ] else
              TextButton(
                onPressed: () =>
                    open(ItemEditor(kind: 'reports', target: i['id'])),
                child: const Text(Ru.text146),
              ),
          ],
        );
      },
    ),
  );
}
