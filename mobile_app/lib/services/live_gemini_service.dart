import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:audio_session/audio_session.dart';

import '../models/live_models.dart';

/// Gemini Live Service using flutter_gemini_live approach
class LiveGeminiService {
  LiveGeminiService({
    String? apiKey,
    String? model,
    String? systemInstruction,
  })  : _apiKey = (apiKey ??
                dotenv.env['API_KEY'] ??
                const String.fromEnvironment('API_KEY', defaultValue: ''))
            .trim(),
        _model = model ??
            dotenv.env['GEMINI_LIVE_MODEL'] ??
            const String.fromEnvironment(
              'GEMINI_LIVE_MODEL',
              defaultValue: 'gemini-2.0-flash-exp',
            ),
        _systemInstruction = systemInstruction ??
            dotenv.env['GEMINI_LIVE_SYSTEM_PROMPT'] ??
            'You are a friendly English tutor.' {
    if (_apiKey.isEmpty) {
      debugPrint('CRITICAL: API_KEY is empty. Live features will fail.');
    }
    _initAudio();
  }

  final String _apiKey;
  final String _model;
  final String _systemInstruction;

  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;

  // Audio components
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();
  StreamSubscription<List<int>>? _micSub;

  // State management
  final _inputTranscriptCtrl = StreamController<String>.broadcast();
  final _outputTranscriptCtrl = StreamController<String>.broadcast();
  final _connectionStateCtrl = StreamController<LiveState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();

  static const _silenceThreshold = 500.0;
  static const _apiVersion = 'v1beta';

  bool _isAiSpeaking = false;
  bool _isManualDisconnect = false;

  // Streams
  Stream<String> get inputTranscriptStream => _inputTranscriptCtrl.stream;
  Stream<String> get outputTranscriptStream => _outputTranscriptCtrl.stream;
  Stream<LiveState> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<double> get volumeStream => _volumeCtrl.stream;

  bool get isConnected => _channel != null;

