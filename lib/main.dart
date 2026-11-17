
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

const gold = Color(0xFFD6AD55);
const bg = Color(0xFF090909);
const panel = Color(0xFF171717);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const StrangerConnectApp());
}

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
      home: const AuthGate(),
    );
  }
}

// --------------------------------------------------
// AUTH GATE
// --------------------------------------------------

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: gold),
            ),
          );
        }

        if (snapshot.data == null) {
          return const AuthScreen();
        }

        return const HomeScreen();
      },
    );
  }
}

// --------------------------------------------------
// SAVE USER PROFILE
// --------------------------------------------------

Future<void> saveUserProfile(
  User user, {
  String? name,
}) async {
  final reference = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid);

  final document = await reference.get();

  if (!document.exists) {
    await reference.set({
      'name': name?.trim().isNotEmpty == true
          ? name!.trim()
          : (user.displayName ?? 'New Member'),
      'email': user.email ?? '',
      'bio': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    final updates = <String, dynamic>{};

    if (user.email != null) {
      updates['email'] = user.email;
    }

    if (name != null && name.trim().isNotEmpty) {
      updates['name'] = name.trim();
    }

    if (updates.isNotEmpty) {
      await reference.set(updates, SetOptions(merge: true));
    }
  }
}

// --------------------------------------------------
// SIGNUP AND LOGIN
// --------------------------------------------------

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isRegister = false;
  bool loading = false;
  bool obscurePassword = true;
  String message = '';

  Future<void> submit() async {
    final name = nameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (isRegister && name.isEmpty) {
      setState(() => message = 'Please enter your name.');
      return;
    }

    if (email.isEmpty || !email.contains('@')) {
      setState(() => message = 'Please enter a valid email address.');
      return;
    }

    if (password.length < 6) {
      setState(() => message = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      UserCredential credential;

      if (isRegister) {
        credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        await saveUserProfile(
          credential.user!,
          name: name,
        );
      } else {
        credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        await saveUserProfile(credential.user!);
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.message ?? 'Authentication failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> googleLogin() async {
    setState(() {
      loading = true;
      message = '';
    });

    try {
      final googleUser = await GoogleSignIn().signIn();

      if (googleUser == null) {
        if (mounted) setState(() => loading = false);
        return;
      }

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final result = await FirebaseAuth.instance
          .signInWithCredential(credential);

      await saveUserProfile(result.user!);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.message ?? 'Google sign-in failed.';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = 'Google sign-in failed. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => message = 'Enter your email address first.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      if (!mounted) return;

      setState(() {
        message = 'Password reset email sent.';
      });
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      setState(() {
        message = e.message ?? 'Could not send reset email.';
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(
                Icons.forum_rounded,
                color: gold,
                size: 65,
              ),
              const SizedBox(height: 12),
              const Text(
                'STRANGER CONNECT',
                style: TextStyle(
                  color: gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Meet someone new. Stay anonymous.',
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 35),
              Text(
                isRegister ? 'CREATE ACCOUNT' : 'WELCOME BACK',
                style: const TextStyle(
                  color: gold,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 25),

              if (isRegister) ...[
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 15),
              ],

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: Icon(Icons.email_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 15),

              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility
                          : Icons.visibility_off,
                    ),
                  ),
                ),
              ),

              if (!isRegister)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: loading ? null : resetPassword,
                    child: const Text(
                      'Forgot Password?',
                      style: TextStyle(color: gold),
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              if (message.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: gold),
                  ),
                ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(16),
                  ),
                  onPressed: loading ? null : submit,
                  child: loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          isRegister ? 'SIGN UP' : 'LOGIN',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 15),

              Row(
                children: const [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      'OR',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                  Expanded(child: Divider(color: Colors.white24)),
                ],
              ),

              const SizedBox(height: 15),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: loading ? null : googleLogin,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                    padding: const EdgeInsets.all(14),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              TextButton(
                onPressed: loading
                    ? null
                    : () {
                        setState(() {
                          isRegister = !isRegister;
                          message = '';
                        });
                      },
                child: Text(
                  isRegister
                      ? 'Already have an account? Login'
                      : "Don't have an account? Sign Up",
                  style: const TextStyle(color: gold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------
// HOME
// --------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selected = 0;

  final pages = const [
    DiscoverScreen(),
    FriendsScreen(),
    PremiumScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.forum_rounded, color: gold),
            SizedBox(width: 9),
            Text(
              'STRANGER CONNECT',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 15,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _showInfo(context),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ],
      ),
      body: pages[selected],
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF111111),
        indicatorColor: gold.withOpacity(.16),
        selectedIndex: selected,
        onDestinationSelected: (i) => setState(() => selected = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Friends',
          ),
          NavigationDestination(
            icon: Icon(Icons.workspace_premium_outlined),
            selectedIcon: Icon(Icons.workspace_premium),
            label: 'Premium',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Notifications'),
        content: const Text('You are all caught up.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// DISCOVER
// --------------------------------------------------

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              colors: [Color(0xFF292015), Color(0xFF111111)],
            ),
            border: Border.all(color: gold.withOpacity(.45)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'YOUR NEXT\nCONVERSATION',
                style: TextStyle(
                  color: gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 26,
                ),
              ),
              SizedBox(height: 10),
              Text(
                'Meet someone new. Stay anonymous. Keep it respectful.',
                style: TextStyle(color: Colors.white70),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Icon(Icons.shield_moon_outlined, color: gold, size: 18),
                  SizedBox(width: 7),
                  Text(
                    'Private by design',
                    style: TextStyle(color: gold),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'START CONNECTING',
          style: TextStyle(color: gold, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _ActionTile(
          icon: Icons.shuffle_rounded,
          title: 'Find Stranger',
          subtitle: 'Get matched for a private chat',
          onTap: () => _comingSoon(context),
        ),
        _ActionTile(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Chat with Friends',
          subtitle: 'Connect using a private invite',
          onTap: () => _comingSoon(context),
        ),
        const SizedBox(height: 20),
        const Text(
          'YOUR EXPERIENCE',
          style: TextStyle(color: gold, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Chats',
                value: '0',
                icon: Icons.chat_bubble_outline,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Friends',
                value: '0',
                icon: Icons.people_outline,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: _StatCard(
                label: 'Rating',
                value: '—',
                icon: Icons.star_outline,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chat backend is the next development step.'),
      ),
    );
  }
}

// --------------------------------------------------
// FRIENDS
// --------------------------------------------------

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) => const _EmptyState(
        icon: Icons.people_alt_outlined,
        title: 'Your circle starts here',
        subtitle: 'Friends you connect with will appear here.',
      );
}

// --------------------------------------------------
// PREMIUM
// --------------------------------------------------

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.workspace_premium_rounded,
            color: gold,
            size: 58,
          ),
          const SizedBox(height: 12),
          const Text(
            'GO PREMIUM',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: gold,
              fontSize: 27,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Unlock more ways to connect.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const _Feature(text: 'Gender preference filters'),
          const _Feature(text: 'Premium profile badge'),
          const _Feature(text: 'Priority matching options'),
          const _Feature(text: 'More profile customisation'),
        ],
      );
}

// --------------------------------------------------
// PROFILE
// --------------------------------------------------

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();

        final name = data?['name']?.toString() ??
            user.displayName ??
            'New Member';

        final bio = data?['bio']?.toString() ?? '';

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 15),
            CircleAvatar(
              radius: 48,
              backgroundColor: const Color(0xFF302719),
              child: const Icon(
                Icons.person,
                size: 48,
                color: gold,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              user.email ?? 'Google Account',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 8),
            Text(
              bio.isEmpty ? 'Add a short bio about yourself.' : bio,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 25),

            _ActionTile(
              icon: Icons.edit,
              title: 'Edit Profile',
              subtitle: 'Change your name and bio',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(
                      currentName: name,
                      currentBio: bio,
                    ),
                  ),
                );
              },
            ),

            _ActionTile(
              icon: Icons.share_rounded,
              title: 'Owner Socials',
              subtitle: 'Instagram, Telegram and YouTube',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerSocialsScreen(),
                ),
              ),
            ),

            _ActionTile(
              icon: Icons.support_agent_rounded,
              title: 'Customer Care',
              subtitle: 'Contact official Telegram support',
              onTap: () => _openExternal(
                context,
                'https://t.me/ujjwal_jaat01',
              ),
            ),

            _ActionTile(
              icon: Icons.admin_panel_settings_rounded,
              title: 'Owner Admin Panel',
              subtitle: 'Restricted owner controls',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AdminAccessScreen(),
                ),
              ),
            ),

            const SizedBox(height: 15),

            _ActionTile(
              icon: Icons.logout,
              title: 'Logout',
              subtitle: 'Sign out of your account',
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                await GoogleSignIn().signOut();
              },
            ),
          ],
        );
      },
    );
  }
}

