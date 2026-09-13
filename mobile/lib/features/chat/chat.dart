part of '../../main.dart';

Future<void> startChat(String account, {String? story}) => guarded(() async {
  final r = await api.call('POST', '/conversations', {'account_id': account});
  await open(ChatPage(cid: r['id'], story: story));
});

class ChatsPane extends StatefulWidget {
  const ChatsPane({super.key});
  @override
  State<ChatsPane> createState() => _ChatsPaneState();
}

class _ChatsPaneState extends State<ChatsPane> {
  String q = '';
  Timer? timer;
  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PagedList(
    path: '/conversations?q=${Uri.encodeComponent(q)}',
    pollSeconds: 6,
    emptyTitle: Ru.text156,
    emptyText: Ru.text155,
    header: Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        decoration: const InputDecoration(
          hintText: Ru.text154,
          prefixIcon: Icon(Icons.search),
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
    tile: (i) {
      final p = i['profile'];
      return Card(
        child: ListTile(
          leading: Avatar(p['pet']?['photo']),
          title: Text(p['pet']?['name'] ?? p['owner']['name'] ?? ''),
          subtitle: Text(
            i['last']?['data']?['text'] ?? Ru.text153,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i['last'] != null)
                Text(
                  stamp(i['last']['created']),
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
              if (i['unread'] > 0) Badge(label: Text('${i['unread']}')),
            ],
          ),
          onTap: () => open(ChatPage(cid: i['id'])),
        ),
      );
    },
  );
}

class ChatPage extends StatefulWidget {
  final String cid;
  final String? story;
  const ChatPage({super.key, required this.cid, this.story});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final text = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  final pending = <String, Map<String, dynamic>>{};
  dynamic next;
  String? error, attachment;
  bool loading = true, sending = false, fetching = false;
  Timer? timer;
  String? story;
  @override
  void initState() {
    super.initState();
    story = widget.story;
    fetch();
    timer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => fetch(silent: true),
    );
  }

  @override
  void dispose() {
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> fetch({bool more = false, bool silent = false}) async {
    if (fetching || api.me == null) return;
    fetching = true;
    try {
      var path = '/items/messages?target=${widget.cid}';
      if (more && next != null) {
        path += '&before=${next['before']}&cursor_id=${next['cursor_id']}';
      }
      final r = await api.call('GET', path);
      if (!mounted) return;
      final fresh = (r['items'] as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      setState(() {
        if (more) {
          rows = [...rows, ...fresh];
          next = r['next'];
        } else {
          final ids = fresh.map((e) => e['id']).toSet();
          rows = [
            ...fresh,
            ...rows.where(
              (e) =>
                  !ids.contains(e['id']) &&
                  (fresh.isEmpty || e['created'] < fresh.last['created']),
            ),
          ];
          if (rows.length <= 20) next = r['next'];
          for (final id in ids) {
            pending.remove(id);
          }
        }
        loading = false;
        error = null;
      });
      if (fresh.isNotEmpty && !more) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            api
                .call('POST', '/conversations/${widget.cid}/read', {
                  'message_id': fresh.first['id'],
                })
                .catchError((_) => null);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    } finally {
      fetching = false;
    }
  }

  Future<void> choose() async {
    await guarded(() async {
      final f = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (f == null) return;
      setState(() => sending = true);
      try {
        attachment = await api.upload(await f.readAsBytes(), 'chat');
      } finally {
        if (mounted) setState(() => sending = false);
      }
    });
  }

  Future<void> enqueue() async {
    if (text.text.trim().isEmpty && attachment == null) return;
    final id = const Uuid().v4();
    final d = <String, dynamic>{
      'text': text.text.trim(),
      if (attachment != null) 'media': [attachment],
      if (story != null) 'story_id': story,
    };
    setState(() {
      pending[id] = {'data': d, 'failed': false};
      text.clear();
      attachment = null;
      story = null;
    });
    await send(id);
  }

  Future<void> send(String id) async {
    final p = pending[id];
    if (p == null) return;
    setState(() {
      p['failed'] = false;
      sending = true;
    });
    try {
      final r = await api.call('POST', '/items/messages', {
        'id': id,
        'target': widget.cid,
        'data': p['data'],
      });
      if (mounted) {
        setState(() {
          pending.remove(id);
          rows.removeWhere((i) => i['id'] == id);
          rows.insert(0, Map<String, dynamic>.from(r));
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          p['failed'] = true;
          error = '$e';
        });
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text152,
    child: Column(
      children: [
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: () => fetch(),
                child: const Text(Ru.text71),
              ),
            ],
          ),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  children: [
                    ...pending.entries.toList().reversed.map(
                      (e) => Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: yellow,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(e.value['data']['text']),
                              if (e.value['data']['media'] != null)
                                Gallery(e.value['data']['media']),
                              if (e.value['failed'] == true)
                                TextButton(
                                  onPressed: sending ? null : () => send(e.key),
                                  child: const Text(Ru.text151),
                                )
                              else
                                const Text(
                                  Ru.text150,
                                  style: TextStyle(fontSize: 11, color: muted),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ...rows.map((i) {
                      final own = i['owner_id'] == api.me?['id'], d = i['data'];
                      return Align(
                        alignment: own
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.sizeOf(context).width * .78,
                          ),
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: own ? yellow : Colors.white,
                            border: Border.all(color: const Color(0xffeee8dd)),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (d['story_id'] != null)
                                Text(
                                  i['story_available'] == true
                                      ? Ru.text142
                                      : Ru.text149,
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 12,
                                  ),
                                ),
                              if (d['media'] != null) Gallery(d['media']),
                              if ((d['text'] ?? '').isNotEmpty)
                                Text(
                                  d['text'],
                                  style: const TextStyle(
                                    fontSize: 16,
                                    height: 1.4,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                '${stamp(i['created'])}${own ? (i['read'] == true ? Ru.text148 : Ru.text147) : ''}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: muted,
                                ),
                              ),
                              if (!own)
                                TextButton(
                                  onPressed: () => open(
                                    ItemEditor(
                                      kind: 'reports',
                                      target: i['id'],
                                    ),
                                  ),
                                  child: const Text(Ru.text146),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (rows.isEmpty && pending.isEmpty)
                      const Empty(Ru.text145, Ru.text144),
                    if (next != null)
                      TextButton(
                        onPressed: () => fetch(more: true),
                        child: const Text(Ru.text143),
                      ),
                  ],
                ),
        ),
        if (story != null)
          ListTile(
            dense: true,
            title: const Text(Ru.text142),
            trailing: IconButton(
              tooltip: Ru.text141,
              onPressed: () => setState(() => story = null),
              icon: const Icon(Icons.close),
            ),
          ),
        if (attachment != null)
          Row(
            children: [
              Photo(attachment, width: 65, height: 65),
              IconButton(
                tooltip: Ru.text140,
                onPressed: () => setState(() => attachment = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                tooltip: Ru.text139,
                onPressed: sending ? null : choose,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: Ru.text28,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: Ru.text138,
                onPressed: sending ? null : enqueue,
                icon: const Icon(Icons.arrow_upward),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