  Future<void> _initAudio() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.videoChat,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.speech,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: true,
      ));

      await _player.initialize(sampleRate: 24000);
      debugPrint('✓ Audio player initialized (24kHz)');

      await _recorder.initialize(sampleRate: 16000);
      debugPrint('✓ Audio recorder initialized (16kHz)');
    } catch (e) {
      debugPrint('❌ Failed to initialize audio: $e');
      _errorCtrl.add('Audio initialization failed: $e');
    }
  }

  Future<void> connect({
    String? systemInstruction,
    String? historyContext,
  }) async {
    if (_channel != null) {
      debugPrint('Already connected');
      return;
    }

    if (_apiKey.isEmpty) {
      _errorCtrl.add('API_KEY is empty');
      _connectionStateCtrl.add(LiveState.disconnected);
      return;
    }

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _errorCtrl.add('Microphone permission denied');
      _connectionStateCtrl.add(LiveState.disconnected);
      return;
    }

    _connectionStateCtrl.add(LiveState.connecting);
    _isManualDisconnect = false;

    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.$_apiVersion.GenerativeService.BidiGenerateContent?key=$_apiKey',
    );

    debugPrint('🔌 Connecting to WebSocket at $uri');

    try {
      final headers = {
        'Content-Type': 'application/json',
        'x-goog-api-key': _apiKey,
        'x-goog-api-client': 'google-genai-sdk/1.28.0 dart/3.8',
        'user-agent': 'google-genai-sdk/1.28.0 dart/3.8',
      };

      final webSocket = await WebSocket.connect(
        uri.toString(),
        headers: headers,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timed out');
        },
      );

      _channel = IOWebSocketChannel(webSocket);

      final setupCompleter = Completer<void>();

      _wsSub = _channel!.stream.listen(
        (data) {
          _handleMessage(data, setupCompleter);
        },
        onError: (error, stackTrace) {
          debugPrint('WS Stream Error: $error');
          if (!setupCompleter.isCompleted) {
            setupCompleter.completeError(error, stackTrace);
          }
          _errorCtrl.add('Connection error: $error');
        },
        onDone: _onDone,
        cancelOnError: true,
      );

      // Send setup message
      final modelName =
          _model.startsWith('models/') ? _model : 'models/$_model';

      final setupMsg = LiveClientMessage(
        setup: LiveClientSetup(
          model: modelName,
          generationConfig: GenerationConfig(
            responseModalities: ['AUDIO'],
            temperature: 0.7,
            speechConfig: {
              'voiceConfig': {
                'prebuiltVoiceConfig': {'voiceName': 'Zephyr'}
              }
            },
          ),
          inputAudioTranscription: {},
          outputAudioTranscription: {},
          systemInstruction: {
            'parts': [
              {
                'text': [
                  systemInstruction ?? _systemInstruction,
                  if (historyContext != null)
                    '\nConversation so far:\n$historyContext'
                ].join('\n')
              }
            ]
          },
        ),
      );

      debugPrint('📤 Sending Setup with model: $modelName');
      _sendMessage(setupMsg);

      await setupCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket setup timed out after 10 seconds');
        },
      );

      _connectionStateCtrl.add(LiveState.ready);

      try {
        await _player.start();
        debugPrint('✓ Audio player started');
      } catch (e) {
        debugPrint('Player start skipped: $e');
      }

      debugPrint('✓ Connection established and ready');
    } catch (e, st) {
      debugPrint('❌ Failed to connect: $e\n$st');
      _errorCtrl.add('Connection failed: $e');
      _connectionStateCtrl.add(LiveState.disconnected);

      await _wsSub?.cancel();
      _wsSub = null;
      await _channel?.sink.close();
      _channel = null;
    }
  }

  void _sendMessage(LiveClientMessage message) {
    if (_channel == null) return;
    try {
      final jsonString = jsonEncode(message.toJson());
      _channel!.sink.add(jsonString);
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  void _handleMessage(dynamic data, Completer<void>? setupCompleter) {
    try {
      final jsonData = data is String ? data : utf8.decode(data as List<int>);

      final jsonMap = jsonDecode(jsonData) as Map<String, dynamic>;
      final msg = LiveServerMessage.fromJson(jsonMap);

      // Setup complete
      if (msg.setupComplete != null) {
        if (setupCompleter != null && !setupCompleter.isCompleted) {
          setupCompleter.complete();
        }
        debugPrint('✓ Setup Complete');
        return;
      }

      // If first message and no setupComplete, consider it success
      if (setupCompleter != null && !setupCompleter.isCompleted) {
        setupCompleter.complete();
      }

      // Server interruption
      if (msg.serverContent?.interrupted == true) {
        _isAiSpeaking = false;
        try {
          _player.stop();
        } catch (e) {
          debugPrint('Error stopping player: $e');
        }
        debugPrint('⚠ AI Interrupted');
        return;
      }

      // Input transcription (User)
      final inputText = msg.serverContent?.inputTranscription?.text;
      if (inputText != null && inputText.isNotEmpty) {
        _inputTranscriptCtrl.add(inputText);
        debugPrint('👤 User: $inputText');
      }

      // Output transcription (AI)
      final outputText = msg.serverContent?.outputTranscription?.text;
      if (outputText != null && outputText.isNotEmpty) {
        _outputTranscriptCtrl.add(outputText);
        debugPrint('🤖 AI: $outputText');
      }

      // Audio output
      final parts = msg.serverContent?.modelTurn?.parts;
      if (parts != null && parts.isNotEmpty) {
        for (final part in parts) {
          final inline = part.inlineData;
          if (inline != null) {
            try {
              final pcm = base64Decode(inline.data);

              try {
                _player.start();
              } catch (_) {}

              if (!_isAiSpeaking) {
                _isAiSpeaking = true;
                debugPrint('🔊 AI started speaking');
              }

              _player.writeChunk(pcm);
            } catch (e) {
              debugPrint('Error processing audio: $e');
            }
          }

          final textPart = part.text;
          if (textPart != null && textPart.isNotEmpty) {
            _outputTranscriptCtrl.add(textPart);
            debugPrint('🤖 AI (text part): $textPart');
          }
        }
      }

      // Turn complete
      if (msg.serverContent?.turnComplete == true) {
        _isAiSpeaking = false;
        debugPrint('✓ Turn Complete');
      }

      // Error handling
      if (msg.error != null) {
        debugPrint('❌ Server error: ${msg.error}');
        _errorCtrl
            .add('Server error: ${msg.error?['message'] ?? 'Unknown error'}');
      }
    } catch (e, st) {
      debugPrint('Error handling message: $e\n$st');
      _errorCtrl.add('Message handling error: $e');
    }
  }

  Future<void> startMicStream() async {
    if (_micSub != null) return;

    if (_channel == null) {
      debugPrint('⚠ No connection, attempting to connect...');
      await connect();
    }

    if (_channel == null) {
      debugPrint('❌ Failed to establish connection');
      _errorCtrl.add('Cannot start recording: not connected');
      return;
    }

    try {
      try {
        await _player.start();
        debugPrint('✓ Audio player started');
      } catch (e) {
        debugPrint('Player already running: $e');
      }

      _micSub = _recorder.audioStream.listen(
        (chunk) {
          try {
            final bytes = Uint8List.fromList(chunk);
            final samples = Int16List.view(bytes.buffer);

            final rms = _calculateRms(samples);
            _volumeCtrl.add(_normalizeVolume(rms));

            if (rms < _silenceThreshold) {
              final rnd = math.Random();
              for (int i = 0; i < samples.length; i++) {
                samples[i] = (rnd.nextBool() ? 1 : -1) * rnd.nextInt(10);
              }
            }

            _sendPcmChunk(bytes);
          } catch (e) {
            debugPrint('Error processing audio chunk: $e');
          }
        },
        onError: (e) {
          debugPrint('Microphone stream error: $e');
          _errorCtrl.add('Microphone error: $e');
        },
        cancelOnError: false,
      );

      await _recorder.start();
      _connectionStateCtrl.add(LiveState.recording);
      debugPrint('🎤 Recording started');
    } catch (e) {
      debugPrint('❌ Failed to start microphone: $e');
      _errorCtrl.add('Failed to start recording: $e');
      _connectionStateCtrl.add(LiveState.ready);
    }
  }

  Future<void> stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    _connectionStateCtrl.add(LiveState.ready);
    debugPrint('🎤 Recording stopped');
  }

  Future<void> interrupt() async {
    if (_isAiSpeaking) {
      try {
        await _player.stop();
        await _player.start();
        _isAiSpeaking = false;
        debugPrint('⚠ User interrupted AI speech');

        if (_channel != null) {
          _sendSilenceKick();
        }
      } catch (e) {
        debugPrint('Error during interrupt: $e');
      }
    }
  }

  void _sendPcmChunk(Uint8List chunk) {
    if (_channel == null) return;

    try {
      final msg = LiveClientMessage(
        realtimeInput: LiveClientRealtimeInput(
          audio:
              Blob(mimeType: 'audio/pcm;rate=16000', data: base64Encode(chunk)),
        ),
      );
      _sendMessage(msg);
    } catch (e) {
      debugPrint('Error sending PCM chunk: $e');
    }
  }

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;

    if (_channel == null) {
      debugPrint('⚠ Not connected, attempting to connect for text send...');
      await connect();
    }
    if (_channel == null) {
      _errorCtrl.add('Not connected');
      return;
    }

    await interrupt();

    try {
      final msg = LiveClientMessage(
        clientContent: LiveClientContent(
          turns: [
            Content(
              role: 'user',
              parts: [Part(text: text.trim())],
            )
          ],
          turnComplete: true,
        ),
      );
      _sendMessage(msg);
      debugPrint('📤 Sent text: ${text.trim()}');
    } catch (e) {
      debugPrint('Error sending text: $e');
      _errorCtrl.add('Failed to send text: $e');
    }
  }

  Future<void> sendImage(Uint8List imageBytes,
      {String mimeType = 'image/jpeg'}) async {
    if (_channel == null || imageBytes.isEmpty) return;

    try {
      final msg = LiveClientMessage(
        realtimeInput: LiveClientRealtimeInput(
          mediaChunks: [
            Blob(mimeType: mimeType, data: base64Encode(imageBytes)),
          ],
        ),
      );
      _sendMessage(msg);
      debugPrint('📤 Sent image (${imageBytes.length} bytes)');

      _sendSilenceKick();
    } catch (e) {
      debugPrint('Error sending image: $e');
      _errorCtrl.add('Failed to send image: $e');
    }
  }

  void _sendSilenceKick() {
    try {
      final samples = Int16List(8000);
      _sendPcmChunk(Uint8List.view(samples.buffer));
    } catch (e) {
      debugPrint('Error sending silence kick: $e');
    }
  }

  double _calculateRms(Int16List samples) {
    if (samples.isEmpty) return 0.0;

    double sum = 0.0;
    for (final s in samples) {
      sum += s * s;
    }

    return math.sqrt(sum / samples.length);
  }

  double _normalizeVolume(double rms) {
    return (rms / 32768.0).clamp(0.0, 1.0);
  }

  Future<void> disconnect() async {
    debugPrint('🔌 Disconnecting...');

    _isManualDisconnect = true;

    try {
      await _micSub?.cancel();
      _micSub = null;

      await _wsSub?.cancel();
      _wsSub = null;

      try {
        await _recorder.stop();
      } catch (e) {
        debugPrint('Recorder stop: $e');
      }

      try {
        await _player.stop();
      } catch (e) {
        debugPrint('Player stop: $e');
      }

      await _channel?.sink.close();
      _channel = null;

      _isAiSpeaking = false;
      _connectionStateCtrl.add(LiveState.disconnected);

      debugPrint('✓ Disconnected');
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
  }

  Future<void> dispose() async {
    debugPrint('🗑️ Disposing LiveGeminiService...');

    await disconnect();

    try {
      await _inputTranscriptCtrl.close();
      await _outputTranscriptCtrl.close();
      await _connectionStateCtrl.close();
      await _errorCtrl.close();
      await _volumeCtrl.close();

      debugPrint('✓ Disposed');
    } catch (e) {
      debugPrint('Error during dispose: $e');
    }
  }

  void _onDone() {
    final ioChannel =
        _channel is IOWebSocketChannel ? _channel as IOWebSocketChannel : null;
    final code = ioChannel?.innerWebSocket?.closeCode;
    final reason = ioChannel?.innerWebSocket?.closeReason;

    debugPrint('🔌 WS Closed. Code: $code, Reason: ${reason ?? "none"}');

    _channel = null;
    _isAiSpeaking = false;
    _connectionStateCtrl.add(LiveState.disconnected);

    if (!_isManualDisconnect) {
      _errorCtrl.add(
          'Connection closed: ${reason ?? "Unknown reason"} (code: $code)');
    }
  }
}

enum LiveState { connecting, ready, recording, disconnected }

extension LiveStateExtension on LiveState {
  String get displayName {
    switch (this) {
      case LiveState.connecting:
        return 'Connecting...';
      case LiveState.ready:
        return 'Ready';
      case LiveState.recording:
        return 'Recording';
      case LiveState.disconnected:
        return 'Disconnected';
    }
  }

  bool get isConnected =>
      this == LiveState.ready || this == LiveState.recording;
}
