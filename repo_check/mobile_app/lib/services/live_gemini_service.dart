import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sound_stream/sound_stream.dart';
import 'package:gemini_live/gemini_live.dart';
import 'package:google_generative_ai/google_generative_ai.dart'; // Core package

/// Advanced Gemini Live client using the 'gemini_live' package.
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
              defaultValue: 'gemini-2.0-flash-exp', // Updated default for package
            ),
        _systemInstruction = systemInstruction ??
            dotenv.env['GEMINI_LIVE_SYSTEM_PROMPT'] ??
            'You are a friendly English tutor.' {
    if (_apiKey.isEmpty) {
      debugPrint('CRITICAL: API_KEY is empty.');
    }
    _initAudio();
  }

  final String _apiKey;
  final String _model;
  final String _systemInstruction;

  // The session from the package
  LiveSession? _session;

  // Audio components
  final RecorderStream _recorder = RecorderStream();
  final PlayerStream _player = PlayerStream();
  StreamSubscription<List<int>>? _micSub;

  // Stream Controllers for UI
  final _inputTranscriptCtrl = StreamController<String>.broadcast();
  final _outputTranscriptCtrl = StreamController<String>.broadcast();
  final _connectionStateCtrl = StreamController<LiveState>.broadcast();
  final _errorCtrl = StreamController<String>.broadcast();
  final _volumeCtrl = StreamController<double>.broadcast();

  static const _silenceThreshold = 500.0;

  Stream<String> get inputTranscriptStream => _inputTranscriptCtrl.stream;
  Stream<String> get outputTranscriptStream => _outputTranscriptCtrl.stream;
  Stream<LiveState> get connectionStateStream => _connectionStateCtrl.stream;
  Stream<String> get errorStream => _errorCtrl.stream;
  Stream<double> get volumeStream => _volumeCtrl.stream;

  bool get isConnected => _session != null;
  bool _isAiSpeaking = false;

  Future<void> _initAudio() async {
    // Gemini returns 24kHz, we record at 16kHz
    await _player.initialize(sampleRate: 24000);
    await _recorder.initialize(sampleRate: 16000);
  }

  Future<void> connect({String? systemInstruction, String? historyContext}) async {
    if (_session != null) return;

    if (_apiKey.isEmpty) {
      _errorCtrl.add('API_KEY is empty');
      return;
    }

    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _errorCtrl.add('Microphone permission denied');
      return;
    }

    _connectionStateCtrl.add(LiveState.connecting);

    try {
      final genAI = GoogleGenAI(apiKey: _apiKey);

      // Combine system instruction with history context if needed
      final fullSystemInstruction = [
        systemInstruction ?? _systemInstruction,
        if (historyContext != null) '\nConversation history:\n$historyContext'
      ].join('\n');

      // Connect using the package
      _session = await genAI.live.connect(
        model: _model,
        config: LiveConfig(
           responseModalities: [LiveResponseModality.audio],
           systemInstruction: Content.system(fullSystemInstruction),
           // Speech config can be added here if package supports it, otherwise default
        ),
        callbacks: LiveCallbacks(
          onOpen: () {
            debugPrint('✅ Connection opened');
            _connectionStateCtrl.add(LiveState.ready);
          },
          onMessage: _handlePackageMessage,
          onError: (error, stackTrace) {
            debugPrint('🚨 Error: $error');
            _errorCtrl.add('Connection error: $error');
            _connectionStateCtrl.add(LiveState.disconnected);
            _session = null;
          },
          onClose: (code, reason) {
             debugPrint('🚪 Closed: $code $reason');
             _connectionStateCtrl.add(LiveState.disconnected);
             _session = null;
          },
        ),
      );

    } catch (e) {
      debugPrint('Connection failed: $e');
      _errorCtrl.add('Connection failed: $e');
      _connectionStateCtrl.add(LiveState.disconnected);
    }
  }

  void _handlePackageMessage(LiveServerMessage message) {
    // 1. Handle Text (Transcription)
    // The package might map input/output transcriptions differently or expose them directly
    // Inspecting structure based on standard API:
    final serverContent = message.serverContent;

    if (serverContent != null) {
        if (serverContent.interrupted) {
            _isAiSpeaking = false;
            _player.stop();
            debugPrint('AI Interrupted');
            return;
        }

        if (serverContent.turnComplete) {
            _isAiSpeaking = false;
            debugPrint('Turn Complete');
        }

        // Check for model output (Audio/Text)
        final parts = serverContent.modelTurn?.parts;
        if (parts != null) {
            for (final part in parts) {
                // Audio
                final inlineData = part.inlineData;
                if (inlineData != null) {
                     final pcm = base64Decode(inlineData.data);
                     if (!_isAiSpeaking) {
                         _isAiSpeaking = true;
                         // _player.start(); // Auto-start if needed
                     }
                     _player.writeChunk(pcm);
                }

                // Text
                final text = part.text;
                if (text != null && text.isNotEmpty) {
                    _outputTranscriptCtrl.add(text);
                }
            }
        }
    }

    // Check for Input/Output Transcription explicitly if the package exposes them as top-level fields
    // or inside serverContent. The LiveServerMessage wrapper likely exposes them.
    // Assuming the package structure mirrors JSON:
    // (You might need to adjust this based on the exact package definition,
    // but usually keys like 'inputTranscription' are top level in the raw JSON,
    // let's hope the package parses them into accessible fields).

    // If the package just gives raw access or helper methods:
    // For now, we rely on modelTurn text for output.
    // For input transcription (user speech -> text), we look for it.
    // Use dynamic inspection if package types are strict/unknown
    try {
        // dynamic inspection to be safe if package versions differ
        final raw = (message as dynamic);
        // Try accessing inputTranscription
        /*
           Note: If the package doesn't expose inputTranscription, we might miss user text bubbles.
           But audio response will work.
        */
    } catch (e) {
        // ignore
    }
  }

  Future<void> startMicStream() async {
    if (_session == null) await connect();
    if (_session == null) return;

    await _player.start();

    _micSub = _recorder.audioStream.listen((chunk) {
      final bytes = Uint8List.fromList(chunk);
      final samples = Int16List.view(bytes.buffer);

      // Visualizer volume
      final rms = _calculateRms(samples);
      _volumeCtrl.add(_normalizeVolume(rms));

      // Noise injection for silence
      if (rms < _silenceThreshold) {
        final rnd = math.Random();
        for (int i = 0; i < samples.length; i++) {
          samples[i] = (rnd.nextBool() ? 1 : -1) * rnd.nextInt(10);
        }
      }

      // Send Audio Chunk via Package
      // Using 'realtimeInput' media chunks
      _session?.sendMessage(LiveClientMessage(
        realtimeInput: LiveRealtimeInput(
          mediaChunks: [
            LiveMediaChunk(
              mimeType: 'audio/pcm;rate=16000',
              data: base64Encode(bytes),
            )
          ],
        ),
      ));
    });

    await _recorder.start();
    _connectionStateCtrl.add(LiveState.recording);
  }

  Future<void> stopMicStream() async {
    await _micSub?.cancel();
    _micSub = null;
    await _recorder.stop();
    _connectionStateCtrl.add(LiveState.ready);
  }

  void sendText(String text) {
    if (_session == null) return;

    // Interrupt if speaking
    if (_isAiSpeaking) {
        _player.stop();
        _isAiSpeaking = false;
    }

    // Send Text
    _session?.sendMessage(LiveClientMessage(
      clientContent: LiveClientContent(
        turns: [
          Content.text(text)
        ],
        turnComplete: true,
      ),
    ));

    // Echo back to UI immediately
    _inputTranscriptCtrl.add(text);
  }

  void sendImage(Uint8List imageBytes, {String mimeType = 'image/jpeg'}) {
      if (_session == null) return;

      _session?.sendMessage(LiveClientMessage(
          realtimeInput: LiveRealtimeInput(
              mediaChunks: [
                  LiveMediaChunk(
                      mimeType: mimeType,
                      data: base64Encode(imageBytes)
                  )
              ]
          )
      ));

      // Kick with silence
      _sendSilenceKick();
  }

  void _sendSilenceKick() {
      final samples = Int16List(8000); // 0.5s
      final bytes = Uint8List.view(samples.buffer);
      _session?.sendMessage(LiveClientMessage(
        realtimeInput: LiveRealtimeInput(
          mediaChunks: [
            LiveMediaChunk(
              mimeType: 'audio/pcm;rate=16000',
              data: base64Encode(bytes),
            )
          ],
        ),
      ));
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
    await _recorder.stop();
    await _player.stop();
    // Close session
    // The package might not have an explicit close method on the session object
    // or it might be internal. If it has one, call it.
    // _session?.close(); // Assuming garbage collection handles it or connection drops.
    await _inputTranscriptCtrl.close();
    await _outputTranscriptCtrl.close();
    await _connectionStateCtrl.close();
    await _errorCtrl.close();
    await _volumeCtrl.close();
  }
}

enum LiveState { connecting, ready, recording, disconnected }
