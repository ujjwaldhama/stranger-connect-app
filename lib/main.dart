import 'package:flutter/material.dart';

void main() => runApp(const StrangerConnectApp());

const gold = Color(0xFFD6AD55);
const bg = Color(0xFF090909);
const panel = Color(0xFF171717);

class StrangerConnectApp extends StatelessWidget {
  const StrangerConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stranger Connect',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: gold,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: gold,
          elevation: 0,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;
  final pages = const [DiscoverScreen(), FriendsScreen(), PremiumScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.forum_rounded, color: gold),
          SizedBox(width: 9),
          Text('STRANGER CONNECT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.1, fontSize: 15)),
        ]),
        actions: [
          IconButton(onPressed: () => _showInfo(context), icon: const Icon(Icons.notifications_none_rounded)),
        ],
      ),
      body: pages[selected],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
        indicatorColor: gold.withOpacity(.16),
        selectedIndex: selected,
        onDestinationSelected: (i) => setState(() => selected = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Discover'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Friends'),
          NavigationDestination(icon: Icon(Icons.workspace_premium_outlined), selectedIcon: Icon(Icons.workspace_premium), label: 'Premium'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: panel,
      title: const Text('Notifications'),
      content: const Text('You are all caught up. Notifications will appear here.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    ));
  }
}

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(20), children: [
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF292015), Color(0xFF111111)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          border: Border.all(color: gold.withOpacity(.45)),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('YOUR NEXT\\nCONVERSATION', style: TextStyle(color: gold, fontWeight: FontWeight.w900, fontSize: 26, height: 1.15)),
          SizedBox(height: 10),
          Text('Meet someone new. Stay anonymous. Keep it respectful.', style: TextStyle(color: Colors.white70, height: 1.4)),
          SizedBox(height: 18),
          Row(children: [Icon(Icons.shield_moon_outlined, color: gold, size: 18), SizedBox(width: 7), Text('Private by design', style: TextStyle(color: gold, fontWeight: FontWeight.w600))]),
        ]),
      ),
      const SizedBox(height: 24),
      const Text('START CONNECTING', style: TextStyle(color: gold, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      _ActionTile(icon: Icons.shuffle_rounded, title: 'Find Stranger', subtitle: 'Get matched for a private chat', onTap: () => _comingSoon(context)),
      _ActionTile(icon: Icons.person_add_alt_1_rounded, title: 'Chat with Friends', subtitle: 'Connect using a private invite', onTap: () => _comingSoon(context)),
      const SizedBox(height: 20),
      const Text('YOUR EXPERIENCE', style: TextStyle(color: gold, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Row(children: const [
        Expanded(child: _StatCard(label: 'Chats', value: '0', icon: Icons.chat_bubble_outline)),
        SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Friends', value: '0', icon: Icons.people_outline)),
        SizedBox(width: 10),
        Expanded(child: _StatCard(label: 'Rating', value: '—', icon: Icons.star_outline)),
      ]),
    ]);
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('UI preview ready — backend connection is the next development step.')));
  }
}

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});
  @override
  Widget build(BuildContext context) => const _EmptyState(
    icon: Icons.people_alt_outlined, title: 'Your circle starts here',
    subtitle: 'Friends you connect with will appear here. Invite links and friend requests will be added in the next phase.',
  );
}

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const Icon(Icons.workspace_premium_rounded, color: gold, size: 58),
    const SizedBox(height: 12),
    const Text('GO PREMIUM', textAlign: TextAlign.center, style: TextStyle(color: gold, fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
    const SizedBox(height: 8),
    const Text('Unlock more ways to connect.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
    const SizedBox(height: 24),
    const _Feature(text: 'Gender preference filters'),
    const _Feature(text: 'Premium profile badge'),
    const _Feature(text: 'Priority matching options'),
    const _Feature(text: 'More profile customisation'),
    const SizedBox(height: 22),
    OutlinedButton(
      style: OutlinedButton.styleFrom(foregroundColor: gold, side: const BorderSide(color: gold), padding: const EdgeInsets.symmetric(vertical: 16)),
      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payments will be connected after backend setup.'))),
      child: const Text('EXPLORE MEMBERSHIP'),
    ),
    const SizedBox(height: 8),
    const Text('Membership pricing and payment verification are not enabled in this UI starter.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
  ]);
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(20), children: [
    const CircleAvatar(radius: 42, backgroundColor: Color(0xFF302719), child: Icon(Icons.person, size: 42, color: gold)),
    const SizedBox(height: 14),
    const Text('New Member', textAlign: TextAlign.center, style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 4),
    const Text('Create your profile to get started', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
    const SizedBox(height: 24),
    _ActionTile(icon: Icons.edit_outlined, title: 'Edit Profile', subtitle: 'Set your display name and interests', onTap: () => _profileNotice(context)),
    _ActionTile(icon: Icons.bar_chart_rounded, title: 'My Statistics', subtitle: 'Your chats, ratings and activity', onTap: () => _profileNotice(context)),
    _ActionTile(icon: Icons.security_rounded, title: 'Privacy & Safety', subtitle: 'Blocking, reporting and privacy controls', onTap: () => _profileNotice(context)),
  ]);
  void _profileNotice(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This section will be connected in the next phase.')));
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(
    color: panel, margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: gold.withOpacity(.13))),
    child: ListTile(onTap: onTap, leading: Icon(icon, color: gold, size: 27), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)), trailing: const Icon(Icons.chevron_right, color: gold)),
  );
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(15), border: Border.all(color: gold.withOpacity(.18))),
    child: Column(children: [Icon(icon, color: gold), const SizedBox(height: 8), Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)), Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11))]),
  );
}

class _Feature extends StatelessWidget {
  final String text;
  const _Feature({required this.text});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 9), child: Row(children: const [Icon(Icons.check_circle, color: gold, size: 19), SizedBox(width: 10), Expanded(child: Text(''))]).copyWithText(text));
}

extension on Widget {
  Widget copyWithText(String text) => Row(children: [const Icon(Icons.check_circle, color: gold, size: 19), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 15)))]);
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _EmptyState({required this.icon, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, color: gold, size: 64), const SizedBox(height: 18),
    Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8), Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, height: 1.5)),
  ])));
}

