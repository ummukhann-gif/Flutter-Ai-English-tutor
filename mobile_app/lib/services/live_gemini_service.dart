import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
  })  : _apiKey = apiKey ??
            dotenv.env['API_KEY'] ??
            const String.fromEnvironment('API_KEY', defaultValue: ''),
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

  Stream<String> get inputTranscriptStream => _inputTranscriptCtrl.stream;
  Stream<String> get outputTranscriptStream => _outputTranscriptCtrl.stream;
  Stream<LiveState> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<double> get volumeStream => _volumeCtrl.stream;

  bool get isConnected => _channel != null;
  bool _isAiSpeaking = false;

  Future<void> _initAudio() async {
    await _player.initialize();
    await _recorder.initialize();
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
      _errorCtrl.add('WS error: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
      _channel = null;
    });

    // Send setup
    final setup = {
      'setup': {
        'model': _model,
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
        }
      }
    };
    _channel!.sink.add(jsonEncode(setup));
  }

  void _handleMessage(dynamic raw) async {
    if (raw is! String) return;
    final msg = jsonDecode(raw);

    // Connection ready
    if (msg['setupComplete'] != null) {
      _connectionStateCtrl.add(LiveState.ready);
    }

    // Server Interruption (AI stopped talking because user interrupted)
    if (msg['serverContent']?['interrupted'] == true) {
      _isAiSpeaking = false;
      await _player.stop(); // Clear buffer immediately
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

    // Audio output chunk
    final parts = msg['serverContent']?['modelTurn']?['parts'];
    if (parts is List && parts.isNotEmpty) {
      final inline = parts.first['inlineData'];
      if (inline != null && inline['data'] != null) {
        final base64Data = inline['data'] as String;
        final pcm = base64Decode(base64Data);

        _isAiSpeaking = true;
        // Write raw PCM to player stream
        _player.writeChunk(pcm);
      }
    }

    // Turn complete
    if (msg['serverContent']?['turnComplete'] == true) {
      _isAiSpeaking = false;
    }
  }

  /// Start microphone stream; sends PCM chunks to WS.
  Future<void> startMicStream() async {
    if (_channel == null) await connect();
    if (_channel == null) return;

    // Start player if not running (needed for echo cancellation on some devices, though sound_stream handles this mostly)
    await _player.start();

    _micSub = _recorder.audioStream.listen((chunk) {
      // Calculate volume for visualizer
      _calculateVolume(chunk);

      // Send to Gemini
      _sendPcmChunk(Uint8List.fromList(chunk));
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
    final msg = {
      'input': {
        'audio': {
          'data': base64Encode(chunk),
          'mimeType': 'audio/pcm;rate=16000',
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
      'input': {
        'text': text.trim(),
      }
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  void _calculateVolume(List<int> chunk) {
    double sum = 0;
    // PCM 16-bit is 2 bytes per sample.
    for (int i = 0; i < chunk.length; i += 2) {
      if (i + 1 >= chunk.length) break;
      int val = chunk[i] | (chunk[i + 1] << 8);
      // Convert to signed 16-bit
      if (val > 32767) val -= 65536;
      sum += val * val;
    }
    final rms = math.sqrt(sum / (chunk.length / 2));
    // Normalize roughly 0.0 to 1.0 (assuming max amplitude ~32768)
    final vol = (rms / 32768).clamp(0.0, 1.0);
    _volumeCtrl.add(vol);
  }

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
    _errorCtrl.add('WS closed (${code ?? 'no code'}): ${reason ?? 'no reason'}');
    _connectionStateCtrl.add(LiveState.disconnected);
    _channel = null;
  }
}

enum LiveState { connecting, ready, recording, disconnected }
