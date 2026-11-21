
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';

const gold = Color(0xFFB44CFF);
const bg = Color(0xFF050008);
const panel = Color(0xFF160B20);

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;

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

// PREMIUM

bool isPremiumActive(Map<String, dynamic>? data) {
  if (data == null || data['isPremium'] != true) return false;
  final expiry = data['premiumExpiresAt'];
  if (expiry == null) return true;

  DateTime? date;
  if (expiry is Timestamp) date = expiry.toDate();
  if (expiry is DateTime) date = expiry;

  return date != null && DateTime.now().isBefore(date);
}

String premiumRemaining(Map<String, dynamic>? data) {
  final expiry = data?['premiumExpiresAt'];
  if (expiry == null) return 'Active';
  if (expiry is! Timestamp) return 'Inactive';

  final difference = expiry.toDate().difference(DateTime.now());
  if (difference.isNegative || difference.inSeconds <= 0) {
    return 'Expired';
  }
  if (difference.inDays >= 1) {
    return '${difference.inDays} day(s) remaining';
  }
  if (difference.inHours >= 1) {
    return '${difference.inHours} hour(s) remaining';
  }
  return '${difference.inMinutes} minute(s) remaining';
}

bool genderMatches(String preference, String gender) {
  return preference == 'Both' || preference == gender;
}

// USER PROFILE

Future<void> saveUserProfile(User user, {String? name}) async {
  final ref = db.collection('users').doc(user.uid);
  final document = await ref.get();

  if (!document.exists) {
    await ref.set({
      'name': name?.trim().isNotEmpty == true
          ? name!.trim()
          : (user.displayName ?? 'New Member'),
      'email': user.email ?? '',
      'bio': '',
      'createdAt': FieldValue.serverTimestamp(),
    });
  } else {
    final updates = <String, dynamic>{};
    if (user.email != null) updates['email'] = user.email;
    if (name != null && name.trim().isNotEmpty) {
      updates['name'] = name.trim();
    }
    if (updates.isNotEmpty) {
      await ref.set(updates, SetOptions(merge: true));
    }
  }
}

// AUTH GATE

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: auth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: gold)),
          );
        }
        if (snapshot.data == null) return const AuthScreen();
        return const HomeScreen();
      },
    );
  }
}

// LOGIN / SIGNUP

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
      UserCredential result;
      if (isRegister) {
        result = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await saveUserProfile(result.user!, name: name);
      } else {
        result = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        await saveUserProfile(result.user!);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = e.message ?? 'Login failed.');
    } catch (_) {
      if (mounted) setState(() => message = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => loading = false);
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

      final result = await auth.signInWithCredential(credential);
      await saveUserProfile(result.user!);
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? 'Google login failed.');
      }
    } catch (_) {
      if (mounted) setState(() => message = 'Google login failed.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => message = 'Enter your email address first.');
      return;
    }
    try {
      await auth.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => message = 'Password reset email sent.');
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => message = e.message ?? 'Could not send email.');
      }
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
              const Icon(Icons.forum_rounded, color: gold, size: 65),
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
                      setState(() => obscurePassword = !obscurePassword);
                    },
                    icon: Icon(
                      obscurePassword ? Icons.visibility : Icons.visibility_off,
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
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text(isRegister ? 'SIGN UP' : 'LOGIN'),
                ),
              ),
              const SizedBox(height: 15),
              const Row(
                children: [
                  Expanded(child: Divider(color: Colors.white24)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('OR', style: TextStyle(color: Colors.white54)),
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
                    : () => setState(() {
                          isRegister = !isRegister;
                          message = '';
                        }),
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

// HOME

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
            onPressed: () => showDialog(
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
            ),
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
}

// DISCOVER

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  Future<void> _find(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FindStrangerScreen()),
    );
  }

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
                  Text('Private by design', style: TextStyle(color: gold)),
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
          onTap: () => _find(context),
        ),
        _ActionTile(
          icon: Icons.person_add_alt_1_rounded,
          title: 'Chat with Friends',
          subtitle: 'Invite friends and chat privately',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FriendsScreen()),
          ),
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
}

// STRANGER MATCHING

class FindStrangerScreen extends StatefulWidget {
  const FindStrangerScreen({super.key});

