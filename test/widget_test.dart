import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yinsi_liulanqi/privacy_browser/privacy_browser_shell.dart';
import 'package:yinsi_liulanqi/privacy_browser/tab_manager.dart';

void main() {
  testWidgets('classic shell builds', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => TabManager(maxTabs: 8),
        child: const MaterialApp(home: PrivacyBrowserShell()),
      ),
    );
    await tester.pump();
    expect(find.text('搜索或输入网址'), findsOneWidget);
  });
}
