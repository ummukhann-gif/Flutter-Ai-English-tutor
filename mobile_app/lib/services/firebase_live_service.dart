import 'dart:async';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';

class FirebaseLiveService {
  late LiveModel _liveModel;
  LiveSession? _session;

  // Events
  final StreamController<String> _textStreamController = StreamController.broadcast();
  final StreamController<Uint8List> _audioStreamController = StreamController.broadcast();
  final StreamController<bool> _turnCompleteController = StreamController.broadcast();

  Stream<String> get textStream => _textStreamController.stream;
  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  Stream<bool> get turnCompleteStream => _turnCompleteController.stream;

  FirebaseLiveService() {
    // Initialize the model
    // Note: This assumes Firebase.initializeApp() is called in main.dart
    _liveModel = FirebaseAI.googleAI().liveModel(
      modelName: 'gemini-2.0-flash-live-preview-04-09', // Latest model as per docs
      generationConfig: LiveGenerationConfig(
        responseModalities: [ResponseModality.audio, ResponseModality.text],
        speechConfig: SpeechConfig(
          voiceConfig: VoiceConfig(
            prebuiltVoiceConfig: PrebuiltVoiceConfig(voiceName: 'Puck'),
          ),
        ),
      ),
    );
  }

  Future<void> connect(String systemInstruction) async {
    try {
      _session = await _liveModel.connect();
      debugPrint('✅ Firebase Live Connected');

      // Send system instruction as first message
      // Note: Live API doesn't support system instructions in config yet properly in all SDKs,
      // but we can send it as the first text message to set context.
      // Or if the SDK supports it in Connect options (checked docs, it suggests sending initial prompt).
      // We'll send it as text.
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

    // Use the receive stream
    _session!.receive().listen((message) {
      // Handle server content
      final parts = message.modelTurn?.parts;
      if (parts != null) {
        for (final part in parts) {
          if (part is TextPart) {
            _textStreamController.add(part.text);
          } else if (part is InlineDataPart) {
             // Assuming audio/pcm comes as InlineDataPart
             _audioStreamController.add(part.bytes);
          }
        }
      }

      if (message.turnComplete) {
        _turnCompleteController.add(true);
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

    // Convert List<int> to Uint8List
    final uint8Bytes = Uint8List.fromList(bytes);

    // Create InlineDataPart for audio
    final audioPart = InlineDataPart('audio/pcm', uint8Bytes);

    // Send without turnComplete for continuous streaming
    // Or we might need to verify if SDK supports streaming chunk by chunk this way.
    // The docs say: await _session.startMediaStream(mediaChunkStream); for streaming.
    // But we can also send individual chunks.
    await _session!.send(input: Content.multi([audioPart]), turnComplete: false);
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
