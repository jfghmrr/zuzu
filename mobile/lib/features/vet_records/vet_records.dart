part of '../../main.dart';

class VetPage extends StatefulWidget {
  const VetPage({super.key});
  @override
  State<VetPage> createState() => _VetPageState();
}

class _VetPageState extends State<VetPage> {
  final key = GlobalKey<PagedListState>();
  @override
  Widget build(BuildContext context) {
    final p = api.me!['pet'] ?? {};
    return PageFrame(
      title: Ru.text136,
      actions: [
        IconButton(
          tooltip: Ru.text162,
          onPressed: () async {
            await open(const ItemEditor(kind: 'vet'));
            key.currentState?.reload();
          },
          icon: const Icon(Icons.add),
        ),
      ],
      child: PagedList(
        key: key,
        path: '/items/vet',
        emptyTitle: Ru.text161,
        emptyText: Ru.text160,
        header: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Avatar(p['photo'], size: 68),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p['name'] ?? '',
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(p['species'] ?? ''),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    Text('Вес: ${p['weight'] ?? '—'} кг'),
                    Text('Рост: ${p['height'] ?? '—'} см'),
                    Text('Пол: ${p['sex'] ?? '—'}'),
                    Text(
                      'Возраст: ${p['age_months'] == null ? Ru.text159 : '${p['age_months']} мес.'}',
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const Row(
                  children: [
                    Icon(Icons.lock_outline, size: 17, color: muted),
                    SizedBox(width: 7),
                    Expanded(
                      child: Text(Ru.text158, style: TextStyle(color: muted)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () async {
                    await open(const ItemEditor(kind: 'vet'));
                    key.currentState?.reload();
                  },
                  icon: const Icon(Icons.add),
                  label: const Text(Ru.text157),
                ),
              ],
            ),
          ),
        ),
        tile: (i) => Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: yellow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.description_outlined),
            ),
            title: Text(
              i['data']['title'],
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              '${i['data']['visit_date']} · ${(i['data']['media'] as List? ?? []).length} фото',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await open(ItemPage(item: i));
              key.currentState?.reload();
            },
          ),
        ),
      ),
    );
  }
}
