part of '../../main.dart';

class StoryStrip extends StatefulWidget {
  const StoryStrip({super.key});
  @override
  State<StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<StoryStrip> {
  late Future<dynamic> future;
  void load() => future = api.call('GET', '/items/stories?limit=50');
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (c, s) => SizedBox(
      height: 92,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        scrollDirection: Axis.horizontal,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Semantics(
              label: 'Добавить историю',
              button: true,
              child: InkWell(
                onTap: () async {
                  await open(const ItemEditor(kind: 'stories'));
                  if (mounted) setState(load);
                },
                child: SizedBox(
                  width: 86,
                  height: 92,
                  child: Stack(
                    children: [
                      PairedAvatar(
                        pet: api.me?['pet']?['photo'],
                        owner: api.me?['owner']?['photo'],
                        size: 80,
                        ownerSize: 30,
                      ),
                      Positioned(
                        left: 0,
                        bottom: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: yellow,
                          ),
                          child: const DesignIcon(
                            'plus',
                            size: 18,
                            color: brown,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (s.hasError)
            IconButton(
              tooltip: 'Повторить загрузку историй',
              onPressed: () => setState(load),
              icon: const Icon(Icons.refresh),
            ),
          if (s.hasData)
            for (final i in s.data['items'])
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Semantics(
                  label: 'История: ${i['author']}',
                  button: true,
                  child: InkWell(
                    onTap: () => guarded(() async {
                      await api.call('POST', '/stories/${i['id']}/view');
                      await open(ItemPage(item: Map<String, dynamic>.from(i)));
                      if (mounted) setState(load);
                    }),
                    child: PairedAvatar(
                      pet: i['avatar'],
                      owner: i['owner_avatar'],
                      size: 80,
                      ownerSize: 30,
                    ),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}