// --------------------------------------------------
// EDIT PROFILE
// --------------------------------------------------

class EditProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentBio;

  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentBio,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController bioController;

  bool loading = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    bioController = TextEditingController(text: widget.currentBio);
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final bio = bioController.text.trim();

    if (name.isEmpty) {
      setState(() => message = 'Name cannot be empty.');
      return;
    }

    if (name.length > 40 || bio.length > 160) {
      setState(() => message = 'Name or bio is too long.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final user = FirebaseAuth.instance.currentUser!;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'name': name,
        'bio': bio,
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        message = 'Could not update profile. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EDIT PROFILE')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const CircleAvatar(
            radius: 42,
            backgroundColor: Color(0xFF302719),
            child: Icon(Icons.person, color: gold, size: 42),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: nameController,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Your Name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: bioController,
            maxLength: 160,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Your Bio',
              hintText: 'Write something about yourself...',
              border: OutlineInputBorder(),
            ),
          ),
          if (message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                message,
                style: const TextStyle(color: gold),
              ),
            ),
          ElevatedButton(
            onPressed: loading ? null : saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(15),
            ),
            child: loading
                ? const CircularProgressIndicator(color: Colors.black)
                : const Text('SAVE PROFILE'),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------
// EXTERNAL LINKS
// --------------------------------------------------

