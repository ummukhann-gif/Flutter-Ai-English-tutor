
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/app_provider.dart';
import '../models/types.dart';
import '../services/gemini_service.dart';
import '../widgets/chat_bubble.dart';

class TutorScreen extends StatefulWidget {
  const TutorScreen({super.key});

  @override
  State<TutorScreen> createState() => _TutorScreenState();
}

class _TutorScreenState extends State<TutorScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isAiTyping = false;
  String _streamingText = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLesson();
    });
  }

  void _startLesson() {
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;

    final history = provider.history.conversations[lesson.id] ?? [];
    if (history.isEmpty) {
      final initialMessage = Conversation(
        speaker: Speaker.ai,
        text: lesson.startingPrompt,
        timestamp: DateTime.now(),
      );
      provider.updateConversationHistory(lesson.id, [initialMessage]);
    }
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

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isAiTyping) return;

    _textController.clear();
    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;

    // Add user message
    final userMsg = Conversation(
      speaker: Speaker.user,
      text: text,
      timestamp: DateTime.now(),
    );

    var currentHistory = List<Conversation>.from(
        provider.history.conversations[lesson.id] ?? []);
    currentHistory.add(userMsg);
    provider.updateConversationHistory(lesson.id, currentHistory);

    setState(() {
      _isAiTyping = true;
      _streamingText = '';
    });
    _scrollToBottom();

    final gemini = GeminiService();

    try {
      final stream = gemini.getTutorResponseStream(
        lesson,
        currentHistory,
        provider.languages!,
      );

      await for (final chunk in stream) {
        setState(() {
          _streamingText += chunk;
        });
        _scrollToBottom();
      }

      String fullResponse = _streamingText;
      
      const token = 'LESSON_COMPLETE';
      if (fullResponse.contains(token)) {
        final parts = fullResponse.split(token);
        final visibleText = parts[0].trim();
        final jsonPart = parts.length > 1 ? parts[1].trim() : '';

        if (visibleText.isNotEmpty) {
           currentHistory.add(Conversation(
            speaker: Speaker.ai,
            text: visibleText,
            timestamp: DateTime.now(),
          ));
        }
        await provider.updateConversationHistory(lesson.id, currentHistory);

        if (jsonPart.isNotEmpty) {
          try {
            final json = _parseJson(jsonPart);
            final score = Score(
              lessonId: lesson.id,
              score: json['score'] is int ? json['score'] : int.tryParse(json['score'].toString()) ?? 0,
              feedback: json['feedback'] ?? 'No feedback',
              completedAt: DateTime.now(),
            );
            
            // Show completion dialog
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
          } catch (e) {
            print("Error parsing completion JSON: $e");
          }
        }
      } else {
        currentHistory.add(Conversation(
          speaker: Speaker.ai,
          text: fullResponse,
          timestamp: DateTime.now(),
        ));
        await provider.updateConversationHistory(lesson.id, currentHistory);
      }

    } catch (e) {
      print("Error: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isAiTyping = false;
          _streamingText = '';
        });
        _scrollToBottom();
      }
    }
  }
  
  Map<String, dynamic> _parseJson(String text) {
    text = text.replaceAll('```json', '').replaceAll('```', '').trim();
    // Find the first '{' and last '}'
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start != -1 && end != -1) {
      text = text.substring(start, end + 1);
    }
    return jsonDecode(text);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return const SizedBox();

    final history = provider.history.conversations[lesson.id] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.title),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => provider.exitLesson(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: history.length + (_isAiTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index < history.length) {
                  return ChatBubble(message: history[index]);
                } else {
                  return ChatBubble(
                    message: Conversation(
                      speaker: Speaker.ai,
                      text: _streamingText.isEmpty ? '...' : _streamingText,
                      timestamp: DateTime.now(),
                    ),
                    isTyping: _streamingText.isEmpty,
                  );
                }
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
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
                      fillColor: Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                    ),
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton(
                  onPressed: _handleSend,
                  backgroundColor: Theme.of(context).primaryColor,
                  elevation: 0,
                  child: const Icon(Icons.send_rounded, color: Colors.white),
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
