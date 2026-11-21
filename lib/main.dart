
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

const gold = Color(0xFFB44CFF);
const bg = Color(0xFF050008);
const panel = Color(0xFF160B20);

const supabaseUrl = 'https://cgimxrrxjeyamckxweta.supabase.co';
const supabaseKey = 'sb_publishable_0b8iCEOvOzpUuC-TtsKt7w_nSOFYIOZ';
const mediaBucket = 'chat-media';

final db = FirebaseFirestore.instance;
final auth = FirebaseAuth.instance;
final supabase = Supabase.instance.client;

// MESSAGE EXPIRY: 10 MINUTES

Timestamp messageExpiry() {
  return Timestamp.fromDate(
    DateTime.now().add(const Duration(minutes: 10)),
  );
}

Future<void> cleanupExpiredMessages(String chatId) async {
  try {
    final messagesRef =
        db.collection('chats').doc(chatId).collection('messages');

    final expiredMessages = await messagesRef
        .where('expiresAt', isLessThanOrEqualTo: Timestamp.now())
        .get();

    for (final message in expiredMessages.docs) {
      try {
        await message.reference.delete();
      } catch (e) {
        debugPrint('Expired message deletion failed: $e');
      }
    }
  } catch (e) {
    debugPrint('Message cleanup error: $e');
  }
}

bool isMessageExpired(Map<String, dynamic> data) {
  final expiry = data['expiresAt'];

  // Old messages without expiry remain visible.
  if (expiry is! Timestamp) return false;

  return !expiry.toDate().isAfter(DateTime.now());
}

// PREMIUM HELPERS

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
  final d = expiry.toDate().difference(DateTime.now());
  if (d.isNegative || d.inSeconds <= 0) return 'Expired';
  if (d.inDays >= 1) return '${d.inDays} day(s) remaining';
  if (d.inHours >= 1) return '${d.inHours} hour(s) remaining';
  return '${d.inMinutes} minute(s) remaining';
}

bool genderMatches(String preference, String gender) =>
    preference == 'Both' || preference == gender;

// PROFILE HELPER