Future<void> _openExternal(
  BuildContext context,
  String value,
) async {
  final uri = Uri.parse(value);

  if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      ) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this link.')),
    );
  }
}

// --------------------------------------------------
// OWNER SOCIALS
// --------------------------------------------------

class OwnerSocialsScreen extends StatelessWidget {
  const OwnerSocialsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OWNER SOCIALS')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _ActionTile(
              icon: Icons.camera_alt,
              title: 'Instagram',
              subtitle: '@ud_dramas',
              onTap: () => _openExternal(
                context,
                'https://www.instagram.com/ud_dramas?srtk=MWszOXFhNXplZHYxcA==',
              ),
            ),
            _ActionTile(
              icon: Icons.send,
              title: 'Telegram',
              subtitle: '@ujjwalmoder',
              onTap: () => _openExternal(
                context,
                'https://t.me/ujjwalmoder',
              ),
            ),
            _ActionTile(
              icon: Icons.play_circle_fill,
              title: 'YouTube',
              subtitle: '@Datingguru01',
              onTap: () => _openExternal(
                context,
                'https://www.youtube.com/@Datingguru01',
              ),
            ),
            _ActionTile(
              icon: Icons.support_agent,
              title: 'Telegram Support',
              subtitle: '@ujjwal_jaat01',
              onTap: () => _openExternal(
                context,
                'https://t.me/ujjwal_jaat01',
              ),
            ),
          ],
        ),
      );
}

// --------------------------------------------------
// OWNER ADMIN LOGIN
// --------------------------------------------------

class AdminAccessScreen extends StatefulWidget {
  const AdminAccessScreen({super.key});

  @override
  State<AdminAccessScreen> createState() =>
      _AdminAccessScreenState();
}

