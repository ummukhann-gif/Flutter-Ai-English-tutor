import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Lightweight Gemini Live (bidi) client for audio in/out over WebSocket.
/// Uses model `gemini-2.5-flash-native-audio-preview-09-2025` by default.
class LiveGeminiService {
  LiveGeminiService({
    String? apiKey,
    String? model,
    String? systemInstruction,
  })  : _apiKey =
            apiKey ?? dotenv.env['API_KEY'] ?? const String.fromEnvironment('API_KEY', defaultValue: ''),
        _model = model ??
            dotenv.env['GEMINI_LIVE_MODEL'] ??
            const String.fromEnvironment(
              'GEMINI_LIVE_MODEL',
              defaultValue: 'models/gemini-2.5-flash-native-audio-preview-09-2025',
            ),
        _systemInstruction = systemInstruction ??
            dotenv.env['GEMINI_LIVE_SYSTEM_PROMPT'] ??
            'You are a friendly English tutor. Be concise and correct mistakes immediately.' {
    _player.setReleaseMode(ReleaseMode.stop);
  }

  final String _apiKey;
  final String _model;
  final String _systemInstruction;

  WebSocketChannel? _channel;
  StreamSubscription<Uint8List>? _micStreamSub;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  final _inputTranscriptCtrl = StreamController<String>.broadcast();
  final _outputTranscriptCtrl = StreamController<String>.broadcast();
  final _connectionStateCtrl = StreamController<LiveState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();

  Stream<String> get inputTranscriptStream => _inputTranscriptCtrl.stream;
  Stream<String> get outputTranscriptStream => _outputTranscriptCtrl.stream;
  Stream<LiveState> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;

  bool get isConnected => _channel != null;
  bool _isClosing = false;

  Future<void> connect({String? systemInstruction, String? historyContext}) async {
    if (_channel != null) return;
    if (_apiKey.isEmpty) {
      _errorCtrl.add('API_KEY is empty');
      return;
    }
    _connectionStateCtrl.add(LiveState.connecting);

    final uri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent'
      '?key=$_apiKey',
    );

