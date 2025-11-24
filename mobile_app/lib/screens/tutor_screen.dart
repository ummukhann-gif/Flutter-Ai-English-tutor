import 'dart:async';

import 'package:flutter/material.dart';
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

class _TutorScreenState extends State<TutorScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isMicOn = false;
  bool _isReady = false;
  bool _isTextMode = false;
  LiveState _liveState = LiveState.disconnected;

  late final LiveGeminiService _live;
  StreamSubscription<String>? _inputSub;
  StreamSubscription<String>? _outputSub;
  StreamSubscription<LiveState>? _stateSub;
  StreamSubscription<String>? _errorSub;

  @override
  void initState() {
    super.initState();
    _live = LiveGeminiService();
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

    final systemPrompt = '''
You are a strict, professional language tutor ("ustoz") teaching a ${provider.languages?.native} speaker to learn ${provider.languages?.target}.
Lesson title: ${lesson.title}
Tasks: ${lesson.tasks.join('; ')}
Vocabulary: ${lesson.vocabulary.map((v) => '${v.word} (${v.translation})').join(', ')}
If user is silent or says "I don't know", immediately teach and make them repeat. Keep replies concise. Explain in ${provider.languages?.native} when needed, encourage speaking in ${provider.languages?.target}.
When lesson ends, say "LESSON_COMPLETE" on a new line, then score (1-10) and brief feedback.
''';

    await _live.connect(
      systemInstruction: systemPrompt,
      historyContext: historyText.isEmpty ? null : historyText,
    );

    _inputSub = _live.inputTranscriptStream.listen((text) {
      final current = context.read<AppProvider>().currentLesson;
      if (current != null) _appendMessage(Speaker.user, text, current.id);
    });

    _outputSub = _live.outputTranscriptStream.listen((text) {
      final current = context.read<AppProvider>().currentLesson;
      if (current != null) {
        _appendMessage(Speaker.ai, text, current.id);
        if (text.contains('LESSON_COMPLETE')) {
          _handleCompletion(text, current);
        }
      }
    });

    _stateSub = _live.connectionStateStream.listen((state) {
      setState(() {
        _isReady = state == LiveState.ready || state == LiveState.recording;
        _isMicOn = state == LiveState.recording;
        _liveState = state;
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
    final history = List<Conversation>.from(
        provider.history.conversations[lessonId] ?? []);

    // Check if we should append to existing message or create new one
    // For streaming responses, we append. For new messages, we create.
    if (history.isNotEmpty && history.last.speaker == speaker) {
      // Append to existing message (streaming)
      final last = history.last;
      history[history.length - 1] = Conversation(
        speaker: last.speaker,
        text: last.text + text, // APPEND, not replace!
        timestamp: last.timestamp,
      );
    } else {
      // New message from different speaker
      history.add(
        Conversation(speaker: speaker, text: text, timestamp: DateTime.now()),
      );
    }

    provider.updateConversationHistory(lessonId, history);
    
    // Scroll to bottom after a short delay to ensure UI updates
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
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;
    final history = provider.history.conversations[lesson.id] ?? [];
    final historyText = history
        .map((m) => '${m.speaker == Speaker.ai ? 'Tutor' : 'User'}: ${m.text}')
        .join('\n');
    final systemPrompt = '''
You are a strict, professional language tutor ("ustoz") teaching a ${provider.languages?.native} speaker to learn ${provider.languages?.target}.
Lesson title: ${lesson.title}
Tasks: ${lesson.tasks.join('; ')}
Vocabulary: ${lesson.vocabulary.map((v) => '${v.word} (${v.translation})').join(', ')}
If user is silent or says "I don't know", immediately teach and make them repeat. Keep replies concise. Explain in ${provider.languages?.native} when needed, encourage speaking in ${provider.languages?.target}.
When lesson ends, say "LESSON_COMPLETE" on a new line, then score (1-10) and brief feedback.
''';
    await _live.connect(
      systemInstruction: systemPrompt,
      historyContext: historyText.isEmpty ? null : historyText,
    );
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

  Widget _statusPill(ThemeData theme) {
    final pillColor = switch (_liveState) {
      LiveState.ready || LiveState.recording => Colors.green,
      LiveState.connecting => Colors.orange,
      LiveState.disconnected => Colors.grey,
    };
    final label = switch (_liveState) {
      LiveState.recording => 'Recording',
      LiveState.ready => 'Ready',
      LiveState.connecting => 'Connecting',
      LiveState.disconnected => 'Disconnected',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: pillColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pillColor,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  Widget _buildLiveView(
      ThemeData theme, Lesson lesson, AppProvider provider) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new),
                  onPressed: () => provider.exitLesson(),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _isTextMode = true),
                  child: const Text('Chat'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text('You: Student',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
          const SizedBox(height: 4),
          Text('Tutor: AI Ustoz',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, fontSize: 20)),
          const SizedBox(height: 24),
          _statusPill(theme),
          const SizedBox(height: 12),
          Text(
            _isReady ? 'Hold to Speak' : 'Connecting...',
            style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTapDown: (_) async {
              if (!_isReady) return;
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                color: Colors.blueAccent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.blueAccent.withOpacity(0.35),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _isMicOn ? 160 : 140,
                height: _isMicOn ? 160 : 140,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isMicOn ? Icons.mic : Icons.mic_none,
                  size: 64,
                  color: Colors.blueAccent.shade700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text('Live tutor',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              onPressed: () => provider.exitLesson(),
              child: const Text('End Conversation'),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 12,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text('I\'m Stuck',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.black87)),
                Text('Word Bank',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatView(
      ThemeData theme, Lesson lesson, List<Conversation> history) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () => context.read<AppProvider>().exitLesson(),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lesson.title, style: theme.textTheme.titleLarge),
                    Text('Text chat',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.grey)),
                  ],
                ),
              ),
              _statusPill(theme),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => setState(() => _isTextMode = false),
                child: const Text('Live'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(12),
            itemCount: history.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: history[index]);
            },
          ),
        ),
        _chatInput(theme),
      ],
    );
  }

  Widget _chatInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                hintText: 'Javobingizni yozing...',
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(28),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
              onSubmitted: (_) => _handleSendText(),
              enabled: _isReady,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: _isReady ? _handleSendText : null,
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
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events, color: Colors.green, size: 36),
            ),
            const SizedBox(height: 12),
            Text('Lesson Complete!', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Score: ${score.score}/10',
                style: theme.textTheme.headlineSmall?.copyWith(color: Colors.green)),
            const SizedBox(height: 12),
            Text(score.feedback,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext,
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
