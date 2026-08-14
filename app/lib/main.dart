import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swipewise/features/ask/ask_screen.dart';
import 'package:swipewise/features/cards/cards_screen.dart';
import 'package:swipewise/theme/tokens.dart';

void main() {
  runApp(const ProviderScope(child: SwipewiseApp()));
}

class SwipewiseApp extends StatelessWidget {
  const SwipewiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'swipewise',
      debugShowCheckedModeBanner: false,
      theme: buildSwipewiseTheme(SwipewiseTokens.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Scaffold(
      backgroundColor: tokens.background,
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: const [AskScreen(), CardsScreen()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: tokens.surface,
        indicatorColor: tokens.accent.withValues(alpha: 0.18),
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.help_outline),
            selectedIcon: Icon(Icons.help),
            label: 'Ask',
          ),
          NavigationDestination(
            icon: Icon(Icons.speed_outlined),
            selectedIcon: Icon(Icons.speed),
            label: 'Caps',
          ),
        ],
      ),
    );
  }
}