  @override
  State<FindStrangerScreen> createState() => _FindStrangerScreenState();
}

class _FindStrangerScreenState extends State<FindStrangerScreen> {
  final user = auth.currentUser!;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? ownSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? queueSubscription;

  bool searching = true;
  bool openingChat = false;
  bool working = false;
  bool closed = false;
  String status = 'Finding someone for you...';
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  Future<void> _startSearch() async {
    if (closed || !mounted) return;

    setState(() {
      searching = true;
      openingChat = false;
      errorMessage = null;
      status = 'Finding someone for you...';
    });

    try {
      final profileDoc = await db.collection('users').doc(user.uid).get();
      final profile = profileDoc.data();

      if (profile == null) {
        throw Exception('Please complete your profile first.');
      }
      if (profile['isBanned'] == true) {
        throw Exception('Your account is restricted.');
      }

      final gender = profile['gender']?.toString() ?? '';
      if (gender != 'Male' && gender != 'Female') {
        throw Exception('Please select your gender in Edit Profile first.');
      }

      final premium = isPremiumActive(profile);
      final preference = premium
          ? (profile['preferredGender']?.toString() ?? 'Both')
          : 'Both';

      final blockedSnapshot = await db
          .collection('users')
          .doc(user.uid)
          .collection('blocked')
          .get();

      final blocked = blockedSnapshot.docs.map((d) => d.id).toList();
      final queueRef = db.collection('matchQueue').doc(user.uid);

      await queueRef.set({
        'uid': user.uid,
        'gender': gender,
        'preferredGender': preference,
        'blockedUids': blocked,
        'status': 'waiting',
        'chatId': null,
        'partnerUid': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted || closed) return;

      ownSubscription?.cancel();
      queueSubscription?.cancel();

      ownSubscription = queueRef.snapshots().listen((snapshot) {
        final data = snapshot.data();
        if (data == null || !mounted || closed) return;

        if (data['status'] == 'matched') {
          final chatId = data['chatId']?.toString();
          final partnerUid = data['partnerUid']?.toString();
          if (chatId != null && partnerUid != null) {
            _openChat(chatId, partnerUid);
          }
        }
      });

      queueSubscription = db
          .collection('matchQueue')
          .where('status', isEqualTo: 'waiting')
          .snapshots()
          .listen((snapshot) {
        _tryMatch(snapshot.docs);
      });

      setState(() => status = 'Searching for an available stranger...');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        searching = false;
        errorMessage = e.toString().replaceFirst('Exception: ', '');
        status = 'Unable to start matching.';
      });
    }
  }

  Future<void> _tryMatch(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> candidates,
  ) async {
    if (working || openingChat || closed || !mounted) return;
    working = true;

    try {
      final myQueueRef = db.collection('matchQueue').doc(user.uid);
      final mySnapshot = await myQueueRef.get();
      final myData = mySnapshot.data();

      if (myData == null || myData['status'] != 'waiting') return;

      final myGender = myData['gender']?.toString() ?? '';
      final myPreference = myData['preferredGender']?.toString() ?? 'Both';
      final myBlocked = List<String>.from(myData['blockedUids'] ?? const []);

      for (final candidate in candidates) {
        if (!mounted || closed || openingChat) return;

        final partnerUid = candidate.id;
        if (partnerUid == user.uid || myBlocked.contains(partnerUid)) {
          continue;
        }

        final candidateData = candidate.data();
        final partnerGender = candidateData['gender']?.toString() ?? '';
        final partnerPreference =
            candidateData['preferredGender']?.toString() ?? 'Both';
        final partnerBlocked =
            List<String>.from(candidateData['blockedUids'] ?? const []);

        if (partnerBlocked.contains(user.uid)) continue;
        if (!genderMatches(myPreference, partnerGender)) continue;
        if (!genderMatches(partnerPreference, myGender)) continue;

        final partnerRef = db.collection('matchQueue').doc(partnerUid);
        final chatRef = db.collection('chats').doc();

        final matched = await db.runTransaction<bool>((transaction) async {
          final myCurrent = await transaction.get(myQueueRef);
          final partnerCurrent = await transaction.get(partnerRef);

          if (!myCurrent.exists || !partnerCurrent.exists) return false;

          final myCurrentData = myCurrent.data()!;
          final partnerCurrentData = partnerCurrent.data()!;

          if (myCurrentData['status'] != 'waiting' ||
              partnerCurrentData['status'] != 'waiting') {
            return false;
          }
          if (partnerCurrentData['uid'] != partnerUid) return false;

          transaction.set(chatRef, {
            'participants': [user.uid, partnerUid],
            'active': true,
            'createdAt': FieldValue.serverTimestamp(),
            'lastMessage': '',
            'lastMessageAt': FieldValue.serverTimestamp(),
          });

          transaction.update(myQueueRef, {
            'status': 'matched',
            'chatId': chatRef.id,
            'partnerUid': partnerUid,
          });

          transaction.update(partnerRef, {
            'status': 'matched',
            'chatId': chatRef.id,
            'partnerUid': user.uid,
          });

          return true;
        });

        if (matched) return;
      }
    } catch (e) {
      debugPrint('Matching error: $e');
    } finally {
      working = false;
    }
  }

  Future<void> _openChat(String chatId, String partnerUid) async {
    if (openingChat || closed || !mounted) return;

    openingChat = true;
    searching = false;
    await queueSubscription?.cancel();
    await ownSubscription?.cancel();

    if (!mounted || closed) return;

    final next = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          chatId: chatId,
          partnerUid: partnerUid,
        ),
      ),
    );

    if (!mounted || closed) return;
    openingChat = false;

    if (next == true) {
      await _startSearch();
    } else {
      await _leaveSearch();
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _leaveSearch() async {
    closed = true;
    await queueSubscription?.cancel();
    await ownSubscription?.cancel();
    try {
      await db.collection('matchQueue').doc(user.uid).delete();
    } catch (_) {}
  }

  @override
  void dispose() {
    closed = true;
    queueSubscription?.cancel();
    ownSubscription?.cancel();
    db.collection('matchQueue').doc(user.uid).delete().catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FIND STRANGER'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await _leaveSearch();
            if (mounted) Navigator.pop(context);
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (searching && errorMessage == null) ...[
                const Icon(Icons.travel_explore, color: gold, size: 75),
                const SizedBox(height: 25),
                const CircularProgressIndicator(color: gold),
              ] else
                Icon(
                  errorMessage == null ? Icons.chat : Icons.error_outline,
                  color: gold,
                  size: 75,
                ),
              const SizedBox(height: 25),
              Text(
                errorMessage == null ? status : errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: gold,
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Please wait while we look for someone available.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 30),
              if (errorMessage != null)
                ElevatedButton(
                  onPressed: _startSearch,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                  ),
                  child: const Text('TRY AGAIN'),
                ),
              OutlinedButton.icon(
                onPressed: () async {
                  await _leaveSearch();
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                label: const Text('CANCEL SEARCH'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: gold,
                  side: const BorderSide(color: gold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// STRANGER CHAT

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String partnerUid;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.partnerUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  bool sending = false;
  bool leaving = false;
  bool partnerLeft = false;
  String partnerName = 'Stranger';

  DocumentReference<Map<String, dynamic>> get chatRef =>
      db.collection('chats').doc(widget.chatId);

  CollectionReference<Map<String, dynamic>> get messagesRef =>
      chatRef.collection('messages');

  @override
  void initState() {
    super.initState();
    _loadPartner();
  }

  Future<void> _loadPartner() async {
    try {
      final doc = await db.collection('users').doc(widget.partnerUid).get();
      if (!mounted) return;
      setState(() {
        partnerName = doc.data()?['name']?.toString() ?? 'Stranger';
      });
    } catch (_) {}
  }

  Future<void> _sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || sending || leaving) return;

    if (text.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message is too long.')),
      );
      return;
    }

    setState(() => sending = true);
    messageController.clear();

    try {
      await messagesRef.add({
        'senderId': auth.currentUser!.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await chatRef.update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      if (mounted) {
        messageController.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be sent.')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _closeChat({required bool next}) async {
    if (leaving) return;
    leaving = true;

    try {
      await chatRef.update({
        'active': false,
        'endedBy': auth.currentUser!.uid,
        'endedAt': FieldValue.serverTimestamp(),
      });
      await db.collection('matchQueue').doc(auth.currentUser!.uid).delete();
    } catch (e) {
      debugPrint('Chat close error: $e');
    }

    if (mounted) Navigator.pop(context, next);
  }

  Future<void> _reportUser() async {
    String reason = 'Inappropriate behaviour';

    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Report Stranger'),
        content: DropdownButtonFormField<String>(
          value: reason,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Reason',
          ),
          items: const [
            DropdownMenuItem(
              value: 'Inappropriate behaviour',
              child: Text('Inappropriate behaviour'),
            ),
            DropdownMenuItem(value: 'Harassment', child: Text('Harassment')),
            DropdownMenuItem(value: 'Spam or scam', child: Text('Spam or scam')),
            DropdownMenuItem(value: 'Other', child: Text('Other')),
          ],
          onChanged: (value) {
            if (value != null) reason = value;
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, reason),
            child: const Text('REPORT'),
          ),
        ],
      ),
    );

    if (selected == null) return;

    try {
      await db.collection('reports').add({
        'reporterId': auth.currentUser!.uid,
        'reportedUid': widget.partnerUid,
        'chatId': widget.chatId,
        'reason': selected,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not submit report.')),
        );
      }
    }
  }

  Future<void> _blockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Block this user?'),
        content: const Text(
          'You will not be matched with this user again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('BLOCK'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await db
          .collection('users')
          .doc(auth.currentUser!.uid)
          .collection('blocked')
          .doc(widget.partnerUid)
          .set({'blockedAt': FieldValue.serverTimestamp()});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked.')),
        );
      }
      await _closeChat(next: false);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not block this user.')),
        );
      }
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !leaving) _closeChat(next: false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partnerName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Text(
                'Anonymous chat',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'report') _reportUser();
                if (value == 'block') _blockUser();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'report', child: Text('Report User')),
                PopupMenuItem(value: 'block', child: Text('Block User')),
              ],
            ),
          ],
        ),
        body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: chatRef.snapshots(),
          builder: (context, chatSnapshot) {
            final chatData = chatSnapshot.data?.data();
            if (chatData != null &&
                chatData['active'] == false &&
                !leaving) {
              partnerLeft = true;
            }

            return Column(
              children: [
                if (partnerLeft)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: const Color(0xFF302719),
                    child: const Text(
                      'The other person has left this chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: gold),
                    ),
                  ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: messagesRef
                        .orderBy('createdAt', descending: false)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Could not load messages.'),
                        );
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: gold),
                        );
                      }

                      final messages = snapshot.data?.docs ?? [];
                      if (messages.isEmpty) {
                        return const Center(
                          child: Text(
                            'Say hello! Start your conversation.',
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.all(15),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final data = messages[index].data();
                          final mine =
                              data['senderId'] == auth.currentUser!.uid;

                          return Align(
                            alignment: mine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * .78,
                              ),
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: mine
                                    ? const Color(0xFF594521)
                                    : panel,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: mine
                                      ? gold.withOpacity(.5)
                                      : Colors.white12,
                                ),
                              ),
                              child: Text(data['text']?.toString() ?? ''),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 15),
                  decoration: const BoxDecoration(
                    color: panel,
                    border: Border(top: BorderSide(color: Colors.white12)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: messageController,
                              enabled: !partnerLeft && !leaving,
                              minLines: 1,
                              maxLines: 4,
                              decoration: InputDecoration(
                                hintText: 'Type a message...',
                                filled: true,
                                fillColor: bg,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(25),
                                  borderSide: BorderSide.none,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed:
                                sending || partnerLeft ? null : _sendMessage,
                            icon: const Icon(Icons.send, color: gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: leaving
                                  ? null
                                  : () => _closeChat(next: true),
                              icon: const Icon(Icons.skip_next),
                              label: const Text('NEXT'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: gold,
                                side: const BorderSide(color: gold),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: leaving
                                  ? null
                                  : () => _closeChat(next: false),
                              icon: const Icon(Icons.stop),
                              label: const Text('STOP'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: gold,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// FRIENDS AND INVITES

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final codeController = TextEditingController();
  bool loading = false;
  String message = '';

  String get myUid => auth.currentUser!.uid;

  Future<void> createInvite() async {
    if (loading) return;

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final profile = await db.collection('users').doc(myUid).get();
      final name = profile.data()?['name']?.toString() ?? 'Member';
      final inviteRef = db.collection('friendInvites').doc();

      await inviteRef.set({
        'inviterUid': myUid,
        'inviterName': name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await Clipboard.setData(ClipboardData(text: inviteRef.id));

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: panel,
          title: const Text('Friend Invite Created'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Share this invite code with your friend.'),
              const SizedBox(height: 15),
              SelectableText(
                inviteRef.id,
                style: const TextStyle(
                  color: gold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Code copied to clipboard!',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('DONE'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) setState(() => message = 'Could not create invite. Try again.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> joinWithCode() async {
    final code = codeController.text.trim();

    if (code.isEmpty || loading) {
      setState(() => message = 'Please enter an invite code.');
      return;
    }

    setState(() {
      loading = true;
      message = '';
    });

    try {
      final inviteRef = db.collection('friendInvites').doc(code);
      final inviteSnapshot = await inviteRef.get();

      if (!inviteSnapshot.exists) {
        throw Exception('Invalid invite code.');
      }

      final inviteData = inviteSnapshot.data()!;
      final inviterUid = inviteData['inviterUid']?.toString() ?? '';

      if (inviteData['status'] != 'pending') {
        throw Exception('This invite has already been used.');
      }
      if (inviterUid == myUid) {
        throw Exception('You cannot use your own invite code.');
      }

      final myProfile = await db.collection('users').doc(myUid).get();
      final myName = myProfile.data()?['name']?.toString() ?? 'Member';
      final inviterName = inviteData['inviterName']?.toString() ?? 'Friend';

      // Deterministic ID makes the same two users share one chat document.
      final friendshipId = '${inviterUid}_$myUid';
      final friendshipRef = db.collection('friendships').doc(friendshipId);
      final chatRef = db.collection('chats').doc(friendshipId);

      await db.runTransaction((transaction) async {
        final currentInvite = await transaction.get(inviteRef);
        final existingFriendship = await transaction.get(friendshipRef);
        final existingChat = await transaction.get(chatRef);

        if (!currentInvite.exists ||
            currentInvite.data()?['status'] != 'pending') {
          throw Exception('Invite is no longer available.');
        }
        if (existingFriendship.exists || existingChat.exists) {
          throw Exception('This friendship already exists.');
        }

        transaction.update(inviteRef, {
          'status': 'accepted',
          'acceptedBy': myUid,
          'acceptedName': myName,
          'acceptedAt': FieldValue.serverTimestamp(),
          'friendshipId': friendshipId,
        });

        transaction.set(friendshipRef, {
          'participants': [inviterUid, myUid],
          'uidA': inviterUid,
          'uidB': myUid,
          'nameA': inviterName,
          'nameB': myName,
          'inviteId': code,
          'createdAt': FieldValue.serverTimestamp(),
        });

        transaction.set(chatRef, {
          'type': 'friend',
          'inviteId': code,
          'participants': [inviterUid, myUid],
          'active': true,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
        });
      });

      codeController.clear();
      if (mounted) setState(() => message = 'Friend connected successfully!');
    } catch (e) {
      if (mounted) {
        setState(() {
          message = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CHAT WITH FRIENDS')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: gold.withOpacity(.35)),
            ),
            child: Column(
              children: [
                const Icon(Icons.people_alt, color: gold, size: 48),
                const SizedBox(height: 12),
                const Text(
                  'YOUR FRIEND CIRCLE',
                  style: TextStyle(
                    color: gold,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Invite someone and enjoy private conversations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: loading ? null : createInvite,
                    icon: const Icon(Icons.person_add),
                    label: const Text('CREATE INVITE CODE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.all(14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'JOIN WITH INVITE CODE',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: codeController,
            decoration: const InputDecoration(
              hintText: 'Enter your friend invite code',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_key),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: loading ? null : joinWithCode,
              style: OutlinedButton.styleFrom(
                foregroundColor: gold,
                side: const BorderSide(color: gold),
                padding: const EdgeInsets.all(14),
              ),
              child: loading
                  ? const CircularProgressIndicator(color: gold)
                  : const Text('JOIN FRIEND'),
            ),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: gold),
            ),
          ],
          const SizedBox(height: 25),
          const Text(
            'MY FRIENDS',
            style: TextStyle(
              color: gold,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 10),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('friendships')
                .where('participants', arrayContains: myUid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Could not load friends.',
                  style: TextStyle(color: Colors.white54),
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: gold),
                );
              }

              final friends = snapshot.data?.docs ?? [];
              if (friends.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(20),
                  child: _EmptyState(
                    icon: Icons.people_outline,
                    title: 'No friends yet',
                    subtitle: 'Create an invite code to connect with someone.',
                  ),
                );
              }

              return Column(
                children: friends.map((friend) {
                  final data = friend.data();
                  final participants =
                      List<String>.from(data['participants'] ?? []);
                  final otherUid = participants.firstWhere(
                    (uid) => uid != myUid,
                    orElse: () => '',
                  );

                  if (otherUid.isEmpty) return const SizedBox.shrink();

                  return FutureBuilder<
                      DocumentSnapshot<Map<String, dynamic>>>(
                    future: db.collection('users').doc(otherUid).get(),
                    builder: (context, userSnapshot) {
                      final friendName = userSnapshot.data?.data()?['name']
                              ?.toString() ??
                          'Friend';

                      return Card(
                        color: panel,
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFF302719),
                            child: Icon(Icons.person, color: gold),
                          ),
                          title: Text(
                            friendName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: const Text(
                            'Private friend chat',
                            style: TextStyle(color: Colors.white54),
                          ),
                          trailing: const Icon(
                            Icons.chat_bubble_outline,
                            color: gold,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FriendChatScreen(
                                  chatId: friend.id,
                                  partnerUid: otherUid,
                                  partnerName: friendName,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// PERMANENT FRIEND CHAT

class FriendChatScreen extends StatefulWidget {
  final String chatId;
  final String partnerUid;
  final String partnerName;

  const FriendChatScreen({
    super.key,
    required this.chatId,
    required this.partnerUid,
    required this.partnerName,
  });

  @override
  State<FriendChatScreen> createState() => _FriendChatScreenState();
}

class _FriendChatScreenState extends State<FriendChatScreen> {
  final messageController = TextEditingController();
  bool sending = false;

  DocumentReference<Map<String, dynamic>> get chatRef =>
      db.collection('chats').doc(widget.chatId);

  CollectionReference<Map<String, dynamic>> get messagesRef =>
      chatRef.collection('messages');

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty || sending) return;

    if (text.length > 1000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message is too long.')),
      );
      return;
    }

    setState(() => sending = true);
    messageController.clear();

    try {
      await messagesRef.add({
        'senderId': auth.currentUser!.uid,
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await chatRef.update({
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      messageController.text = text;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message could not be sent.')),
        );
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.partnerName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Text(
              'Friend • Private chat',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: messagesRef.orderBy('createdAt').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('Could not load messages.'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                final messages = snapshot.data?.docs ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say hello to your friend!',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final data = messages[index].data();
                    final mine = data['senderId'] == auth.currentUser!.uid;

                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * .78,
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: mine
                              ? const Color(0xFF594521)
                              : panel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: mine
                                ? gold.withOpacity(.5)
                                : Colors.white12,
                          ),
                        ),
                        child: Text(data['text']?.toString() ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 15),
            decoration: const BoxDecoration(
              color: panel,
              border: Border(top: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      filled: true,
                      fillColor: bg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onSubmitted: (_) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: sending ? null : sendMessage,
                  icon: const Icon(Icons.send, color: gold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// PREMIUM AND GENDER FILTER

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  Future<void> savePreference(
    BuildContext context,
    String preference,
  ) async {
    final user = auth.currentUser!;
    try {
      await db.collection('users').doc(user.uid).set({
        'preferredGender': preference,
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gender preference saved.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save preference.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final premium = isPremiumActive(data);
        final preference = data?['preferredGender']?.toString() ?? 'Both';

        return ListView(
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
            const SizedBox(height: 20),
            Card(
              color: panel,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.workspace_premium, color: gold),
                        const SizedBox(width: 10),
                        Text(
                          premium ? 'PREMIUM ACTIVE' : 'FREE MEMBERSHIP',
                          style: const TextStyle(
                            color: gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      premium
                          ? premiumRemaining(data)
                          : 'Gender filters are available to Premium members.',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'GENDER PREFERENCE FILTER',
              style: TextStyle(color: gold, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: ['Male', 'Female', 'Both'].contains(preference)
                  ? preference
                  : 'Both',
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  premium ? Icons.people_alt_outlined : Icons.lock_outline,
                ),
                helperText: premium
                    ? 'Choose who you want to meet.'
                    : 'Upgrade to Premium to unlock this filter.',
              ),
              items: const [
                DropdownMenuItem(value: 'Male', child: Text('Male')),
                DropdownMenuItem(value: 'Female', child: Text('Female')),
                DropdownMenuItem(value: 'Both', child: Text('Both')),
              ],
              onChanged: premium
                  ? (value) {
                      if (value != null) savePreference(context, value);
                    }
                  : null,
            ),
            if (!premium) ...[
              const SizedBox(height: 12),
              const Text(
                'The gender filter is locked for free accounts.',
                style: TextStyle(color: Colors.white54),
              ),
            ],
            const SizedBox(height: 25),
            const _Feature(text: 'Gender preference filters'),
            const _Feature(text: 'Premium profile badge'),
            const _Feature(text: 'Priority matching options'),
            const _Feature(text: 'More profile customisation'),
          ],
        );
      },
    );
  }
}

// PROFILE

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final name =
            data?['name']?.toString() ?? user.displayName ?? 'New Member';
        final bio = data?['bio']?.toString() ?? '';
        final gender = data?['gender']?.toString() ?? '';
        final premium = isPremiumActive(data);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 15),
            const CircleAvatar(
              radius: 48,
              backgroundColor: Color(0xFF302719),
              child: Icon(Icons.person, size: 48, color: gold),
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
            if (gender.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                gender,
                textAlign: TextAlign.center,
                style: const TextStyle(color: gold),
              ),
            ],
            if (premium) ...[
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.workspace_premium, color: gold, size: 18),
                  SizedBox(width: 5),
                  Text(
                    'PREMIUM MEMBER',
                    style: TextStyle(color: gold, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
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
              subtitle: 'Change your name, gender and bio',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfileScreen(
                    currentName: name,
                    currentBio: bio,
                    currentGender: gender,
                  ),
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.share_rounded,
              title: 'Owner Socials',
              subtitle: 'Instagram, Telegram and YouTube',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OwnerSocialsScreen()),
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
                MaterialPageRoute(builder: (_) => const AdminAccessScreen()),
              ),
            ),
            const SizedBox(height: 15),
            _ActionTile(
              icon: Icons.logout,
              title: 'Logout',
              subtitle: 'Sign out of your account',
              onTap: () async {
                await auth.signOut();
                await GoogleSignIn().signOut();
              },
            ),
          ],
        );
      },
    );
  }
}

// EDIT PROFILE

class EditProfileScreen extends StatefulWidget {
  final String currentName;
  final String currentBio;
  final String currentGender;

  const EditProfileScreen({
    super.key,
    required this.currentName,
    required this.currentBio,
    required this.currentGender,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController bioController;

  String? gender;
  bool loading = false;
  String message = '';

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    bioController = TextEditingController(text: widget.currentBio);
    gender = widget.currentGender.isEmpty ? null : widget.currentGender;
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();
    final bio = bioController.text.trim();

    if (name.isEmpty) {
      setState(() => message = 'Name cannot be empty.');
      return;
    }
    if (gender == null) {
      setState(() => message = 'Please select your gender.');
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
      final user = auth.currentUser!;
      await db.collection('users').doc(user.uid).set({
        'name': name,
        'bio': bio,
        'gender': gender,
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully.')),
      );
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => message = 'Could not update profile. Please try again.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
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
          DropdownButtonFormField<String>(
            value: gender,
            decoration: const InputDecoration(
              labelText: 'Your Gender',
              prefixIcon: Icon(Icons.wc),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
            ],
            onChanged: (value) => setState(() => gender = value),
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
              child: Text(message, style: const TextStyle(color: gold)),
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

// EXTERNAL LINKS

Future<void> _openExternal(BuildContext context, String value) async {
  final uri = Uri.parse(value);
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open this link.')),
    );
  }
}

// OWNER SOCIALS

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
              onTap: () => _openExternal(context, 'https://t.me/ujjwalmoder'),
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

// ADMIN LOGIN

class AdminAccessScreen extends StatefulWidget {
  const AdminAccessScreen({super.key});

  @override
  State<AdminAccessScreen> createState() => _AdminAccessScreenState();
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
        credential = await auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        credential = await auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      }

      final user = credential.user!;
      final adminDoc = await db.collection('admins').doc(user.uid).get();

      if (!mounted) return;

      if (adminDoc.exists && adminDoc.data()?['role'] == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
        );
      } else {
        setState(() {
          message = isRegister
              ? 'Account created. Owner approval is still required.'
              : 'This account is not approved as an admin.';
        });
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => message = e.message ?? 'Login failed.');
    } catch (_) {
      if (mounted) setState(() => message = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => loading = false);
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
                        ? const CircularProgressIndicator(color: Colors.black)
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

// ADMIN DASHBOARD

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
                await auth.signOut();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.verified_user, color: gold, size: 65),
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
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserManagementScreen(),
                ),
              ),
            ),
            _ActionTile(
              icon: Icons.workspace_premium,
              title: 'Premium Management',
              subtitle: 'Give Premium for 1, 7 or 30 days',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const UserManagementScreen(),
                ),
              ),
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

// USER MANAGEMENT AND PREMIUM

class UserManagementScreen extends StatelessWidget {
  const UserManagementScreen({super.key});

  Future<void> _changeUserStatus(
    BuildContext context,
    String userId,
    String field,
    bool value,
  ) async {
    try {
      await db.collection('users').doc(userId).set(
        {field: value},
        SetOptions(merge: true),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              field == 'isBanned'
                  ? (value ? 'User banned.' : 'User unbanned.')
                  : (value ? 'Premium activated.' : 'Premium deactivated.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Action failed.')),
        );
      }
    }
  }

  Future<void> _setPremium(
    BuildContext context,
    String userId,
    int days,
  ) async {
    try {
      final expiry = DateTime.now().add(Duration(days: days));
      await db.collection('users').doc(userId).set({
        'isPremium': true,
        'premiumExpiresAt': Timestamp.fromDate(expiry),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Premium activated for $days day(s).')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not activate Premium.')),
        );
      }
    }
  }

  Future<void> _removePremium(
    BuildContext context,
    String userId,
  ) async {
    try {
      await db.collection('users').doc(userId).set({
        'isPremium': false,
        'premiumExpiresAt': FieldValue.delete(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Premium deactivated.')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not deactivate Premium.')),
        );
      }
    }
  }

  Future<void> _showPremiumOptions(
    BuildContext context,
    String userId,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: panel,
        title: const Text('Give Premium'),
        content: const Text('Select Premium duration.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _setPremium(context, userId, 1);
            },
            child: const Text('1 Day'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _setPremium(context, userId, 7);
            },
            child: const Text('7 Days'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _setPremium(context, userId, 30);
            },
            child: const Text('1 Month'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('USER MANAGEMENT')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _EmptyState(
              icon: Icons.error_outline,
              title: 'Could not load users',
              subtitle: 'Check Firestore rules and internet connection.',
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
              final premium = isPremiumActive(data);

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
                      const Divider(color: Colors.white12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.workspace_premium,
                          color: gold,
                        ),
                        title: const Text('Premium Membership'),
                        subtitle: Text(
                          premium
                              ? premiumRemaining(data)
                              : 'Premium inactive or expired',
                        ),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: gold),
                          onSelected: (value) {
                            if (value == 'give') {
                              _showPremiumOptions(context, document.id);
                            } else {
                              _removePremium(context, document.id);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'give',
                              child: Text('Give / Renew Premium'),
                            ),
                            PopupMenuItem(
                              value: 'remove',
                              child: Text('Deactivate Premium'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _showPremiumOptions(context, document.id),
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('GIVE PREMIUM'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: gold,
                            side: const BorderSide(color: gold),
                          ),
                        ),
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

// REUSABLE WIDGETS

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
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: gold),
        ),
      );
}

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
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
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
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ],
        ),
      );
}

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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    super.key,
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
