import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Advanced Gemini Live client using raw PCM streams for low-latency audio.
class LiveGeminiService {
  LiveGeminiService({
    String? apiKey,
    String? model,
    String? systemInstruction,
  })  : _apiKey = (apiKey ??
            dotenv.env['API_KEY'] ??
            const String.fromEnvironment('API_KEY', defaultValue: '')).trim(),
        _model = model ??
            dotenv.env['GEMINI_LIVE_MODEL'] ??
            const String.fromEnvironment(
              'GEMINI_LIVE_MODEL',
              defaultValue:
                  'models/gemini-2.5-flash-native-audio-preview-09-2025',
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

  // SoundStream components (defaults are 16k mono on most devices)
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();

  StreamSubscription<List<int>>? _micSub;
  StreamSubscription<dynamic>? _wsSub;

  final _inputTranscriptCtrl = StreamController<String>.broadcast();
  final _outputTranscriptCtrl = StreamController<String>.broadcast();
  final _connectionStateCtrl = StreamController<LiveState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast(); // For visualizer
  static const _silenceThreshold = 500.0; // RMS under this triggers noise injection

  Stream<String> get inputTranscriptStream => _inputTranscriptCtrl.stream;
  Stream<String> get outputTranscriptStream => _outputTranscriptCtrl.stream;
  Stream<LiveState> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<double> get volumeStream => _volumeCtrl.stream;

  bool get isConnected => _channel != null;
  bool _isAiSpeaking = false;

  Future<void> _initAudio() async {
    // Gemini returns 24 kHz audio; we send 16 kHz
    await _player.initialize(sampleRate: 24000);
    await _recorder.initialize(sampleRate: 16000);
  }

  Future<void> connect(
      {String? systemInstruction, String? historyContext}) async {
    if (_channel != null) return;
    if (_apiKey.isEmpty) {
      _errorCtrl.add('API_KEY is empty');
      return;
    }

    // Request permissions first
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _errorCtrl.add('Microphone permission denied');
      return;
    }

    _connectionStateCtrl.add(LiveState.connecting);

    // The BidiGenerateContent endpoint
    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=$_apiKey',
    );

    try {
      _channel = IOWebSocketChannel.connect(
        uri,
        connectTimeout: const Duration(seconds: 10),
        pingInterval: const Duration(seconds: 20),
      );
    } catch (e) {
      _errorCtrl.add('WS connect failed: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
      return;
    }

    _wsSub = _channel!.stream.listen(_handleMessage, onDone: _onDone,
        onError: (e, st) {
      debugPrint('WS Stream Error: $e');
      _errorCtrl.add('WS error: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
      _channel = null;
    });

    // Send setup
    // Correct Model format: models/model-name
    // Ensure the model variable has 'models/' prefix if it's not already there.
    final modelName = _model.startsWith('models/') ? _model : 'models/$_model';

    final setup = {
      'setup': {
        'model': modelName,
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'temperature': 0.7,
          'speechConfig': {
            'voiceConfig': {
              'prebuiltVoiceConfig': {'voiceName': 'Zephyr'}
            }
          }
        },
        'systemInstruction': {
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
        // Enable transcription with empty config objects (defaults)
        'inputAudioTranscription': {},
        'outputAudioTranscription': {},
      }
    };
    debugPrint('Sending Setup: $setup');
    _channel!.sink.add(jsonEncode(setup));
  }

  void _handleMessage(dynamic raw) async {
    if (raw is! String) return;
    final msg = jsonDecode(raw);
    
    // Log message keys for debugging
    // debugPrint('Received WS Message: ${msg.keys}');

    // Connection ready
    if (msg['setupComplete'] != null) {
      _connectionStateCtrl.add(LiveState.ready);
      debugPrint('Setup Complete');
    }

    // Server Interruption (AI stopped talking because user interrupted)
    if (msg['serverContent']?['interrupted'] == true) {
      _isAiSpeaking = false;
      await _player.stop(); // Clear buffer immediately
      debugPrint('AI Interrupted');
      // Don't clear transcript, just stop audio
      return;
    }

    // Input transcription (User)
    final inputText = msg['serverContent']?['inputTranscription']?['text'];
    if (inputText is String && inputText.isNotEmpty) {
      _inputTranscriptCtrl.add(inputText);
    }

    // Output transcription (AI)
    final outputText = msg['serverContent']?['outputTranscription']?['text'];
    if (outputText is String && outputText.isNotEmpty) {
      _outputTranscriptCtrl.add(outputText);
    }

    // Audio output handling
    // IMPORTANT: Iterate through ALL parts.
    // Sometimes the model sends text parts (e.g. empty thoughts) before audio parts.
    final parts = msg['serverContent']?['modelTurn']?['parts'];
    if (parts is List && parts.isNotEmpty) {
      for (final part in parts) {
         // Check for Audio
         final inline = part['inlineData'];
         if (inline != null && inline['data'] != null) {
            final base64Data = inline['data'] as String;
            final pcm = base64Decode(base64Data);

            if (!_isAiSpeaking) {
               _isAiSpeaking = true;
               // Ensure player is running
               // _player.start(); 
            }
            
            // Write raw PCM to player stream
            _player.writeChunk(pcm);
         }
         
         // Check for Text (Fallback if outputTranscription is missing/delayed)
         final textPart = part['text'];
         if (textPart is String && textPart.isNotEmpty) {
             _outputTranscriptCtrl.add(textPart);
         }
      }
    }

    // Turn complete
    if (msg['serverContent']?['turnComplete'] == true) {
      _isAiSpeaking = false;
      debugPrint('Turn Complete');
    }
  }

  /// Start microphone stream; sends PCM chunks to WS.
  Future<void> startMicStream() async {
    if (_channel == null) await connect();
    if (_channel == null) return;

    // Start player if not running (needed for echo cancellation on some devices, though sound_stream handles this mostly)
    await _player.start();

    _micSub = _recorder.audioStream.listen((chunk) {
      final bytes = Uint8List.fromList(chunk);
      final samples = Int16List.view(bytes.buffer);

      // Volume for visualizer
      final rms = _calculateRms(samples);
      _volumeCtrl.add(_normalizeVolume(rms));

      // Active noise injection: keep stream alive during silence
      if (rms < _silenceThreshold) {
        final rnd = math.Random();
        for (int i = 0; i < samples.length; i++) {
          samples[i] = (rnd.nextBool() ? 1 : -1) * rnd.nextInt(10);
        }
      }

      // Send to Gemini
      _sendPcmChunk(bytes);
    });

    await _recorder.start();
    _connectionStateCtrl.add(LiveState.recording);
  }

  void stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder.stop();
    _connectionStateCtrl.add(LiveState.ready);
  }

