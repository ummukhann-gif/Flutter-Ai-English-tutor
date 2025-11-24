import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/types.dart';
import '../providers/app_provider.dart';
import '../services/live_gemini_service.dart';
import '../widgets/chat_bubble.dart';

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _isMicOn = false;
  bool _isReady = false;
  bool _isTextMode = false;
  LiveState _liveState = LiveState.disconnected;
  String _streamingText = '';

  late final LiveGeminiService _live;
  late AnimationController _pulseController;

  StreamSubscription<String>? _inputSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<LiveState>? _stateSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _live = LiveGeminiService();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLesson();
    });
  }

  Future<void> _startLesson() async {
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;

    final history = provider.history.conversations[lesson.id] ?? [];
    final historyText = history
        .map((m) => '${m.speaker == Speaker.ai ? 'Tutor' : 'User'}: ${m.text}')
        .join('\n');

    final nativeLang = provider.languages?.native ?? 'Uzbek';
    final targetLang = provider.languages?.target ?? 'English';

    final systemPrompt = '''
You are a strict, professional language tutor ("ustoz") teaching a $nativeLang speaker to learn $targetLang.

**CRITICAL RULES (MUST FOLLOW):**
1.  **ZERO TOLERANCE FOR IGNORANCE**: If the user says "I don't know", "Bilmayman", "No", or stays silent, you MUST NOT say "Good job" or "Barakalla". Instead, IMMEDIATELY teach them the answer and make them repeat it.
2.  **CORRECT MISTAKES INSTANTLY**: If the user makes a pronunciation or grammar mistake, stop and correct them. Do not praise incorrect attempts.
3.  **SHORT & CLEAR**: Keep your responses concise. Focus on the lesson tasks.
4.  **USE $nativeLang FOR EXPLANATIONS**: Explain complex concepts in $nativeLang, but encourage the user to speak in $targetLang.
5.  **NO INTERNAL THOUGHTS**: Output ONLY what you want to say to the student. Do not output thinking processes.
6.  **VISION CAPABILITIES**: You can see images the user sends. If they send an image of a book or text, read it and help them. Use the image as context for the lesson.

**YOUR LESSON PLAN:**
- Lesson Title: ${lesson.title}
- Tasks: ${lesson.tasks.join('; ')}
- Vocabulary: ${lesson.vocabulary.map((v) => '${v.word} (${v.translation})').join(', ')}

**LESSON COMPLETION:**
When completed, end your response (in $nativeLang) with "LESSON_COMPLETE" on a new line, followed by a score (1-10) and brief feedback.
''';

    await _live.connect(
      systemInstruction: systemPrompt,
      historyContext: historyText.isEmpty ? null : historyText,
    );

    _inputSub = _live.inputTranscriptStream.listen((text) {
      final current = context.read<AppProvider>().currentLesson;
      if (current != null) _appendMessage(Speaker.user, text, current.id);

      // Clear streaming text when user speaks (new turn)
      if (_streamingText.isNotEmpty) {
        setState(() => _streamingText = '');
      }
    });

    _outputSub = _live.outputTranscriptStream.listen((text) {
      final current = context.read<AppProvider>().currentLesson;
      if (current != null) {
        _appendMessage(Speaker.ai, text, current.id);

        setState(() {
          // If text contains completion token, don't show it in karaoke
          if (text.contains('LESSON_COMPLETE')) {
            _handleCompletion(text, current);
          } else {
            _streamingText += text;
          }
        });
      }
    });

    _stateSub = _live.connectionStateStream.listen((state) {
      setState(() {
        _isReady = state == LiveState.ready || state == LiveState.recording;
        _isMicOn = state == LiveState.recording;
        _liveState = state;

        if (state == LiveState.recording) {
          _streamingText = ''; // Clear text when recording starts
        }
      });
    });

    _errorSub = _live.errorStream.listen((err) {
      debugPrint('Live error: $err');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
      );
    });
  }

  void _appendMessage(Speaker speaker, String text, String lessonId) {
    if (!mounted) return;

    final provider = context.read<AppProvider>();
    final history =
        List<Conversation>.from(provider.history.conversations[lessonId] ?? []);

    if (history.isNotEmpty && history.last.speaker == speaker) {
      final last = history.last;
      history[history.length - 1] = Conversation(
        speaker: last.speaker,
        text: last.text + text,
        timestamp: last.timestamp,
      );
    } else {
      history.add(
        Conversation(speaker: speaker, text: text, timestamp: DateTime.now()),
      );
    }

    provider.updateConversationHistory(lessonId, history);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  Future<void> _handleCompletion(String text, Lesson lesson) async {
    final provider = context.read<AppProvider>();
    final parts = text.split('LESSON_COMPLETE');
    final rest = parts.length > 1 ? parts[1].trim() : '';
    int scoreVal = 8;
    String feedback = 'Good job!';
    if (rest.isNotEmpty) {
      final lines = rest.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.isNotEmpty) {
        scoreVal = int.tryParse(lines[0].replaceAll(RegExp(r'[^0-9]'), '')) ??
            scoreVal;
      }
      if (lines.length > 1) feedback = lines.sublist(1).join(' ').trim();
    }

    final score = Score(
      lessonId: lesson.id,
      score: scoreVal,
      feedback: feedback,
      completedAt: DateTime.now(),
    );

    if (!mounted) return;
    _live.stopMicStream();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => _CompletionDialog(
        score: score,
        onNext: () {
          Navigator.pop(c);
          provider.completeLesson(score);
        },
      ),
    );
  }

  Future<void> _ensureConnected() async {
    if (_isReady) return;
    await _startLesson();
  }

  Future<void> _handleSendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;
    await _ensureConnected();
    _appendMessage(Speaker.user, text, lesson.id);
    _live.sendText(text);
    setState(() => _streamingText = ''); // Clear previous AI text
  }

  Future<void> _handleImageSelection() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        await _ensureConnected();

        await _live.sendImage(bytes, mimeType: 'image/jpeg');

        final provider = context.read<AppProvider>();
        final lesson = provider.currentLesson;
        if (lesson != null) {
          _appendMessage(Speaker.user, '[Sent an image]', lesson.id);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image sent to AI Tutor')),
        );
        setState(() => _streamingText = '');
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _outputSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _live.dispose();
    _scrollController.dispose();
    _textController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return const SizedBox();
    final history = provider.history.conversations[lesson.id] ?? [];
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isTextMode
            ? _buildChatView(theme, lesson, history)
            : _buildLiveView(theme, lesson, provider),
      ),
    );
  }

  Widget _buildLiveView(ThemeData theme, Lesson lesson, AppProvider provider) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.blue.shade50.withOpacity(0.3),
                  Colors.white,
                ],
              ),
            ),
          ),
        ),
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        size: 28, color: Colors.black87),
                    onPressed: () => provider.exitLesson(),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _liveState == LiveState.ready ||
                                    _liveState == LiveState.recording
                                ? Colors.green
                                : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _liveState == LiveState.recording
                              ? 'Listening'
                              : 'Live',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 26, color: Colors.black87),
                    onPressed: () => setState(() => _isTextMode = true),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: SingleChildScrollView(
                    reverse: true,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _streamingText.isNotEmpty
                          ? Text(
                              _streamingText,
                              key: const ValueKey('streaming'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'AI Tutor',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey.shade500,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _isMicOn ? 'Listening...' : 'Tap to speak',
                                  style: TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 48, top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCircleButton(
                    icon: Icons.camera_alt_outlined,
                    onTap: _handleImageSelection,
                    color: Colors.grey.shade100,
                    iconColor: Colors.black87,
                  ),
                  const SizedBox(width: 32),
                  GestureDetector(
                    onTapDown: (_) async {
                      if (!_isReady) return;
                      HapticFeedback.lightImpact();
                      await _ensureConnected();
                      await _live.startMicStream();
                      setState(() => _isMicOn = true);
                    },
                    onTapUp: (_) {
                      _live.stopMicStream();
                      setState(() => _isMicOn = false);
                    },
                    onTapCancel: () {
                      _live.stopMicStream();
                      setState(() => _isMicOn = false);
                    },
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            shape: BoxShape.circle,
                            boxShadow: _isMicOn
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withOpacity(0.3),
                                      blurRadius:
                                          20 + (10 * _pulseController.value),
                                      spreadRadius:
                                          5 + (5 * _pulseController.value),
                                    )
                                  ]
                                : [],
                          ),
                          child: Icon(
                            _isMicOn ? Icons.graphic_eq : Icons.mic_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 32),
                  _buildCircleButton(
                    icon: Icons.more_horiz_rounded,
                    onTap: () {},
                    color: Colors.grey.shade100,
                    iconColor: Colors.black87,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    required Color iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
    );
  }

  Widget _buildChatView(
      ThemeData theme, Lesson lesson, List<Conversation> history) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 22),
                onPressed: () => setState(() => _isTextMode = false),
              ),
              const SizedBox(width: 8),
              Text(
                'Chat',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: history.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: history[index]);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Colors.grey.shade100)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_photo_alternate_outlined,
                    color: Colors.grey),
                onPressed: _handleImageSelection,
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (_) => _handleSendText(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _handleSendText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CompletionDialog extends StatelessWidget {
  final Score score;
  final VoidCallback onNext;

  const _CompletionDialog({required this.score, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_rounded,
                  color: Colors.green.shade600, size: 40),
            ),
            const SizedBox(height: 24),
            const Text(
              'Lesson Complete',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'Score: ${score.score}/10',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              score.feedback,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.5),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: onNext,
                child: const Text('Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
