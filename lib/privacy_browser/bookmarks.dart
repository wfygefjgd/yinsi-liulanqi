import 'package:flutter/foundation.dart';

import 'durable_store.dart';

class Bookmark {
  const Bookmark({required this.title, required this.url});

  final String title;
  final String url;

  Map<String, dynamic> toJson() => {'title': title, 'url': url};

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        title: (j['title'] as String?)?.trim().isNotEmpty == true
            ? (j['title'] as String).trim()
            : _titleFromUrl(j['url'] as String? ?? ''),
        url: (j['url'] as String? ?? '').trim(),
      );

  static String _titleFromUrl(String url) {
    try {
      final u = Uri.parse(url);
      return u.host.isNotEmpty ? u.host : url;
    } catch (_) {
      return url;
    }
  }
}

/// Seed only when durable file is missing.
const List<Bookmark> kDefaultBookmarks = [
  Bookmark(
    title: 'Jiurelay',
    url: 'https://jiurelay.com/r/JR-UQYJQT',
  ),
];

class BookmarkStore extends ChangeNotifier {
  BookmarkStore();

  List<Bookmark> _items = [];
  bool _ready = false;

  List<Bookmark> get items => List.unmodifiable(_items);
  bool get ready => _ready;

  Future<void> load() async {
    _items = await DurableStore.loadBookmarks();
    _ready = true;
    notifyListeners();
  }

  Future<void> add(Bookmark b) async {
    final url = b.url.trim();
    if (url.isEmpty) return;
    final exists = _items.any((e) => e.url == url);
    if (exists) {
      _items = [
        for (final e in _items)
          if (e.url == url)
            Bookmark(
              title: b.title.trim().isEmpty ? e.title : b.title.trim(),
              url: url,
            )
          else
            e,
      ];
    } else {
      _items = [
        ..._items,
        Bookmark(
          title: b.title.trim().isEmpty
              ? Bookmark._titleFromUrl(url)
              : b.title.trim(),
          url: url,
        ),
      ];
    }
    await DurableStore.saveBookmarks(_items);
    notifyListeners();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _items.length) return;
    _items = [..._items]..removeAt(index);
    await DurableStore.saveBookmarks(_items);
    notifyListeners();
  }

  Future<void> removeUrl(String url) async {
    _items = _items.where((e) => e.url != url).toList();
    await DurableStore.saveBookmarks(_items);
    notifyListeners();
  }
}