Future<void> saveUserProfile(User user, {String? name}) async {
  final ref = db.collection('users').doc(user.uid);
  final doc = await ref.get();
  if (!doc.exists) {
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
        return snapshot.data == null
            ? const AuthScreen()
            : const HomeScreen();
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
    } catch (e) {
      if (mounted) setState(() => message = 'Something went wrong: $e');
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
      if (googleUser == null) return;
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
      if (mounted) setState(() => message = e.message ?? 'Could not send email.');
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
                'STRENZO',
                style: TextStyle(
                  color: gold,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Meet. Connect. Chat.',
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
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                    icon: Icon(obscurePassword
                        ? Icons.visibility
                        : Icons.visibility_off),
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
              'STRENZO',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.1,
                fontSize: 17,
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FindStrangerScreen()),
          ),
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

// PART 2 STARTS FROM HERE:
// // STRANGER MATCHING
// STRANGER MATCHING

class FindStrangerScreen extends StatefulWidget {
  const FindStrangerScreen({super.key});

  @override
  State<FindStrangerScreen> createState() => _FindStrangerScreenState();
}

class _FindStrangerScreenState extends State<FindStrangerScreen> {
  bool searching = false;
  String status = 'Ready to meet someone new.';
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? queueSubscription;
  String? currentChatId;
  Timer? searchTimer;

  String get uid => auth.currentUser!.uid;

  @override
  void dispose() {
    queueSubscription?.cancel();
    searchTimer?.cancel();
    super.dispose();
  }

  Future<void> startSearching() async {
    if (searching) return;

    setState(() {
      searching = true;
      status = 'Finding someone for you...';
    });

    try {
      final userDoc = await db.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      final gender = userData['gender'] ?? 'Other';
      final preference = isPremiumActive(userData)
          ? (userData['genderPreference'] ?? 'Both')
          : 'Both';

      await db.collection('matchQueue').doc(uid).set({
        'uid': uid,
        'gender': gender,
        'preference': preference,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'waiting',
      });

      queueSubscription = db
          .collection('matchQueue')
          .snapshots()
          .listen((snapshot) async {
        if (!searching || currentChatId != null) return;

        for (final doc in snapshot.docs) {
          if (doc.id == uid) continue;

          final other = doc.data();
          if (other['status'] != 'waiting') continue;

          final otherGender = other['gender'] ?? 'Other';
          final otherPreference = other['preference'] ?? 'Both';

          if (!genderMatches(preference, otherGender)) continue;
          if (!genderMatches(otherPreference, gender)) continue;

          final otherRef = db.collection('matchQueue').doc(doc.id);
          final myRef = db.collection('matchQueue').doc(uid);

          final chatRef = db.collection('chats').doc();

          try {
            await db.runTransaction((transaction) async {
              final mySnapshot = await transaction.get(myRef);
              final otherSnapshot = await transaction.get(otherRef);

              if (!mySnapshot.exists || !otherSnapshot.exists) {
                throw Exception('User is no longer available.');
              }

              if (mySnapshot.data()?['status'] != 'waiting' ||
                  otherSnapshot.data()?['status'] != 'waiting') {
                throw Exception('Already matched.');
              }

              transaction.update(myRef, {
                'status': 'matched',
                'chatId': chatRef.id,
              });

              transaction.update(otherRef, {
                'status': 'matched',
                'chatId': chatRef.id,
              });

              transaction.set(chatRef, {
                'members': [uid, doc.id],
                'type': 'stranger',
                'createdAt': FieldValue.serverTimestamp(),
              });
            });

            currentChatId = chatRef.id;
            await queueSubscription?.cancel();

            if (!mounted) return;

            setState(() {
              searching = false;
              status = 'Stranger found!';
            });

            await Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  chatId: chatRef.id,
                  partnerUid: doc.id,
                ),
              ),
            );
            return;
          } catch (e) {
            debugPrint('Matching error: $e');
          }
        }
      });

      searchTimer = Timer(const Duration(seconds: 30), () async {
        if (searching && currentChatId == null) {
          await stopSearching();
          if (!mounted) return;

          setState(() {
            status = 'No stranger found. Please try again.';
          });
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          searching = false;
          status = 'Could not start searching.';
        });
      }
    }
  }

  Future<void> stopSearching() async {
    searchTimer?.cancel();
    await queueSubscription?.cancel();

    try {
      await db.collection('matchQueue').doc(uid).delete();
    } catch (_) {}

    if (!mounted) return;

    setState(() {
      searching = false;
      currentChatId = null;
      status = 'Search stopped.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Stranger')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                searching ? Icons.travel_explore : Icons.people_alt_outlined,
                color: gold,
                size: 90,
              ),
              const SizedBox(height: 25),
              Text(
                searching ? 'SEARCHING...' : 'READY TO CONNECT?',
                style: const TextStyle(
                  color: gold,
                  fontWeight: FontWeight.w900,
                  fontSize: 23,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 35),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: searching ? stopSearching : startSearching,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.all(17),
                  ),
                  child: Text(
                    searching ? 'STOP SEARCHING' : 'FIND STRANGER',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
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
  Timer? cleanupTimer;
  Timer? refreshTimer;
  bool leaving = false;

  @override
  void initState() {
    super.initState();

    cleanupExpiredMessages(widget.chatId);

    cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        cleanupExpiredMessages(widget.chatId);
      },
    );

    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    cleanupTimer?.cancel();
    refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> leaveChat() async {
    if (leaving) return;
    leaving = true;

    try {
      await db.collection('chats').doc(widget.chatId).update({
        'endedBy': auth.currentUser!.uid,
        'endedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stranger Chat'),
        actions: [
          IconButton(
            onPressed: leaveChat,
            icon: const Icon(Icons.stop_circle_outlined),
            tooltip: 'Stop Chat',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                final messages = (snapshot.data?.docs ?? [])
                    .where((doc) => !isMessageExpired(doc.data()))
                    .toList();

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Say hello to your stranger!',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data();
                    final mine = data['senderId'] ==
                        auth.currentUser!.uid;

                    return ChatMessageBubble(
                      data: data,
                      mine: mine,
                      messageRef: message.reference,
                    );
                  },
                );
              },
            ),
          ),
          ChatComposer(chatId: widget.chatId),
        ],
      ),
    );
  }
}

