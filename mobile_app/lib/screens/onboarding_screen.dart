
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

    final gemini = GeminiService(); 
    
    try {
      final stream = gemini.getOnboardingResponseStream(
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
          print("JSON Parse error: $e");
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
    return jsonDecode(text);
  }

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AppProvider>().history.onboardingConversation;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Ustoz bilan tanishuv'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
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
                  // Show streaming text
                  return ChatBubble(
                    message: Conversation(
                      speaker: Speaker.ai, 
                      text: _streamingText.isEmpty ? '...' : _streamingText, 
                      timestamp: DateTime.now()
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
                      hintText: 'Maqsadlaringiz haqida yozing...',
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