    try {
      _channel = WebSocketChannel.connect(uri);
    } catch (e) {
      _errorCtrl.add('WS connect failed: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
      return;
    }

    _channel!.stream.listen(_handleMessage, onDone: _onDone, onError: (e) {
      _errorCtrl.add('WS error: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
    });

    // Send setup
    final setup = {
      'setup': {
        'model': _model,
        'generationConfig': {
          'responseModalities': ['AUDIO'],
          'temperature': 0.7,
        },
        'systemInstruction': {
          'parts': [
            {
              'text': [
                systemInstruction ?? _systemInstruction,
                if (historyContext != null) '\nConversation so far:\n$historyContext'
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

    // Input transcription
    final inputText = msg['serverContent']?['inputTranscription']?['text'];
    if (inputText is String && inputText.isNotEmpty) {
      _inputTranscriptCtrl.add(inputText);
    }

    // Output transcription
    final outputText = msg['serverContent']?['outputTranscription']?['text'];
    if (outputText is String && outputText.isNotEmpty) {
      _outputTranscriptCtrl.add(outputText);
    }

    // Audio output chunk: serverContent.modelTurn.parts[0].inlineData.data
    final parts = msg['serverContent']?['modelTurn']?['parts'];
    if (parts is List && parts.isNotEmpty) {
      final inline = parts.first['inlineData'];
      if (inline != null && inline['data'] != null) {
        final base64Data = inline['data'] as String;
        final pcm = base64Decode(base64Data);
        await _playPcmAsWav(pcm, sampleRate: 24000);
      }
    }
  }

  Future<void> _playPcmAsWav(Uint8List pcmBytes, {int sampleRate = 24000}) async {
    final wavBytes = _pcm16ToWav(pcmBytes, sampleRate: sampleRate);
    await _player.play(BytesSource(wavBytes));
  }

  /// Start microphone stream; sends PCM chunks to WS.
  Future<void> startMicStream({bool injectNoise = true}) async {
    if (_channel == null) {
      await connect();
    }
    if (_channel == null) return;

    final hasPerm = await _recorder.hasPermission();
    if (!hasPerm) {
      _errorCtrl.add('Mic permission denied');
      return;
    }

    final pcmStream = await _recorder.startStream(
      RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _micStreamSub = pcmStream.listen((chunk) {
      final list = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      Uint8List data = list;
      if (injectNoise && _isSilence(data)) {
        data = _injectLowNoise(data.length);
      }
      _sendPcmChunk(data);
    });

    _connectionStateCtrl.add(LiveState.recording);
  }

  void stopMicStream() {
    _micStreamSub?.cancel();
    _micStreamSub = null;
    _recorder.stop();
    _connectionStateCtrl.add(LiveState.ready);
  }

  void _sendPcmChunk(Uint8List chunk) {
    if (_channel == null) return;
    final msg = {
      'realtimeInput': {
        'audio': {
          'data': base64Encode(chunk),
          'mimeType': 'audio/pcm;rate=16000',
        }
      }
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  /// Send plain text into the same live session (for typed input)
  void sendText(String text) {
    if (_channel == null || text.trim().isEmpty) return;
    final msg = {
      'realtimeInput': {
        'text': text.trim(),
      }
    };
    _channel!.sink.add(jsonEncode(msg));
  }

  bool _isSilence(Uint8List chunk) {
    final bytes = chunk.buffer.asInt16List();
    double sum = 0;
    for (final v in bytes) {
      sum += (v * v);
    }
    final rms = sum == 0 ? 0 : math.sqrt(sum / bytes.length);
    return rms < 500; // heuristic threshold
  }

  Uint8List _injectLowNoise(int length) {
    final rnd = math.Random();
    final noise = Int16List(length ~/ 2);
    for (var i = 0; i < noise.length; i++) {
      noise[i] = (rnd.nextInt(200) - 100); // tiny noise
    }
    return noise.buffer.asUint8List();
  }

  Future<void> dispose() async {
    _isClosing = true;
    await _player.dispose();
    await _micStreamSub?.cancel();
    await _recorder.dispose();
    await _channel?.sink.close();
    await _inputTranscriptCtrl.close();
    await _outputTranscriptCtrl.close();
    await _connectionStateCtrl.close();
    await _errorCtrl.close();
  }

  void _onDone() {
    if (_isClosing) return;
    _connectionStateCtrl.add(LiveState.disconnected);
    _channel = null;
  }

  /// Wrap PCM16 mono bytes into a minimal WAV for playback.
  Uint8List _pcm16ToWav(Uint8List pcm, {int sampleRate = 24000}) {
    final byteRate = sampleRate * 2; // 16-bit mono
    final totalDataLen = pcm.length + 36;
    final header = BytesBuilder();
    header.add(ascii.encode('RIFF'));
    header.add(_intToBytes(totalDataLen, 4));
    header.add(ascii.encode('WAVE'));
    header.add(ascii.encode('fmt '));
    header.add(_intToBytes(16, 4)); // Subchunk1Size
    header.add(_intToBytes(1, 2)); // PCM
    header.add(_intToBytes(1, 2)); // Mono
    header.add(_intToBytes(sampleRate, 4));
    header.add(_intToBytes(byteRate, 4));
    header.add(_intToBytes(2, 2)); // Block align
    header.add(_intToBytes(16, 2)); // Bits per sample
    header.add(ascii.encode('data'));
    header.add(_intToBytes(pcm.length, 4));
    header.add(pcm);
    return header.toBytes();
  }

  Uint8List _intToBytes(int value, int bytes) {
    final b = ByteData(bytes);
    if (bytes == 2) {
      b.setInt16(0, value, Endian.little);
    } else {
      b.setInt32(0, value, Endian.little);
    }
    return b.buffer.asUint8List();
  }
}

enum LiveState { connecting, ready, recording, disconnected }