// CHAT MESSAGE BUBBLE

class ChatMessageBubble extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool mine;
  final DocumentReference<Map<String, dynamic>>? messageRef;

  const ChatMessageBubble({
    super.key,
    required this.data,
    required this.mine,
    this.messageRef,
  });

  @override
  State<ChatMessageBubble> createState() => _ChatMessageBubbleState();
}

class _ChatMessageBubbleState extends State<ChatMessageBubble> {
  bool markingSeen = false;

  @override
  void initState() {
    super.initState();
    markSeen();
  }

  @override
  void didUpdateWidget(covariant ChatMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.data['seen'] != widget.data['seen']) {
      markSeen();
    }
  }

  Future<void> markSeen() async {
    if (widget.mine ||
        widget.data['seen'] == true ||
        widget.messageRef == null ||
        markingSeen) {
      return;
    }

    markingSeen = true;

    try {
      await widget.messageRef!.update({
        'seen': true,
        'seenAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Seen update failed: $e');
    } finally {
      markingSeen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final mine = widget.mine;
    final type = data['type'] ?? 'text';

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF392044) : panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: gold.withOpacity(.22)),
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (type == 'image')
              ChatImage(url: data['url'] ?? ''),
            if (type == 'audio')
              ChatAudio(url: data['url'] ?? ''),
            if (type == 'text')
              Text(
                data['text'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            if (mine) ...[
              const SizedBox(height: 5),
              Text(
                data['seen'] == true ? 'Seen' : 'Sent',
                style: TextStyle(
                  color: data['seen'] == true
                      ? gold
                      : Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// CHAT IMAGE

class ChatImage extends StatelessWidget {
  final String url;

  const ChatImage({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(backgroundColor: Colors.black),
              body: Center(
                child: InteractiveViewer(
                  child: Image.network(url),
                ),
              ),
            ),
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: 220,
          height: 220,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const SizedBox(
              width: 220,
              height: 180,
              child: Center(
                child: CircularProgressIndicator(color: gold),
              ),
            );
          },
          errorBuilder: (_, __, ___) => const SizedBox(
            width: 200,
            height: 100,
            child: Center(
              child: Text(
                'Image unavailable',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// CHAT AUDIO

class ChatAudio extends StatefulWidget {
  final String url;

  const ChatAudio({super.key, required this.url});

  @override
  State<ChatAudio> createState() => _ChatAudioState();
}

class _ChatAudioState extends State<ChatAudio> {
  final AudioPlayer player = AudioPlayer();
  bool playing = false;

  @override
  void initState() {
    super.initState();

    player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          playing = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> toggleAudio() async {
    try {
      if (playing) {
        await player.pause();
      } else {
        await player.play(UrlSource(widget.url));
      }
    } catch (e) {
      debugPrint('Audio playback error: $e');
    }
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: toggleAudio,
          icon: Icon(
            playing ? Icons.pause_circle : Icons.play_circle,
            color: gold,
            size: 35,
          ),
        ),
        const Text(
          'Voice message',
          style: TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

// CHAT COMPOSER

class ChatComposer extends StatefulWidget {
  final String chatId;

  const ChatComposer({super.key, required this.chatId});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final controller = TextEditingController();
  final recorder = AudioRecorder();
  final picker = ImagePicker();

  bool recording = false;
  bool sending = false;

  CollectionReference<Map<String, dynamic>> get messagesRef =>
      db.collection('chats').doc(widget.chatId).collection('messages');

  Future<void> sendText() async {
    final text = controller.text.trim();
    if (text.isEmpty || sending) return;

    controller.clear();
    setState(() => sending = true);

    try {
      await messagesRef.add({
        'senderId': auth.currentUser!.uid,
        'text': text,
        'type': 'text',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': messageExpiry(),
        'seen': false,
      });
    } catch (e) {
      debugPrint('Message send error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> sendImage() async {
    if (sending) return;

    try {
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
      );

      if (image == null) return;

      setState(() => sending = true);

      final file = File(image.path);
      final path =
          '${widget.chatId}/${DateTime.now().millisecondsSinceEpoch}_${auth.currentUser!.uid}.jpg';

      await supabase.storage.from(mediaBucket).upload(
            path,
            file,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: false,
            ),
          );

      final url = supabase.storage.from(mediaBucket).getPublicUrl(path);

      await messagesRef.add({
        'senderId': auth.currentUser!.uid,
        'type': 'image',
        'url': url,
        'storagePath': path,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': messageExpiry(),
        'seen': false,
      });
    } catch (e) {
      debugPrint('Image send error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> startRecording() async {
    try {
      if (!await recorder.hasPermission()) return;

      final directory = Directory.systemTemp;
      final path =
          '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );

      if (mounted) setState(() => recording = true);
    } catch (e) {
      debugPrint('Recording start error: $e');
    }
  }

  Future<void> stopAndSendRecording() async {
    try {
      final path = await recorder.stop();

      if (mounted) setState(() => recording = false);
      if (path == null) return;

      setState(() => sending = true);

      final file = File(path);
      final storagePath =
          '${widget.chatId}/voice_${DateTime.now().millisecondsSinceEpoch}_${auth.currentUser!.uid}.m4a';

      await supabase.storage.from(mediaBucket).upload(
            storagePath,
            file,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: false,
            ),
          );

      final url =
          supabase.storage.from(mediaBucket).getPublicUrl(storagePath);

      await messagesRef.add({
        'senderId': auth.currentUser!.uid,
        'type': 'audio',
        'url': url,
        'storagePath': storagePath,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': messageExpiry(),
        'seen': false,
      });
    } catch (e) {
      debugPrint('Voice message error: $e');
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: const BoxDecoration(
          color: panel,
          border: Border(top: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: sending ? null : sendImage,
              icon: const Icon(Icons.image_outlined, color: gold),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  filled: true,
                  fillColor: bg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => sendText(),
              ),
            ),
            if (recording)
              IconButton(
                onPressed: sending ? null : stopAndSendRecording,
                icon: const Icon(Icons.stop_circle, color: Colors.red),
              )
            else
              IconButton(
                onPressed: sending ? null : startRecording,
                icon: const Icon(Icons.mic, color: gold),
              ),
            IconButton(
              onPressed: sending ? null : sendText,
              icon: const Icon(Icons.send, color: gold),
            ),
          ],
        ),
      ),
    );
  }
}

// PART 2 END
//// FRIENDS SCREEN

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final inviteController = TextEditingController();
  bool loading = false;

  String get uid => auth.currentUser!.uid;

  String friendshipId(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}_${ids[1]}';
  }

  Future<void> createInvite() async {
    try {
      setState(() => loading = true);

      final ref = db.collection('friendInvites').doc();

      await ref.set({
        'inviterUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'used': false,
      });

      await Clipboard.setData(ClipboardData(text: ref.id));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite code copied! Share it with your friend.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Invite creation error: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> acceptInvite() async {
    final code = inviteController.text.trim();

    if (code.isEmpty || loading) return;

    setState(() => loading = true);

    try {
      final inviteRef = db.collection('friendInvites').doc(code);
      final inviteSnapshot = await inviteRef.get();

      if (!inviteSnapshot.exists) {
        throw Exception('Invalid invite code.');
      }

      final inviteData = inviteSnapshot.data()!;
      final inviterUid = inviteData['inviterUid'] as String?;

      if (inviterUid == null || inviterUid == uid) {
        throw Exception('This invite code cannot be used.');
      }

      if (inviteData['used'] == true) {
        throw Exception('This invite has already been used.');
      }

      final friendship = friendshipId(uid, inviterUid);
      final friendshipRef =
          db.collection('friendships').doc(friendship);

      await db.runTransaction((transaction) async {
        final latestInvite = await transaction.get(inviteRef);
        final latestFriendship = await transaction.get(friendshipRef);

        if (!latestInvite.exists ||
            latestInvite.data()?['used'] == true) {
          throw Exception('Invite is no longer available.');
        }

        if (!latestFriendship.exists) {
          transaction.set(friendshipRef, {
            'members': [uid, inviterUid],
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        transaction.update(inviteRef, {
          'used': true,
          'usedBy': uid,
          'usedAt': FieldValue.serverTimestamp(),
        });
      });

      inviteController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Friend added successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    inviteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: gold.withOpacity(.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_add_alt_1, color: gold, size: 35),
                const SizedBox(height: 12),
                const Text(
                  'INVITE YOUR FRIENDS',
                  style: TextStyle(
                    color: gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Create an invite code and share it with your friend.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loading ? null : createInvite,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('CREATE INVITE CODE'),
                  ),
                ),
                const Divider(height: 30, color: Colors.white24),
                const Text(
                  'HAVE AN INVITE CODE?',
                  style: TextStyle(color: gold, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: inviteController,
                  decoration: const InputDecoration(
                    hintText: 'Enter invite code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: loading ? null : acceptInvite,
                    child: const Text('ADD FRIEND'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'YOUR FRIENDS',
            style: TextStyle(
              color: gold,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db
                .collection('friendships')
                .where('members', arrayContains: uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: gold),
                );
              }

              final friendships = snapshot.data?.docs ?? [];

              if (friendships.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(25),
                  child: Center(
                    child: Text(
                      'No friends yet. Invite someone to get started!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                );
              }

              return Column(
                children: friendships.map((friendship) {
                  final members =
                      List<String>.from(friendship.data()['members'] ?? []);
                  final partnerUid = members.firstWhere(
                    (id) => id != uid,
                    orElse: () => '',
                  );

                  if (partnerUid.isEmpty) {
                    return const SizedBox.shrink();
                  }

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: db.collection('users').doc(partnerUid).get(),
                    builder: (context, userSnapshot) {
                      final userData = userSnapshot.data?.data() ?? {};
                      final name = userData['name'] ?? 'Friend';

                      return Card(
                        color: panel,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: gold.withOpacity(.2),
                            child: const Icon(Icons.person, color: gold),
                          ),
                          title: Text(name.toString()),
                          subtitle: const Text('Tap to start chatting'),
                          trailing: const Icon(
                            Icons.chat_bubble_outline,
                            color: gold,
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => FriendChatScreen(
                                  chatId: friendship.id,
                                  partnerUid: partnerUid,
                                  partnerName: name.toString(),
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

// FRIEND CHAT

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
  Timer? cleanupTimer;
  Timer? refreshTimer;

  @override
  void initState() {
    super.initState();

    cleanupExpiredMessages(widget.chatId);

    cleanupTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => cleanupExpiredMessages(widget.chatId),
    );

    refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    cleanupTimer?.cancel();
    refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.partnerName),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: db
                  .collection('chats')
                  .doc(widget.chatId)
                  .collection('messages')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: gold),
                  );
                }

                final messages = (snapshot.data?.docs ?? [])
                    .where((doc) => !isMessageExpired(doc.data()))
                    .toList();

                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'Start a conversation with your friend!',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final data = message.data();
                    final mine =
                        data['senderId'] == auth.currentUser!.uid;

                    return ChatMessageBubble(
                      data: data,
                      mine: mine,
                      messageRef: message.reference,
                    );
                  },
                );
              },
            ),
          ),
          ChatComposer(chatId: widget.chatId),
        ],
      ),
    );
  }
}

// PREMIUM SCREEN

class PremiumScreen extends StatelessWidget {
  const PremiumScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = auth.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final active = isPremiumActive(data);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(25),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
                  colors: [Color(0xFF3B1550), Color(0xFF160B20)],
                ),
                border: Border.all(color: gold.withOpacity(.5)),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.workspace_premium,
                    color: gold,
                    size: 65,
                  ),
                  const SizedBox(height: 15),
                  const Text(
                    'STRENZO PREMIUM',
                    style: TextStyle(
                      color: gold,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    active ? 'YOUR PREMIUM IS ACTIVE' : 'UPGRADE YOUR EXPERIENCE',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 15),
                  if (active)
                    Text(
                      premiumRemaining(data),
                      style: const TextStyle(color: gold, fontSize: 16),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'PREMIUM FEATURES',
              style: TextStyle(
                color: gold,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 15),
            const _FeatureTile(
              icon: Icons.filter_alt_outlined,
              title: 'Gender Filter',
              subtitle: 'Choose who you want to meet.',
            ),
            const _FeatureTile(
              icon: Icons.star_outline,
              title: 'Premium Profile',
              subtitle: 'Show your premium membership.',
            ),
            const _FeatureTile(
              icon: Icons.all_inclusive,
              title: 'Better Experience',
              subtitle: 'Enjoy additional app features.',
            ),
            const SizedBox(height: 20),
            const Text(
              'Premium access is managed by the STRENZO admin team.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ],
        );
      },
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: gold, size: 28),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

// PROFILE SCREEN

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = auth.currentUser!;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? {};
        final name = data['name'] ?? user.displayName ?? 'Member';
        final email = data['email'] ?? user.email ?? '';
        final bio = data['bio'] ?? '';
        final premium = isPremiumActive(data);

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 15),
            CircleAvatar(
              radius: 48,
              backgroundColor: gold.withOpacity(.2),
              child: const Icon(Icons.person, color: gold, size: 55),
            ),
            const SizedBox(height: 15),
            Center(
              child: Text(
                name.toString(),
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Center(
              child: Text(
                email.toString(),
                style: const TextStyle(color: Colors.white54),
              ),
            ),
            if (premium)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Center(
                  child: Text(
                    '★ PREMIUM MEMBER',
                    style: TextStyle(
                      color: gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 15),
            if (bio.toString().isNotEmpty)
              Center(
                child: Text(
                  bio.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 25),
            _ActionTile(
              icon: Icons.edit_outlined,
              title: 'Edit Profile',
              subtitle: 'Update your name, bio and gender',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditProfileScreen(data: data),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin Panel',
              subtitle: 'Administrator access',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AdminLoginScreen(),
                  ),
                );
              },
            ),
            _ActionTile(
              icon: Icons.logout,
              title: 'Logout',
              subtitle: 'Sign out of your account',
              onTap: () async {
                await auth.signOut();
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
  final Map<String, dynamic> data;

  const EditProfileScreen({
    super.key,
    required this.data,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController nameController;
  late final TextEditingController bioController;

  String gender = 'Other';
  bool saving = false;

  @override
  void initState() {
    super.initState();

    nameController = TextEditingController(
      text: widget.data['name'] ?? '',
    );

    bioController = TextEditingController(
      text: widget.data['bio'] ?? '',
    );

    gender = widget.data['gender'] ?? 'Other';
  }

  Future<void> saveProfile() async {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name.')),
      );
      return;
    }

    setState(() => saving = true);

    try {
      await db.collection('users').doc(auth.currentUser!.uid).set({
        'name': name,
        'bio': bioController.text.trim(),
        'gender': gender,
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
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
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Full Name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: bioController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Bio',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Gender',
            style: TextStyle(color: gold, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: gender,
            dropdownColor: panel,
            items: const [
              DropdownMenuItem(value: 'Male', child: Text('Male')),
              DropdownMenuItem(value: 'Female', child: Text('Female')),
              DropdownMenuItem(value: 'Other', child: Text('Other')),
            ],
            onChanged: (value) {
              if (value != null) setState(() => gender = value);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 25),
          ElevatedButton(
            onPressed: saving ? null : saveProfile,
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(16),
            ),
            child: saving
                ? const CircularProgressIndicator(color: Colors.black)
                : const Text('SAVE PROFILE'),
          ),
        ],
      ),
    );
  }
}

// ADMIN LOGIN

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool loading = false;
  String error = '';

  Future<void> loginAdmin() async {
    setState(() {
      loading = true;
      error = '';
    });

    try {
      final credential = await auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final userDoc =
          await db.collection('users').doc(credential.user!.uid).get();

      if (userDoc.data()?['role'] != 'admin') {
        await auth.signOut();
        throw Exception('You do not have administrator access.');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminDashboardScreen(),
        ),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => error = e.message ?? 'Admin login failed.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin Login')),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          const Icon(
            Icons.admin_panel_settings,
            color: gold,
            size: 75,
          ),
          const SizedBox(height: 20),
          const Text(
            'ADMINISTRATOR',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: gold,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 25),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Admin Email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(
                error,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: loading ? null : loginAdmin,
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.all(16),
            ),
            child: loading
                ? const CircularProgressIndicator(color: Colors.black)
                : const Text('ADMIN LOGIN'),
          ),
        ],
      ),
    );
  }
}

// ADMIN DASHBOARD

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Future<void> updatePremium(
    BuildContext context,
    String uid,
    int days,
  ) async {
    final expiry = Timestamp.fromDate(
      DateTime.now().add(Duration(days: days)),
    );

    await db.collection('users').doc(uid).set({
      'isPremium': true,
      'premiumExpiresAt': expiry,
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Premium activated for $days days.')),
      );
    }
  }

  Future<void> removePremium(String uid) async {
    await db.collection('users').doc(uid).set({
      'isPremium': false,
      'premiumExpiresAt': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  Future<void> toggleBan(
    BuildContext context,
    String uid,
    bool currentlyBanned,
  ) async {
    await db.collection('users').doc(uid).set({
      'isBanned': !currentlyBanned,
    }, SetOptions(merge: true));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyBanned ? 'User unbanned.' : 'User banned.',
          ),
        ),
      );
    }
  }

  void showUserOptions(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: panel,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data['name'] ?? 'User',
                  style: const TextStyle(
                    color: gold,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: const Icon(Icons.workspace_premium, color: gold),
                  title: const Text('Activate Premium - 30 Days'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await updatePremium(context, uid, 30);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium, color: gold),
                  title: const Text('Activate Premium - 90 Days'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await updatePremium(context, uid, 90);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.workspace_premium, color: gold),
                  title: const Text('Activate Premium - 365 Days'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await updatePremium(context, uid, 365);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.remove_circle_outline),
                  title: const Text('Remove Premium'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await removePremium(uid);
                  },
                ),
                ListTile(
                  leading: Icon(
                    data['isBanned'] == true
                        ? Icons.lock_open
                        : Icons.block,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    data['isBanned'] == true ? 'Unban User' : 'Ban User',
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await toggleBan(
                      context,
                      uid,
                      data['isBanned'] == true,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            onPressed: () async {
              await auth.signOut();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: gold),
            );
          }

          final users = snapshot.data?.docs ?? [];

          return ListView(
            padding: const EdgeInsets.all(15),
            children: [
              Card(
                color: panel,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.people_alt_outlined,
                        color: gold,
                        size: 35,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'TOTAL USERS',
                        style: TextStyle(color: Colors.white70),
                      ),
                      Text(
                        '${users.length}',
                        style: const TextStyle(
                          color: gold,
                          fontWeight: FontWeight.w900,
                          fontSize: 30,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'USER MANAGEMENT',
                style: TextStyle(
                  color: gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 10),
              ...users.map((doc) {
                final data = doc.data();
                final name = data['name'] ?? 'Unknown User';
                final email = data['email'] ?? '';
                final banned = data['isBanned'] == true;
                final premium = isPremiumActive(data);

                return Card(
                  color: panel,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: gold.withOpacity(.2),
                      child: const Icon(Icons.person, color: gold),
                    ),
                    title: Text(name.toString()),
                    subtitle: Text(
                      '${email.toString()}\n'
                      '${banned ? 'BANNED' : 'Active'}'
                      '${premium ? ' • PREMIUM' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert, color: gold),
                      onPressed: () => showUserOptions(
                        context,
                        doc.id,
                        data,
                      ),
                    ),
                  ),
                );
              }),
            ],
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
  Widget build(BuildContext context) {
    return Card(
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
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          color: gold,
          size: 16,
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 8),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: gold.withOpacity(.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: gold),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              color: gold,
              fontWeight: FontWeight.bold,
              fontSize: 18,
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
}

// APP ENTRY POINT

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseKey,
  );

  runApp(const StrenzoApp());
}

class StrenzoApp extends StatelessWidget {
  const StrenzoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'STRENZO',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        primaryColor: gold,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: gold,
          surface: panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: bg,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel,
          labelStyle: const TextStyle(color: Colors.white70),
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: gold),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF111111),
          indicatorColor: Color(0x333B1550),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(color: Colors.white70),
          ),
        ),
      ),
      home: const AuthGate(),
    );
  }
}

// END OF MAIN.DART PART 3 WILL CONTINUE WITH FRIENDS, PREMIUM, PROFILE AND ADMIN.
