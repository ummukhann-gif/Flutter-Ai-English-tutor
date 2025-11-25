import 'dart:async';
import 'dart:io';

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
  XFile? _selectedImage;

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
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    // Auto-connect when entering the screen
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
      // When receiving transcript from voice, we might want to merge if it's a continuous flow,
      // but usually, a new transcript packet implies a new phrase.
      // However, for stability, let's keep merging for voice transcripts unless silence broke it.
      if (!mounted) return;
      if (current != null) _appendMessage(Speaker.user, text, current.id);

      if (_streamingText.isNotEmpty) {
        if (mounted) setState(() => _streamingText = '');
      }
    });

    _outputSub = _live.outputTranscriptStream.listen((text) {
      final current = context.read<AppProvider>().currentLesson;
      if (!mounted) return;
      if (current != null) {
        _appendMessage(Speaker.ai, text, current.id);

        setState(() {
          if (text.contains('LESSON_COMPLETE')) {
            _handleCompletion(text, current);
          } else {
            _streamingText += text;
          }
        });
      }
    });

    _stateSub = _live.connectionStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isReady = state == LiveState.ready || state == LiveState.recording;
        _isMicOn = state == LiveState.recording;
        _liveState = state;

        if (state == LiveState.recording) {
          _streamingText = '';
        }
      });
    });

    _errorSub = _live.errorStream.listen((err) {
      debugPrint('Live error: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $err'), backgroundColor: Colors.red),
      );
    });
  }

  void _appendMessage(Speaker speaker, String text, String lessonId,
      {bool forceNewBubble = false}) {
    if (!mounted) return;

    final provider = context.read<AppProvider>();
    final history =
        List<Conversation>.from(provider.history.conversations[lessonId] ?? []);

    // Only merge if it's the AI speaking (streaming) OR if it's the user speaking via voice (transcript stream).
    // If forceNewBubble is true (e.g. manual send or image), we always create a new bubble.
    if (!forceNewBubble &&
        history.isNotEmpty &&
        history.last.speaker == speaker) {
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
    // If image is selected, send with image
    if (_selectedImage != null) {
      await _sendImageWithText();
      return;
    }

    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    _textController.clear();
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;
    
    await _ensureConnected();
    _appendMessage(Speaker.user, text, lesson.id, forceNewBubble: true);
    _live.sendText(text);
    setState(() => _streamingText = '');
  }

  Future<void> _handleImageSelection() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );

      if (image != null && mounted) {
        setState(() => _selectedImage = image);
        
        // Switch to text mode to show preview
        if (!_isTextMode) {
          setState(() => _isTextMode = true);
        }
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick image: $e')),
        );
      }
    }
  }

  Future<void> _sendImageWithText() async {
    if (_selectedImage == null) return;
    
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description for the image')),
      );
      return;
    }

    try {
      await _ensureConnected();
      
      final bytes = await _selectedImage!.readAsBytes();
      
      // Send image first
      await _live.sendImage(bytes, mimeType: 'image/jpeg');
      
      // Then send text
      await _live.sendText(text);

      final provider = context.read<AppProvider>();
      final lesson = provider.currentLesson;
      if (lesson != null && mounted) {
        _appendMessage(Speaker.user, text, lesson.id, forceNewBubble: true);
      }

      _textController.clear();
      setState(() {
        _selectedImage = null;
        _streamingText = '';
      });
    } catch (e) {
      debugPrint('Error sending image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
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
    return Container(
      color: const Color(0xFFF8F9FA), // Light gray background
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Close button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.black87),
                      onPressed: () => provider.exitLesson(),
                    ),
                  ),
                  
                  // Status indicator
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _liveState == LiveState.ready || _liveState == LiveState.recording
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _liveState == LiveState.ready || _liveState == LiveState.recording
                                ? Colors.green
                                : Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _liveState == LiveState.recording
                              ? 'Listening'
                              : _liveState == LiveState.connecting
                                  ? 'Connecting'
                                  : 'Live',
                          style: TextStyle(
                            color: _liveState == LiveState.ready || _liveState == LiveState.recording
                                ? Colors.green.shade700
                                : Colors.orange.shade700,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Chat button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.black87),
                      onPressed: () => setState(() => _isTextMode = true),
                    ),
                  ),
                ],
              ),
            ),

            // Main content area
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Animated streaming text or placeholder
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        transitionBuilder: (child, animation) {
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.1),
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: _streamingText.isNotEmpty
                            ? Container(
                                key: const ValueKey('streaming'),
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 20,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _streamingText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.black87,
                                    height: 1.5,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              )
                            : Column(
                                key: const ValueKey('placeholder'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isMicOn ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                                    size: 64,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    _isMicOn ? 'Listening...' : 'Hold to speak',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    lesson.title,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom controls
            Padding(
              padding: const EdgeInsets.only(bottom: 48, top: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Camera button
                  _buildModernButton(
                    icon: Icons.camera_alt_rounded,
                    onTap: _handleImageSelection,
                    size: 56,
                  ),

                  // Main mic button
                  Listener(
                    onPointerDown: (_) async {
                      if (_liveState == LiveState.connecting) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Connecting... please wait')),
                          );
                        }
                        return;
                      }

                      HapticFeedback.mediumImpact();
                      await _ensureConnected();
                      await _live.startMicStream();
                      if (mounted) setState(() => _isMicOn = true);
                    },
                    onPointerUp: (_) async {
                      await _live.stopMicStream();
                      if (mounted) setState(() => _isMicOn = false);
                    },
                    onPointerCancel: (_) async {
                      await _live.stopMicStream();
                      if (mounted) setState(() => _isMicOn = false);
                    },
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _isMicOn ? Colors.blue.shade600 : Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: _isMicOn 
                                    ? Colors.blue.withValues(alpha: 0.3)
                                    : Colors.black.withValues(alpha: 0.1),
                                blurRadius: _isMicOn ? 20 + (10 * _pulseController.value) : 15,
                                spreadRadius: _isMicOn ? 2 + (3 * _pulseController.value) : 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            _isMicOn ? Icons.graphic_eq_rounded : Icons.mic_rounded,
                            color: _isMicOn ? Colors.white : Colors.black87,
                            size: 36,
                          ),
                        );
                      },
                    ),
                  ),

                  // Keyboard button
                  _buildModernButton(
                    icon: Icons.keyboard_rounded,
                    onTap: () => setState(() => _isTextMode = true),
                    size: 56,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernButton({
    required IconData icon,
    required VoidCallback onTap,
    required double size,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 15,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.black87,
          size: size * 0.45,
        ),
      ),
    );
  }

  Widget _buildChatView(
      ThemeData theme, Lesson lesson, List<Conversation> history) {
    return Container(
      color: Colors.grey.shade50,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => setState(() {
                    _isTextMode = false;
                    _selectedImage = null;
                  }),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Chat Mode',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        lesson.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Connection status
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _liveState == LiveState.ready || _liveState == LiveState.recording
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _liveState == LiveState.ready || _liveState == LiveState.recording
                              ? Colors.green
                              : Colors.orange,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _liveState == LiveState.ready || _liveState == LiveState.recording
                            ? 'Online'
                            : 'Connecting',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _liveState == LiveState.ready || _liveState == LiveState.recording
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Messages
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

          // Input area
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image preview
                if (_selectedImage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(_selectedImage!.path),
                            height: 120,
                            width: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedImage = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input row
                Row(
                  children: [
                    // Image button
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.add_photo_alternate_rounded,
                          color: Colors.grey.shade700,
                        ),
                        onPressed: _handleImageSelection,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Text input
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _textController,
                          maxLines: null,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: _selectedImage != null
                                ? 'Describe the image...'
                                : 'Type a message...',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onSubmitted: (_) => _handleSendText(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Send button
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF00d4ff), Color(0xFF0099ff)],
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF00d4ff).withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
                        onPressed: _handleSendText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
