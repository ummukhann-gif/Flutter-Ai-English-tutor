
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/app_provider.dart';
import '../models/types.dart';
import '../services/live_gemini_service.dart';
import '../widgets/chat_bubble.dart';

enum TutorMode { live, chat }

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
  TutorMode _mode = TutorMode.live;

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

    // If no history, seed with starting prompt (AI message)
    if (history.isEmpty) {
      provider.updateConversationHistory(lesson.id, [
        Conversation(
          speaker: Speaker.ai,
          text: lesson.startingPrompt,
          timestamp: DateTime.now(),
        )
      ]);
    }

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
      _appendMessage(Speaker.user, text, lesson.id);
    });

    _outputSub = _live.outputTranscriptStream.listen((text) {
      _appendMessage(Speaker.ai, text, lesson.id);
      if (text.contains('LESSON_COMPLETE')) {
        _handleCompletion(text, lesson);
      }
    });

    _stateSub = _live.connectionStateStream.listen((state) {
      setState(() {
        _isReady = state == LiveState.ready || state == LiveState.recording;
      });
    });

    _errorSub = _live.errorStream.listen((err) {
      debugPrint('Live error: $err');
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _appendMessage(Speaker speaker, String text, String lessonId) {
    final provider = context.read<AppProvider>();
    final history = List<Conversation>.from(
        provider.history.conversations[lessonId] ?? []);
    history.add(Conversation(
      speaker: speaker,
      text: text,
      timestamp: DateTime.now(),
    ));
    provider.updateConversationHistory(lessonId, history);
    _scrollToBottom();
  }

  void _handleCompletion(String text, Lesson lesson) async {
    final provider = context.read<AppProvider>();
    final parts = text.split('LESSON_COMPLETE');
    final visibleText = parts[0].trim();
    final rest = parts.length > 1 ? parts[1].trim() : '';
    int scoreVal = 8;
    String feedback = 'Good job!';
    if (rest.isNotEmpty) {
      final lines = rest.split('\n').where((e) => e.trim().isNotEmpty).toList();
      if (lines.isNotEmpty) {
        scoreVal = int.tryParse(lines[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? scoreVal;
      }
      if (lines.length > 1) feedback = lines.sublist(1).join(' ').trim();
    }

    // Replace last AI message with visibleText only
    final history = List<Conversation>.from(
        provider.history.conversations[lesson.id] ?? []);
    if (history.isNotEmpty && history.last.speaker == Speaker.ai) {
      history[history.length - 1] = Conversation(
        speaker: history.last.speaker,
        text: visibleText,
        timestamp: history.last.timestamp,
      );
    }
    final score = Score(
      lessonId: lesson.id,
      score: scoreVal,
      feedback: feedback,
      completedAt: DateTime.now(),
    );
    await provider.updateConversationHistory(lesson.id, history);

    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => _CompletionDialog(score: score, onNext: () {
          Navigator.pop(c);
          provider.completeLesson(score);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return const SizedBox();

    final history = provider.history.conversations[lesson.id] ?? [];
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(lesson.title),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => provider.exitLesson(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ToggleButtons(
              borderRadius: BorderRadius.circular(20),
              isSelected: [
                _mode == TutorMode.live,
                _mode == TutorMode.chat,
              ],
              onPressed: (i) {
                setState(() {
                  if (i == 0) {
                    _mode = TutorMode.live;
                  } else {
                    _mode = TutorMode.chat;
                    if (_isMicOn) {
                      _live.stopMicStream();
                      _isMicOn = false;
                    }
                  }
                });
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.mic_none, size: 16),
                      SizedBox(width: 6),
                      Text('Live'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.chat_bubble_outline, size: 16),
                      SizedBox(width: 6),
                      Text('Chat'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: history.length,
              itemBuilder: (context, index) {
                return ChatBubble(message: history[index]);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                if (_mode == TutorMode.live) ...[
                  IconButton(
                    icon: Icon(_isMicOn ? Icons.mic : Icons.mic_none, color: theme.colorScheme.primary),
                    onPressed: () async {
                      await _ensureConnected();
                      if (_isMicOn) {
                        _live.stopMicStream();
                      } else {
                        await _live.startMicStream();
                      }
                      setState(() {
                        _isMicOn = !_isMicOn;
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                ],
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
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onSubmitted: (_) => _handleSendText(),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
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
                    onPressed: _handleSendText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    await _live.connect(systemInstruction: systemPrompt, historyContext: historyText.isEmpty ? null : historyText);
  }

  @override
  void dispose() {
    _inputSub?.cancel();
    _outputSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _live.stopMicStream();
    _live.dispose();
    super.dispose();
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
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.emoji_events_rounded, size: 40, color: Colors.green),
            ),
            const SizedBox(height: 16),
            Text(
              'Dars yakunlandi!',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Natija: ${score.score}/10',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              score.feedback,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onNext,
              child: const Text('Davom etish'),
            ),
          ],
        ),
      ),
    );
  }
}
