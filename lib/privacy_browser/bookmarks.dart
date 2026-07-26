/// Hardcoded only — never persisted (prefs are wiped every launch).
class Bookmark {
  const Bookmark({required this.title, required this.url});

  final String title;
  final String url;
}

/// Prefer [kBuiltInBookmarks] in privacy_browser_shell.dart (this file is unused).
const List<Bookmark> kBookmarks = [
  Bookmark(
    title: 'Jiurelay',
    url: 'https://jiurelay.com/r/JR-UQYJQT',
  ),
];