class _AdminAccessScreenState extends State<AdminAccessScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool isRegister = false;
  bool loading = false;
  String message = '';

  Future<void> submit() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.length < 6) {
      setState(() {
        message = 'Enter a valid email and password (minimum 6 characters).';
      });
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      UserCredential credential;

      if (isRegister) {
        credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = credential.user!;

      final adminDoc = await FirebaseFirestore.instance
          .collection('admins')
          .doc(user.uid)
          .get();

      if (!mounted) return;

      if (adminDoc.exists &&
          adminDoc.data()?['role'] == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const AdminDashboardScreen(),
          ),
        );
      } else {
        setState(() {
          message = isRegister
              ? 'Account created. Owner approval is still required.'
              : 'This account is not approved as an admin.';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        message = e.message ?? 'Authentication failed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        message = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('OWNER ADMIN LOGIN')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.admin_panel_settings,
                  color: gold,
                  size: 68,
                ),
                const SizedBox(height: 18),
                Text(
                  isRegister ? 'CREATE OWNER ACCOUNT' : 'OWNER LOGIN',
                  style: const TextStyle(
                    color: gold,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Admin Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 18),
                if (message.isNotEmpty)
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: gold),
                  ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(15),
                    ),
                    onPressed: loading ? null : submit,
                    child: loading
                        ? const CircularProgressIndicator(
                            color: Colors.black,
                          )
                        : Text(isRegister ? 'CREATE ACCOUNT' : 'LOGIN'),
                  ),
                ),
                TextButton(
                  onPressed: loading
                      ? null
                      : () => setState(() {
                            isRegister = !isRegister;
                            message = '';
                          }),
                  child: Text(
                    isRegister
                        ? 'Already registered? Login'
                        : 'First time? Create account',
                    style: const TextStyle(color: gold),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// --------------------------------------------------
// ADMIN DASHBOARD
// --------------------------------------------------

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('OWNER DASHBOARD'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await FirebaseAuth.instance.signOut();

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(
              Icons.verified_user,
              color: gold,
              size: 65,
            ),
            const SizedBox(height: 15),
            const Text(
              'Welcome, Owner Admin',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: gold,
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 25),
            _ActionTile(
              icon: Icons.manage_accounts,
              title: 'User Management',
              subtitle: 'View, ban and unban users',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserManagementScreen(),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: Icons.workspace_premium,
              title: 'Premium Management',
              subtitle: 'Activate or deactivate user Premium',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UserManagementScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 15),
            const _Feature(text: 'Reports and broadcasts'),
            const _Feature(text: 'App analytics'),
            const SizedBox(height: 15),
            const Text(
              'User Management and Premium controls are connected '
              'to the Firestore users collection.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        ),
      );
}

// --------------------------------------------------
// USER MANAGEMENT
// --------------------------------------------------

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  Future<void> _changeUserStatus(
    BuildContext context,
    String userId,
    String field,
    bool value,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set(
        {field: value},
        SetOptions(merge: true),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              field == 'isBanned'
                  ? (value ? 'User banned.' : 'User unbanned.')
                  : (value
                      ? 'Premium activated.'
                      : 'Premium deactivated.'),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('USER MANAGEMENT')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load users',
              subtitle:
                  'Check Firestore security rules and internet connection.',
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: gold),
            );
          }

          final documents = snapshot.data?.docs ?? [];

          if (documents.isEmpty) {
            return const _EmptyState(
              icon: Icons.people_outline,
              title: 'No users yet',
              subtitle: 'Registered app users will appear here.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final document = documents[index];
              final data = document.data();

              final email = data['email']?.toString() ?? 'No email';
              final name = data['name']?.toString() ?? 'User';
              final isBanned = data['isBanned'] == true;
              final isPremium = data['isPremium'] == true;

              return Card(
                color: panel,
                margin: const EdgeInsets.only(bottom: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: gold.withOpacity(.18)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            backgroundColor: Color(0xFF302719),
                            child: Icon(Icons.person, color: gold),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  email,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'UID: ${document.id}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                      ),
                      const Divider(color: Colors.white12),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: gold,
                        title: const Text('Ban User'),
                        subtitle: Text(
                          isBanned ? 'User is banned' : 'User is active',
                        ),
                        value: isBanned,
                        onChanged: (value) {
                          _changeUserStatus(
                            context,
                            document.id,
                            'isBanned',
                            value,
                          );
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: gold,
                        title: const Text('Premium Membership'),
                        subtitle: Text(
                          isPremium
                              ? 'Premium is active'
                              : 'Premium is inactive',
                        ),
                        value: isPremium,
                        onChanged: (value) {
                          _changeUserStatus(
                            context,
                            document.id,
                            'isPremium',
                            value,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --------------------------------------------------
// REUSABLE ACTION TILE
// --------------------------------------------------

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        color: panel,
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: gold, size: 27),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          trailing: const Icon(Icons.chevron_right, color: gold),
        ),
      );
}

// --------------------------------------------------
// STAT CARD
// --------------------------------------------------

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 8,
        ),
        decoration: BoxDecoration(
          color: panel,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: gold.withOpacity(.18)),
        ),
        child: Column(
          children: [
            Icon(icon, color: gold),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      );
}

// --------------------------------------------------
// FEATURE ROW
// --------------------------------------------------

class _Feature extends StatelessWidget {
  final String text;

  const _Feature({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: gold, size: 19),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
          ],
        ),
      );
}

// --------------------------------------------------
// EMPTY STATE
// --------------------------------------------------

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: gold, size: 64),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ],
          ),
        ),
      );
}
