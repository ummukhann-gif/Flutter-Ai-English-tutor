// Gemini Live Service
// Based on flutter_gemini_live package

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'models.dart';

export 'models.dart';

/// Callbacks for Live API events
class LiveCallbacks {
  final void Function()? onOpen;
  final void Function(LiveServerMessage message)? onMessage;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final void Function(int? closeCode, String? closeReason)? onClose;

  LiveCallbacks({this.onOpen, this.onMessage, this.onError, this.onClose});
}

/// Parameters for connecting to Live API
class LiveConnectParameters {
  final String model;
  final LiveCallbacks callbacks;
  final GenerationConfig? config;
  final Content? systemInstruction;
  final bool enableInputTranscription;
  final bool enableOutputTranscription;

  LiveConnectParameters({
    required this.model,
    required this.callbacks,
    this.config,
    this.systemInstruction,
    this.enableInputTranscription = true,
    this.enableOutputTranscription = true,
  });
}

/// Live API Service
class LiveService {
  final String apiKey;
  final String apiVersion;

  LiveService({
    required this.apiKey,
    this.apiVersion = 'v1beta',
  });

  Future<LiveSession> connect(LiveConnectParameters params) async {
    final websocketUri = Uri.parse(
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.$apiVersion.'
      'GenerativeService.BidiGenerateContent?key=$apiKey',
    );

    debugPrint('🔌 Connecting to WebSocket...');

    try {
      final headers = {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
        'x-goog-api-client': 'google-genai-sdk/1.28.0 dart/3.8',
        'user-agent': 'google-genai-sdk/1.28.0 dart/3.8',
      };

      final webSocket = await WebSocket.connect(
        websocketUri.toString(),
        headers: headers,
      );

      final channel = IOWebSocketChannel(webSocket);
      final session = LiveSession._(channel);
      final setupCompleter = Completer<void>();

      StreamSubscription? streamSubscription;
      streamSubscription = channel.stream.listen(
        (data) {
          final jsonData =
              data is String ? data : utf8.decode(data as List<int>);

          if (!setupCompleter.isCompleted) {
            setupCompleter.complete();
          }

          try {
            final json = jsonDecode(jsonData) as Map<String, dynamic>;
            final message = LiveServerMessage.fromJson(json);
            params.callbacks.onMessage?.call(message);
          } catch (e, st) {
            params.callbacks.onError?.call(e, st);
          }
        },
        onError: (error, stackTrace) {
          if (!setupCompleter.isCompleted) {
            setupCompleter.completeError(error, stackTrace);
          }
          params.callbacks.onError?.call(error, stackTrace);
        },
        onDone: () {
          params.callbacks.onClose?.call(
            channel.closeCode,
            channel.closeReason,
          );
          streamSubscription?.cancel();
        },
        cancelOnError: true,
      );

      params.callbacks.onOpen?.call();

      final modelName = params.model.startsWith('models/')
          ? params.model
          : 'models/${params.model}';

      // Build setup message
      final setupMessage = LiveClientMessage(
        setup: LiveClientSetup(
          model: modelName,
          generationConfig: params.config,
          systemInstruction: params.systemInstruction,
          inputAudioTranscription:
              params.enableInputTranscription ? {} : null,
          outputAudioTranscription:
              params.enableOutputTranscription ? {} : null,
        ),
      );

      session.sendMessage(setupMessage);

      await setupCompleter.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('WebSocket setup timed out');
        },
      );

      debugPrint('✅ Connected to Gemini Live');
      return session;
    } catch (e) {
      debugPrint('❌ Failed to connect: $e');
      rethrow;
    }
  }
}

/// Live Session for sending messages
class LiveSession {
  final WebSocketChannel _channel;

  LiveSession._(this._channel);

  bool get isClosed => _channel.closeCode != null;

  void sendMessage(LiveClientMessage message) {
    if (isClosed) {
      debugPrint('⚠️ Cannot send: channel closed');
      return;
    }
    final jsonString = jsonEncode(message.toJson());
    _channel.sink.add(jsonString);
  }

  void sendText(String text) {
    final message = LiveClientMessage(
      clientContent: LiveClientContent(
        turns: [
          Content(parts: [Part(text: text)], role: 'user'),
        ],
        turnComplete: true,
      ),
    );
    sendMessage(message);
  }

  void sendAudio(List<int> audioBytes, {String mimeType = 'audio/pcm'}) {
    final base64Audio = base64Encode(audioBytes);
    final message = LiveClientMessage(
      realtimeInput: LiveClientRealtimeInput(
        audio: Blob(mimeType: mimeType, data: base64Audio),
      ),
    );
    sendMessage(message);
  }

  void sendImage(List<int> imageBytes, {String mimeType = 'image/jpeg'}) {
    final base64Image = base64Encode(imageBytes);
    final message = LiveClientMessage(
      realtimeInput: LiveClientRealtimeInput(
        mediaChunks: [Blob(mimeType: mimeType, data: base64Image)],
      ),
    );
    sendMessage(message);
  }

  Future<void> close() async {
    await _channel.sink.close();
  }
}
