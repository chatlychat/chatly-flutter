import 'package:chatly/chatly.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Use your real publicId + apiHost in production.
  await Chatly.instance.configure(
    const ChatlyConfig(
      publicId: 'pub_abc123',
      apiHost: 'api.chatlychat.com',
    ),
  );
  runApp(const ExampleApp());
}

/// The sample app's root widget.
class ExampleApp extends StatelessWidget {
  /// Creates the sample app.
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatly example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

/// The one screen in the sample: a button that opens the chat.
class HomeScreen extends StatelessWidget {
  /// Creates the sample's home screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chatly example')),
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Tap the bubble or the button below to start chatting.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await Chatly.instance.identify(
                      const ChatlyIdentity(
                        externalId: 'user_42',
                        email: 'u@example.com',
                        name: 'Alice',
                      ),
                    );
                  },
                  child: const Text('Identify as Alice'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () => Chatly.instance.show(context),
                  child: const Text('Open chat'),
                ),
                const SizedBox(height: 24),
                StreamBuilder<int>(
                  stream: Chatly.instance.unreadCount,
                  initialData: 0,
                  builder: (context, snap) =>
                      Text('Unread: ${snap.data ?? 0}'),
                ),
              ],
            ),
          ),
          const ChatlyWidget(),
        ],
      ),
    );
  }
}
