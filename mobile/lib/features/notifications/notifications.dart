part of '../../main.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final key = GlobalKey<PagedListState>();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text103,
    child: PagedList(
      key: key,
      path: '/items/notifications',
      emptyTitle: Ru.text311,
      emptyText: Ru.text310,
      tile: (i) {
        final d = i['data'];
        return Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.notifications_none,
                  color: d['read'] == true ? muted : orange,
                ),
                title: Text(
                  d['title'],
                  style: TextStyle(
                    fontWeight: d['read'] == true
                        ? FontWeight.normal
                        : FontWeight.bold,
                  ),
                ),
                subtitle: Text(stamp(i['created'])),
                onTap: () => guarded(() async {
                  await api.call('PUT', '/item/${i['id']}', {
                    'data': {'read': true},
                  });
                  key.currentState?.reload();
                  await routeTo(
                    jsonEncode({'route': d['route'], 'target': i['target']}),
                  );
                }),
              ),
              if (d['route'] == 'profile')
                TextButton(
                  onPressed: () => open(const RelationshipsPage()),
                  child: const Text(Ru.text309),
                ),
            ],
          ),
        );
      },
    ),
  );
}
