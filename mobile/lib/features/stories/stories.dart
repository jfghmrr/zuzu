part of '../../main.dart';

class StoryStrip extends StatefulWidget {
  const StoryStrip({super.key});
  @override
  State<StoryStrip> createState() => _StoryStripState();
}

class _StoryStripState extends State<StoryStrip> {
  late Future<dynamic> future;
  @override
  void initState() {
    super.initState();
    future = api.call('GET', '/items/stories?limit=50');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: future,
    builder: (c, s) => SizedBox(
      height: 116,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: 90,
            child: Column(
              children: [
                IconButton.filledTonal(
                  tooltip: Ru.text182,
                  iconSize: 32,
                  padding: const EdgeInsets.all(18),
                  onPressed: () async {
                    await open(const ItemEditor(kind: 'stories'));
                    if (mounted) {
                      setState(
                        () =>
                            future = api.call('GET', '/items/stories?limit=50'),
                      );
                    }
                  },
                  icon: const Icon(Icons.add),
                ),
                const SizedBox(height: 8),
                const Text(Ru.text181, style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          if (s.hasError)
            IconButton(
              tooltip: Ru.text180,
              onPressed: () => setState(
                () => future = api.call('GET', '/items/stories?limit=50'),
              ),
              icon: const Icon(Icons.refresh),
            ),
          if (s.hasData)
            for (final i in s.data['items'])
              SizedBox(
                width: 86,
                child: InkWell(
                  onTap: () => guarded(() async {
                    await api.call('POST', '/stories/${i['id']}/view');
                    await open(ItemPage(item: Map<String, dynamic>.from(i)));
                    if (mounted) {
                      setState(
                        () =>
                            future = api.call('GET', '/items/stories?limit=50'),
                      );
                    }
                  }),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: orange, width: 2),
                        ),
                        child: Avatar(
                          (i['data']['media'] as List).first,
                          size: 58,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        i['author'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    ),
  );
}
