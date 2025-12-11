import 'package:flutter/material.dart';
import '../../ui/screen_capture_test_page.dart';
import '../../ui/script_test_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _pages = const [
    ScreenCaptureTestPage(),
    ScriptTestPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GameMaps'),
      ),
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.image),
                selectedIcon: Icon(Icons.image_outlined),
                label: Text('功能页面'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.code),
                selectedIcon: Icon(Icons.code_off),
                label: Text('脚本测试'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: _pages,
            ),
          ),
        ],
      ),
    );
  }
}

