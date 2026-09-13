part of '../../main.dart';

class OwnerPane extends StatefulWidget {
  const OwnerPane({super.key});
  @override
  State<OwnerPane> createState() => _OwnerPaneState();
}

class _OwnerPaneState extends State<OwnerPane> {
  Future<void> edit() async {
    await open(const ProfileEditor());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final profile = api.me!,
        owner = profile['owner'] as Map,
        pet = profile['pet'] as Map;
    const levels = [
      'Новый друг',
      'Свой человек',
      'Опытный хозяин',
      'Авторитет',
      'Легенда',
    ];
    final level = levels.indexOf(profile['level'] ?? 'Новый друг') + 1;
    return RefreshIndicator(
      onRefresh: () async {
        await api.refreshMe();
        if (mounted) setState(() {});
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(15, 20, 15, 14),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    children: [
                      Avatar(owner['photo'], size: 116),
                      const SizedBox(height: 18),
                      Text(
                        '${owner['name'] ?? ''} ${owner['surname'] ?? ''}'
                            .trim(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 24 / 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${profile['handle'] ?? ''}',
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
                  right: -8,
                  top: -12,
                  child: PopupMenuButton<String>(
                    tooltip: 'Действия с профилем',
                    icon: const Icon(Icons.more_vert, size: 20, color: muted),
                    onSelected: (_) => edit(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Редактировать'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _section(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Статус',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '${owner['status'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
          ),
          _section(
            ExpansionTile(
              dense: true,
              minTileHeight: 34,
              visualDensity: VisualDensity.compact,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 15),
              title: Row(
                children: [
                  const Text(
                    'Уровень',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$level',
                    style: const TextStyle(color: orange, fontSize: 14),
                  ),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(15, 0, 15, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Вы с нами с ${DateFormat('dd.MM.yy').format(DateTime.fromMillisecondsSinceEpoch((profile['created'] * 1000).toInt()))}.',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < levels.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'Уровень ${i + 1} — «${levels[i]}»',
                            style: const TextStyle(fontSize: 12, color: muted),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _section(
            ExpansionTile(
              dense: true,
              minTileHeight: 34,
              visualDensity: VisualDensity.compact,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: const EdgeInsets.symmetric(horizontal: 15),
              title: Row(
                children: [
                  const Text(
                    'Достижения',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${profile['achievements'] ?? 0}',
                    style: const TextStyle(color: orange, fontSize: 14),
                  ),
                  const Icon(Icons.star_border, size: 14, color: orange),
                ],
              ),
              children: const [
                Padding(
                  padding: EdgeInsets.fromLTRB(15, 0, 15, 12),
                  child: Text(
                    'Достижения = посты + метки на ЗуЗу-карте',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          _section(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  const Text(
                    'Мои питомцы',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => open(
                      PageFrame(
                        title: Ru.text94,
                        child: ProfilePane(account: profile['id']),
                      ),
                    ),
                    child: Column(
                      children: [
                        Avatar(pet['photo'], size: 60),
                        const SizedBox(height: 6),
                        Text(
                          '${pet['name']}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(Widget child) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: divider),
    ),
    child: child,
  );
}
