import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

class FirebaseLiveService {
  late LiveGenerativeModel _liveModel;
  LiveSession? _session;

  // Events
  final StreamController<String> _textStreamController = StreamController.broadcast();
  final StreamController<Uint8List> _audioStreamController = StreamController.broadcast();
  final StreamController<bool> _turnCompleteController = StreamController.broadcast();

  Stream<String> get textStream => _textStreamController.stream;
  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<bool> get turnCompleteStream => _turnCompleteController.stream;

  FirebaseLiveService() {
    final firebaseAI = FirebaseAI.googleAI();

    _liveModel = firebaseAI.liveGenerativeModel(
      model: 'gemini-2.0-flash-live-preview-04-09',
      liveGenerationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModalities.audio, ResponseModalities.text],
        speechConfig: SpeechConfig(voiceName: 'Puck'),
      ),
    );
  }

  Future<void> connect(String systemInstruction) async {
    try {
      _session = await _liveModel.connect();
      debugPrint('✅ Firebase Live Connected');

      // Send system instruction as first message
      await _session?.send(
        input: Content.text(systemInstruction),
        turnComplete: true
      );

      _listenToResponses();
    } catch (e) {
      debugPrint('❌ Firebase Connect Error: $e');
      rethrow;
    }
  }

  void _listenToResponses() {
    if (_session == null) return;

    _session!.receive().listen((response) {
      final message = response.message;

      if (message is LiveServerContent) {
        final parts = message.modelTurn?.parts;
        if (parts != null) {
          for (final part in parts) {
            if (part is TextPart) {
              _textStreamController.add(part.text);
            } else if (part is InlineDataPart) {
               _audioStreamController.add(part.bytes);
            }
          }
        }

        if (message.turnComplete == true) {
          _turnCompleteController.add(true);
        }
      }
    }, onError: (e) {
      debugPrint('Error receiving from Firebase: $e');
    }, onDone: () {
      debugPrint('Firebase session closed');
    });
  }

  Future<void> sendText(String text) async {
    if (_session == null) return;
    await _session!.send(input: Content.text(text), turnComplete: true);
  }

  Future<void> sendAudio(List<int> bytes) async {
    if (_session == null) return;

    final uint8Bytes = Uint8List.fromList(bytes);
    final audioPart = InlineDataPart('audio/pcm', uint8Bytes);

    // Use sendAudioRealtime for streaming audio input
    await _session!.sendAudioRealtime(audioPart);
  }

  Future<void> disconnect() async {
    await _session?.close();
    _session = null;
  }

  void dispose() {
    _textStreamController.close();
    _audioStreamController.close();
    _turnCompleteController.close();
    disconnect();
  }
}
