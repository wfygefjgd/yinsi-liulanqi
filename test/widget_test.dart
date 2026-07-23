import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yinsi_liulanqi/privacy_browser/bookmarks.dart';
import 'package:yinsi_liulanqi/privacy_browser/privacy_browser_shell.dart';
import 'package:yinsi_liulanqi/privacy_browser/tab_manager.dart';

void main() {
  testWidgets('shell builds with bookmark provider', (tester) async {
    final store = BookmarkStore();
    // skip durable load in unit test — inject empty ready list
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: store),
          ChangeNotifierProvider(create: (_) => TabManager(maxTabs: 3)),
        ],
        child: const MaterialApp(home: PrivacyBrowserShell()),
      ),
    );
    await tester.pump();
    expect(find.text('搜索或输入网站名称'), findsOneWidget);
    expect(find.text('个人收藏'), findsOneWidget);
  });
}