  void interrupt() {
    // If user manually interrupts (e.g. taps screen), stop AI audio
    if (_isAiSpeaking) {
      _player.stop(); // Clear buffer
      _player.start(); // Restart stream for future chunks
      _isAiSpeaking = false;
      // Optionally send an empty text to signal interruption to server,
      // but usually sending audio is enough.
    }
  }

  void _sendPcmChunk(Uint8List chunk) {
    if (_channel == null) return;
    
    // Correct format: realtimeInput -> audio -> data (Blob)
    final msg = {
      'realtimeInput': {
        'audio': {
          'mimeType': 'audio/pcm;rate=16000',
          'data': base64Encode(chunk),
        }
      }
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  void sendText(String text) {
    if (_channel == null || text.trim().isEmpty) return;

    // If sending text, we should interrupt AI speech first
    interrupt();

    final msg = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text.trim()}
            ],
          }
        ],
        'turnComplete': true
      }
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  void sendImage(Uint8List imageBytes, {String mimeType = 'image/jpeg'}) {
    if (_channel == null || imageBytes.isEmpty) return;
    
    // For live interaction, sending image as realtimeInput allows the model to "see" it immediately
    // akin to video frames. 
    final msg = {
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': mimeType,
            'data': base64Encode(imageBytes),
          }
        ]
      }
    };
    _channel!.sink.add(jsonEncode(msg));
    _sendSilenceKick();
  }

  void _sendSilenceKick() {
    // 0.5s of silence at 16kHz keeps the stream alive / nudges response
    final samples = Int16List(8000); // 8000 samples = 0.5s
    _sendPcmChunk(Uint8List.view(samples.buffer));
  }

  double _calculateRms(Int16List samples) {
    if (samples.isEmpty) return 0;
    double sum = 0;
    for (final s in samples) {
      sum += s * s;
    }
    return math.sqrt(sum / samples.length);
  }

  double _normalizeVolume(double rms) => (rms / 32768).clamp(0.0, 1.0);

  Future<void> dispose() async {
    await _micSub?.cancel();
    await _wsSub?.cancel();
    await _recorder.stop();
    await _player.stop();
    await _channel?.sink.close();
    await _inputTranscriptCtrl.close();
    await _outputTranscriptCtrl.close();
    await _connectionStateCtrl.close();
    await _errorCtrl.close();
    await _volumeCtrl.close();
  }

  void _onDone() {
    final ioChannel = _channel is IOWebSocketChannel
        ? _channel as IOWebSocketChannel
        : null;
    final code = ioChannel?.innerWebSocket?.closeCode;
    final reason = ioChannel?.innerWebSocket?.closeReason;
    debugPrint('WS Closed. Code: $code, Reason: $reason');
    _errorCtrl.add('WS closed (${code ?? 'no code'}): ${reason ?? 'no reason'}');
    _connectionStateCtrl.add(LiveState.disconnected);
    _channel = null;
  }
}

enum LiveState { connecting, ready, recording, disconnected }
