part of '../../main.dart';

class MapPane extends StatefulWidget {
  const MapPane({super.key});
  @override
  State<MapPane> createState() => _MapPaneState();
}

class _MapPaneState extends State<MapPane> {
  final controller = MapController();
  LatLng point = const LatLng(55.751244, 37.618423);
  List<Map<String, dynamic>> items = [];
  bool news = false, loading = false, selected = false, ready = false;
  String? error;
  Timer? debounce;
  int generation = 0;
  @override
  void dispose() {
    debounce?.cancel();
    super.dispose();
  }

  void schedule() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 450), load);
  }

  Future<void> load() async {
    final gen = ++generation;
    setState(() => loading = true);
    try {
      final b = controller.camera.visibleBounds;
      final all = <Map<String, dynamic>>[];
      Map? cursor;
      do {
        var path =
            '/items/${news ? 'news' : 'markers'}?limit=50&west=${b.west}&south=${b.south}&east=${b.east}&north=${b.north}';
        if (cursor != null) {
          path +=
              '&before=${cursor['before']}&cursor_id=${cursor['cursor_id']}';
        }
        final r = await api.call('GET', path);
        all.addAll(
          (r['items'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        cursor = r['next'];
      } while (cursor != null && gen == generation);
      if (mounted && gen == generation) {
        setState(() {
          items = all;
          error = null;
        });
      }
    } catch (e) {
      if (mounted && gen == generation) setState(() => error = '$e');
    } finally {
      if (mounted && gen == generation) setState(() => loading = false);
    }
  }

  Future<void> locate() => guarded(() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw ApiFailure(Ru.text195);
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 15),
      ),
    );
    if (mounted) {
      point = LatLng(p.latitude, p.longitude);
      controller.move(point, 14);
      setState(() => selected = true);
    }
  });
  Future<void> add() async {
    if (!selected) {
      note(Ru.text194);
      return;
    }
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.warning_amber),
              title: const Text(Ru.text193),
              onTap: () => Navigator.pop(c, 'markers'),
            ),
            ListTile(
              leading: const Icon(Icons.newspaper_outlined),
              title: const Text(Ru.text192),
              onTap: () => Navigator.pop(c, 'news'),
            ),
          ],
        ),
      ),
    );
    if (kind == null) return;
    await open(
      ItemEditor(
        kind: kind,
        defaults: {
          'lat': point.latitude,
          'lng': point.longitude,
          'city': api.me?['pet']?['city'] ?? '',
        },
      ),
    );
    if (mounted) load();
  }

  List<Marker> markers() {
    final groups = <String, List<Map<String, dynamic>>>{};
    final zoom = controller.camera.zoom,
        step = 360 / (1 << controller.camera.zoom.floor().clamp(1, 20)) * .2;
    for (final i in items) {
      final d = i['data'];
      groups
          .putIfAbsent(
            '${(d['lat'] / step).floor()}:${(d['lng'] / step).floor()}',
            () => [],
          )
          .add(i);
    }
    return groups.values.map((g) {
      final d = g.first['data'];
      final pos = LatLng(
        (d['lat'] as num).toDouble(),
        (d['lng'] as num).toDouble(),
      );
      return Marker(
        point: pos,
        width: 48,
        height: 48,
        child: IconButton.filled(
          tooltip: g.length > 1 ? '${g.length} объектов' : d['title'],
          onPressed: () async {
            if (g.length > 1) {
              controller.move(pos, zoom + 2);
            } else {
              await open(ItemPage(item: g.first));
              if (mounted) load();
            }
          },
          icon: g.length > 1
              ? Text('${g.length}')
              : Icon(news ? Icons.newspaper : Icons.pets),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text(Ru.text191)),
                  ButtonSegment(value: true, label: Text(Ru.text190)),
                ],
                selected: {news},
                onSelectionChanged: (s) {
                  setState(() => news = s.first);
                  load();
                },
              ),
            ),
            IconButton(
              tooltip: Ru.text189,
              onPressed: locate,
              icon: const Icon(Icons.my_location),
            ),
          ],
        ),
      ),
      Expanded(
        flex: 3,
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: point,
                initialZoom: 12,
                onMapReady: () {
                  setState(() => ready = true);
                  load();
                },
                onPositionChanged: (_, __) => schedule(),
                onTap: (_, p) => setState(() {
                  point = p;
                  selected = true;
                }),
              ),
              children: [
                TileLayer(
                  urlTemplate: const String.fromEnvironment(
                    'MAP_TILE_URL',
                    defaultValue:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  ),
                  userAgentPackageName: 'app.zuzu.mobile',
                ),
                if (ready)
                  MarkerLayer(
                    markers: [
                      ...markers(),
                      if (selected)
                        Marker(
                          point: point,
                          width: 48,
                          height: 48,
                          child: const Icon(
                            Icons.location_pin,
                            size: 46,
                            color: brown,
                          ),
                        ),
                    ],
                  ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      const String.fromEnvironment(
                        'MAP_ATTRIBUTION',
                        defaultValue: '© OpenStreetMap contributors',
                      ),
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 8,
              child: IgnorePointer(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      selected
                          ? '${point.latitude.toStringAsFixed(4)}, ${point.longitude.toStringAsFixed(4)}'
                          : Ru.text188,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 32,
              right: 16,
              child: FloatingActionButton(
                tooltip: Ru.text187,
                onPressed: add,
                child: const Icon(Icons.add),
              ),
            ),
            if (loading) const LinearProgressIndicator(),
          ],
        ),
      ),
      Expanded(
        flex: 2,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              news ? Ru.text186 : Ru.text185,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            if (error != null) Failure(message: error!, retry: load),
            if (items.isEmpty && !loading)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(Ru.text184),
              ),
            ...items.map(
              (i) => Card(
                child: ListTile(
                  title: Text(i['data']['title']),
                  subtitle: Text('${i['author']} · ${stamp(i['created'])}'),
                  onTap: () async {
                    await open(ItemPage(item: i));
                    if (mounted) load();
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class MapDiscussion extends StatefulWidget {
  final String marker;
  const MapDiscussion({super.key, required this.marker});
  @override
  State<MapDiscussion> createState() => _MapDiscussionState();
}

class _MapDiscussionState extends State<MapDiscussion> {
  final key = GlobalKey<PagedListState>();
  @override
  Widget build(BuildContext context) => PageFrame(
    title: Ru.text29,
    actions: [
      IconButton(
        tooltip: Ru.text183,
        onPressed: () async {
          await open(ItemEditor(kind: 'map_messages', target: widget.marker));
          key.currentState?.reload();
        },
        icon: const Icon(Icons.add_comment_outlined),
      ),
    ],
    child: PagedList(
      key: key,
      path: '/items/map_messages?target=${widget.marker}',
      tile: (i) => Card(
        child: ListTile(
          title: Text(i['data']['text']),
          subtitle: Text('${i['author']} · ${stamp(i['created'])}'),
          onTap: () => open(ItemPage(item: i)),
        ),
      ),
    ),
  );
}
