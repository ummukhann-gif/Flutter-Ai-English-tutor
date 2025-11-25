import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:audio_session/audio_session.dart';

import '../gemini_live/gemini_live.dart';
import '../models/types.dart';
import '../providers/app_provider.dart';
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

  // Audio components
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();
  StreamSubscription<List<int>>? _micSub;

  // State
  bool _isMicOn = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isTextMode = false;
  bool _isAiSpeaking = false; // AI gapirayotganda true - mikrofon disabled
  XFile? _selectedImage;

  // Gemini Live
  LiveService? _liveService;
  LiveSession? _session;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _initAudio();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }


  Future<void> _initAudio() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.voiceChat,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      ));
      await _player.initialize(sampleRate: 24000);
      await _recorder.initialize(sampleRate: 16000);
    } catch (e) {
      debugPrint('Audio init error: $e');
    }
  }

  Future<void> _connect() async {
    if (_isConnecting || _isConnected) return;

    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;

    setState(() => _isConnecting = true);

    final apiKey = dotenv.env['API_KEY'] ?? 
        const String.fromEnvironment('API_KEY', defaultValue: '');

    _liveService = LiveService(apiKey: apiKey);

    final nativeLang = provider.languages?.native ?? 'Uzbek';
    final targetLang = provider.languages?.target ?? 'English';

    final systemPrompt = '''
You are a strict language tutor teaching a $nativeLang speaker to learn $targetLang.
Keep responses SHORT (1-2 sentences max). Correct mistakes immediately.
Lesson: ${lesson.title}
Tasks: ${lesson.tasks.join('; ')}
When all tasks done, say "LESSON_COMPLETE" with score (1-10) and brief feedback.
''';

    try {
      _session = await _liveService!.connect(
        LiveConnectParameters(
          model: 'gemini-2.5-flash-native-audio-preview-09-2025',
          config: GenerationConfig(
            responseModalities: ['AUDIO'],
            temperature: 0.7,
            speechConfig: {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': 'Zephyr'}
              }
            },
          ),
          systemInstruction: Content(parts: [Part(text: systemPrompt)]),
          callbacks: LiveCallbacks(
            onOpen: () => debugPrint('✅ Connected'),
            onMessage: _handleMessage,
            onError: (e, st) {
              debugPrint('❌ Error: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: $e')),
                );
              }
            },
            onClose: (code, reason) {
              debugPrint('🔌 Closed: $code $reason');
              if (mounted) {
                setState(() {
                  _isConnected = false;
                  _isConnecting = false;
                });
              }
            },
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
        await _player.start();
      }
    } catch (e) {
      debugPrint('Connection failed: $e');
      if (mounted) {
        setState(() => _isConnecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    }
  }


  void _handleMessage(LiveServerMessage message) {
    if (!mounted) return;

    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson == null) return;

    // Handle interruption
    if (message.serverContent?.interrupted == true) {
      _player.stop();
      setState(() => _isAiSpeaking = false);
      return;
    }

    // Handle user transcription
    final inputText = message.serverContent?.inputTranscription?.text;
    if (inputText != null && inputText.isNotEmpty) {
      _appendMessage(Speaker.user, inputText, lesson.id);
    }

    // Handle AI transcription
    final outputText = message.serverContent?.outputTranscription?.text;
    if (outputText != null && outputText.isNotEmpty) {
      _appendMessage(Speaker.ai, outputText, lesson.id);

      if (outputText.contains('LESSON_COMPLETE')) {
        _handleCompletion(outputText, lesson);
      }
    }

    // Handle audio - AI gapirayotganda mikrofon o'chadi
    final parts = message.serverContent?.modelTurn?.parts;
    if (parts != null) {
      for (final part in parts) {
        if (part.inlineData != null) {
          try {
            final pcm = base64Decode(part.inlineData!.data);
            
            // AI gapira boshladi - mikrofon o'chirish
            if (!_isAiSpeaking) {
              _stopMicImmediately(); // Mikrofon darhol o'chadi
              setState(() => _isAiSpeaking = true);
            }
            
            _player.start();
            _player.writeChunk(pcm);
          } catch (e) {
            debugPrint('Audio error: $e');
          }
        }
      }
    }

    // Handle turn complete - AI gapirish tugadi
    if (message.serverContent?.turnComplete == true) {
      setState(() => _isAiSpeaking = false);
    }
  }

  void _appendMessage(Speaker speaker, String text, String lessonId) {
    final provider = context.read<AppProvider>();
    final history = List<Conversation>.from(
        provider.history.conversations[lessonId] ?? []);

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
    _scrollToBottom();
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
        scoreVal =
            int.tryParse(lines[0].replaceAll(RegExp(r'[^0-9]'), '')) ?? 8;
      }
      if (lines.length > 1) feedback = lines.sublist(1).join(' ').trim();
    }

    final score = Score(
      lessonId: lesson.id,
      score: scoreVal,
      feedback: feedback,
      completedAt: DateTime.now(),
    );

    await _stopMicImmediately();
    if (!mounted) return;

    showDialog(
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


  // Mikrofon boshlash - faqat AI gapirmayotganda
  Future<void> _startMic() async {
    // AI gapirayotgan bo'lsa, mikrofon ishlamaydi
    if (_session == null || _isMicOn || _isAiSpeaking) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _isMicOn = true;
      // _streamingText tozalanmaydi - faqat AI gapira boshlaganda tozalanadi
    });

    _micSub = _recorder.audioStream.listen((chunk) {
      // Faqat AI gapirmayotganda audio yuborish
      if (_session != null && !_session!.isClosed && !_isAiSpeaking) {
        _session!.sendAudio(chunk, mimeType: 'audio/pcm;rate=16000');
      }
    });

    await _recorder.start();
  }

  // Mikrofon to'xtatish (normal) - pending bilan
  Future<void> _stopMic() async {
    if (!_isMicOn) return;

    // 1. Pending - mikrofon hali yozadi va yuboradi
    await Future.delayed(const Duration(seconds: 3));

    // 2. Pending tugadi - endi to'xtatish
    await _micSub?.cancel();
    _micSub = null;
    await _recorder.stop();

    // 3. UI yangilash
    if (mounted) setState(() => _isMicOn = false);
  }

  // Mikrofon darhol o'chirish (AI gapira boshlaganda)
  Future<void> _stopMicImmediately() async {
    _micSub?.cancel();
    _micSub = null;
    _recorder.stop();
    if (mounted) setState(() => _isMicOn = false);
  }

  Future<void> _sendText() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _session == null) return;

    _textController.clear();
    _session!.sendText(text);

    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson != null) {
      _appendMessage(Speaker.user, text, lesson.id);
    }
  }

  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (image != null && mounted) {
      setState(() {
        _selectedImage = image;
        _isTextMode = true;
      });
    }
  }

  Future<void> _sendWithImage() async {
    if (_selectedImage == null || _session == null) return;

    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a description')),
      );
      return;
    }

    final bytes = await _selectedImage!.readAsBytes();
    _session!.sendImage(bytes);
    _session!.sendText(text);

    final provider = context.read<AppProvider>();
    final lesson = provider.currentLesson;
    if (lesson != null) {
      _appendMessage(Speaker.user, text, lesson.id);
    }

    _textController.clear();
    setState(() => _selectedImage = null);
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

  @override
  void dispose() {
    _micSub?.cancel();
    _session?.close();
    _recorder.stop();
    _player.stop();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: _isTextMode
            ? _buildChatView(lesson, history, provider)
            : _buildLiveView(lesson, provider),
      ),
    );
  }

  Widget _buildLiveView(Lesson lesson, AppProvider provider) {
    final history = provider.history.conversations[lesson.id] ?? [];
    // Oxirgi AI xabarini olish
    final lastAiMessage = history.isNotEmpty && history.last.speaker == Speaker.ai
        ? history.last.text
        : '';

    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildHeaderButton(Icons.close, () => provider.exitLesson()),
              _buildStatusBadge(),
              _buildHeaderButton(
                Icons.chat_bubble_outline,
                () => setState(() => _isTextMode = true),
              ),
            ],
          ),
        ),

        // Main content
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (lastAiMessage.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Text(
                        lastAiMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        Icon(
                          _isMicOn ? Icons.graphic_eq : Icons.mic_none,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _isMicOn ? 'Listening...' : 'Hold to speak',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          lesson.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
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
              _buildControlButton(Icons.camera_alt, _pickImage),
              _buildMicButton(),
              _buildControlButton(
                Icons.keyboard,
                () => setState(() => _isTextMode = true),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildHeaderButton(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.black87),
        onPressed: onTap,
      ),
    );
  }

  Widget _buildStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isConnecting
                ? 'Connecting'
                : _isConnected
                    ? 'Live'
                    : 'Offline',
            style: TextStyle(
              color: _isConnected
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 15,
            ),
          ],
        ),
        child: Icon(icon, color: Colors.black87, size: 24),
      ),
    );
  }

  Widget _buildMicButton() {
    // AI gapirayotganda mikrofon disabled
    final bool isDisabled = _isAiSpeaking || !_isConnected;
    
    return Listener(
      onPointerDown: isDisabled ? null : (_) => _startMic(),
      onPointerUp: isDisabled ? null : (_) => _stopMic(),
      onPointerCancel: isDisabled ? null : (_) => _stopMic(),
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDisabled
                  ? Colors.grey.shade300 // Disabled holat
                  : _isMicOn
                      ? Colors.blue.shade600
                      : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: isDisabled
                      ? Colors.transparent
                      : _isMicOn
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.black.withOpacity(0.1),
                  blurRadius: _isMicOn ? 20 : 15,
                  spreadRadius: _isMicOn ? 2 : 0,
                ),
              ],
            ),
            child: Icon(
              isDisabled
                  ? Icons.mic_off
                  : _isMicOn
                      ? Icons.graphic_eq
                      : Icons.mic,
              color: isDisabled
                  ? Colors.grey.shade500
                  : _isMicOn
                      ? Colors.white
                      : Colors.black87,
              size: 36,
            ),
          );
        },
      ),
    );
  }


  Widget _buildChatView(
      Lesson lesson, List<Conversation> history, AppProvider provider) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
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
              _buildSmallStatusBadge(),
            ],
          ),
        ),

        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: history.length,
            itemBuilder: (context, index) {
              return ChatBubble(message: history[index]);
            },
          ),
        ),

        // Input
        _buildChatInput(),
      ],
    );
  }

  Widget _buildSmallStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _isConnected ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 11,
              color: _isConnected
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_selectedImage != null) _buildSelectedImagePreview(),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image),
                color: Colors.grey.shade700,
                onPressed: _pickImage,
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: 'Type a message...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) =>
                      _selectedImage != null ? _sendWithImage() : _sendText(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_upward, color: Colors.white),
                  onPressed:
                      _selectedImage != null ? _sendWithImage : _sendText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedImagePreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_selectedImage!.path),
              height: 100,
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
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.white,
                ),
              ),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check,
                color: Colors.green.shade600,
                size: 40,
              ),
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
                fontWeight: FontWeight.w600,
                color: Colors.green.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              score.feedback,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
