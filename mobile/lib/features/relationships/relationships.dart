part of '../../main.dart';

class PeoplePage extends StatelessWidget {
  final String title, path;
  const PeoplePage({super.key, required this.title, required this.path});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: title,
    child: PagedList(
      path: path,
      tile: (p) => Card(
        child: ListTile(
          leading: Avatar(p['pet']?['photo']),
          title: Text(p['pet']?['name'] ?? p['owner']['name'] ?? ''),
          subtitle: Text('@${p['pet']?['handle'] ?? p['handle'] ?? ''}'),
          onTap: () => open(
            PageFrame(
              title: Ru.text228,
              child: ProfilePane(account: p['id']),
            ),
          ),
        ),
      ),
    ),
  );
}

class RelationshipsPage extends StatefulWidget {
  final bool blocked;
  const RelationshipsPage({super.key, this.blocked = false});
  @override
  State<RelationshipsPage> createState() => _RelationshipsPageState();
}

class _RelationshipsPageState extends State<RelationshipsPage> {
  final key = GlobalKey<PagedListState>();
  String filter = Ru.text305, q = '';
  Future<void> action(
    String other,
    String kind,
    Map<String, dynamic> data,
  ) async {
    await api.call('PUT', '/relationships/$other/$kind', data);
    api.invalidateImages();
    key.currentState?.reload();
    await api.refreshMe();
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: widget.blocked ? Ru.text100 : Ru.text134,
    child: PagedList(
      key: key,
      path: '/relationships',
      emptyTitle: Ru.text308,
      emptyText: Ru.text307,
      header: Column(
        children: [
          TextField(
            decoration: const InputDecoration(
              hintText: Ru.text306,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => q = v.toLowerCase()),
          ),
          if (!widget.blocked)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Wrap(
                spacing: 8,
                children:
                    [Ru.text305, Ru.text251, Ru.text304, Ru.text303, Ru.text302]
                        .map(
                          (v) => ChoiceChip(
                            label: Text(v),
                            selected: filter == v,
                            onSelected: (_) => setState(() => filter = v),
                          ),
                        )
                        .toList(),
              ),
            ),
        ],
      ),
      tile: (e) {
        final p = e['profile'] as Map,
            other = p['id'],
            incoming = e['target'] == api.me!['id'],
            kind = e['kind'];
        final show = widget.blocked
            ? kind == 'block'
            : kind != 'block' &&
                  switch (filter) {
                    Ru.text251 => kind == 'friend' && e['status'] == 'accepted',
                    Ru.text304 => kind == 'friend' && e['status'] == 'pending',
                    Ru.text303 => kind == 'follow' && incoming,
                    Ru.text302 => kind == 'follow' && !incoming,
                    _ => true,
                  };
        final name = p['pet']?['name'] ?? p['owner']['name'] ?? '';
        if (!show ||
            q.isNotEmpty && !name.toString().toLowerCase().contains(q)) {
          return const SizedBox.shrink();
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Avatar(p['pet']?['photo']),
                  title: Text(name),
                  subtitle: Text(
                    kind == 'block'
                        ? Ru.text301
                        : kind == 'follow'
                        ? incoming
                              ? Ru.text300
                              : Ru.text299
                        : e['status'] == 'accepted'
                        ? Ru.text251
                        : incoming
                        ? Ru.text298
                        : Ru.text297,
                  ),
                  onTap: kind == 'block'
                      ? null
                      : () => open(
                          PageFrame(
                            title: Ru.text228,
                            child: ProfilePane(account: other),
                          ),
                        ),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    if (kind == 'block')
                      TextButton(
                        onPressed: () => guarded(
                          () => action(other, 'block', {'active': false}),
                        ),
                        child: const Text(Ru.text296),
                      ),
                    if (kind == 'friend' && e['status'] == 'pending') ...[
                      if (incoming)
                        FilledButton(
                          onPressed: () => guarded(
                            () => action(other, 'friend', {
                              'operation': 'accept',
                            }),
                          ),
                          child: const Text(Ru.text295),
                        ),
                      TextButton(
                        onPressed: () => guarded(
                          () => action(other, 'friend', {
                            'operation': incoming ? 'decline' : 'cancel',
                          }),
                        ),
                        child: Text(incoming ? Ru.text294 : Ru.text293),
                      ),
                    ],
                    if (kind == 'friend' && e['status'] == 'accepted')
                      TextButton(
                        onPressed: () => guarded(
                          () =>
                              action(other, 'friend', {'operation': 'remove'}),
                        ),
                        child: const Text(Ru.text292),
                      ),
                    if (kind == 'follow' && !incoming)
                      TextButton(
                        onPressed: () => guarded(
                          () => action(other, 'follow', {'active': false}),
                        ),
                        child: const Text(Ru.text249),
                      ),
                    if (kind != 'block')
                      TextButton(
                        onPressed: () => startChat(other),
                        child: const Text(Ru.text245),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
