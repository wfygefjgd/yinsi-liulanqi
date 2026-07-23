/// Hardcoded only — never persisted (prefs are wiped every launch).
class Bookmark {
  const Bookmark({required this.title, required this.url});

  final String title;
  final String url;
}

const List<Bookmark> kBookmarks = [
  Bookmark(
    title: 'Jiurelay',
    url: 'https://jiurelay.com/r/JR-UQYJQT',
  ),
];
