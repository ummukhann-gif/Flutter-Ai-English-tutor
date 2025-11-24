
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import '../providers/app_provider.dart';
import '../models/types.dart';
import '../services/gemini_service.dart';
import '../widgets/chat_bubble.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isAiTyping = false;
  // Temporary storage for streaming response
  String _streamingText = '';
  
  // Keep service instance to maintain chat session state
  final GeminiService _geminiService = GeminiService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startOnboarding();
    });
  }

  void _startOnboarding() {
    final provider = context.read<AppProvider>();
    if (provider.history.onboardingConversation.isEmpty) {
      final initialMessage = Conversation(
        speaker: Speaker.ai,
        text: "Assalomu alaykum! Men sizning shaxsiy AI ingliz tili o'qituvchingiz Kai. Boshlash uchun, o'quv maqsadlaringiz haqida bir oz gapirib bera olasizmi?",
        timestamp: DateTime.now(),
      );
      provider.updateOnboardingConversation([initialMessage]);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100, // Add some buffer
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
    
    // Add user message
    final userMsg = Conversation(
      speaker: Speaker.user,
      text: text,
      timestamp: DateTime.now(),
    );
    
    var currentHistory = List<Conversation>.from(provider.history.onboardingConversation);
    currentHistory.add(userMsg);
    provider.updateOnboardingConversation(currentHistory);
    
    setState(() {
      _isAiTyping = true;
      _streamingText = '';
    });
    _scrollToBottom();

    try {
      final stream = _geminiService.getOnboardingResponseStream(
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
      
      // Check for completion token
      const token = 'ONBOARDING_COMPLETE::';
      if (fullResponse.contains(token)) {
        final parts = fullResponse.split(token);
        final visibleText = parts[0].trim();
        final jsonPart = parts[1];
        
        // Update final history with visible text
        currentHistory.add(Conversation(
          speaker: Speaker.ai,
          text: visibleText,
          timestamp: DateTime.now(),
        ));
        await provider.updateOnboardingConversation(currentHistory);
        
        try {
           final json = _parseJson(jsonPart);
           if (json.containsKey('path')) {
             await Future.delayed(const Duration(seconds: 1));
             if (mounted) {
               provider.completeOnboarding(json['path']);
             }
           }
        } catch (e) {
          debugPrint("JSON Parse error: $e");
          ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Reja tuzishda xatolik bo\'ldi, qaytadan urining.')),
          );
        }
      } else {
        // Normal response
        currentHistory.add(Conversation(
          speaker: Speaker.ai,
          text: fullResponse,
          timestamp: DateTime.now(),
        ));
        await provider.updateOnboardingConversation(currentHistory);
      }

    } catch (e) {
      debugPrint("Error: $e");
       ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text('Aloqa xatosi: $e')),
       );
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
    // Robust parsing: remove markdown blocks if any
    text = text.replaceAll(RegExp(r'^```json\s*', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^```\s*', multiLine: true), '');
    text = text.trim();
    return jsonDecode(text);
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AppProvider>().history.onboardingConversation;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('AI ustoz bilan tanishuv'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Text('Kai', style: theme.textTheme.labelLarge),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.only(bottom: 20, top: 8),
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
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: "Maqsadlaringiz haqida yozing...",
                        fillColor: theme.colorScheme.surface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(28),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      ),
                      onSubmitted: (_) => _handleSend(),
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
                      onPressed: _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
