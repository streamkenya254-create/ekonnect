import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../models/message_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore_service.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/connection_state_view.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  late Map<String, dynamic> _args;
  bool _argsLoaded = false;

  String get _incidentId => _args['incidentId'] as String;
  String get _otherName => _args['otherName'] as String? ?? 'Contact';
  String get _otherPhone => _args['otherPhone'] as String? ?? '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsLoaded) {
      _args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
      _argsLoaded = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();
    final user = context.read<AuthProvider>().user!;
    final msg = MessageModel(
      id: '',
      senderId: user.uid,
      senderName: user.name,
      text: text,
      timestamp: DateTime.now(),
    );
    await FirestoreService.sendMessage(_incidentId, msg);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _call() async {
    if (_otherPhone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: _otherPhone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final myUid = context.read<AuthProvider>().user?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_otherName),
            if (_otherPhone.isNotEmpty)
              Text(_otherPhone,
                  style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_otherPhone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call),
              tooltip: 'Call',
              onPressed: _call,
            ),
        ],
      ),
      // resizeToAvoidBottomInset: true (default) pushes the body above the keyboard.
      // The input bar must NOT manually add viewInsets.bottom or it doubles up.
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: FirestoreService.streamMessages(_incidentId),
              builder: (context, snap) {
                if (snap.hasError) {
                  // Previously this fell through to an endless spinner, so a
                  // dropped connection looked identical to "still loading".
                  // The stream is built in this method, so setState genuinely
                  // re-subscribes rather than just repainting.
                  return ConnectionStateView(
                    title: 'Cannot load messages',
                    message: 'You appear to be offline. Your responder can '
                        'still be reached by phone.',
                    onRetry: () => setState(() {}),
                    compact: true,
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final messages = snap.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: Text('No messages yet. Say hello!',
                        style: TextStyle(color: AppColors.textLight)),
                  );
                }
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _scrollToBottom());
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i];
                    return ChatBubble(
                      message: msg,
                      isMe: msg.senderId == myUid,
                    );
                  },
                );
              },
            ),
          ),

          // Input bar — keyboard handled by Scaffold resize, not manual insets
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type a message…',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: AppColors.background,
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton.small(
                    onPressed: _send,
                    backgroundColor: AppColors.primary,
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
