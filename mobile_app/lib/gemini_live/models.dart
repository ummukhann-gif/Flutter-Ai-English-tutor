// Gemini Live API Models
// Based on flutter_gemini_live package

// Enums
enum Modality { text, image, audio }

// Data Classes
class Part {
  final String? text;
  final Blob? inlineData;

  Part({this.text, this.inlineData});

  factory Part.fromJson(Map<String, dynamic> json) {
    return Part(
      text: json['text'] as String?,
      inlineData: json['inlineData'] != null
          ? Blob.fromJson(json['inlineData'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (text != null) map['text'] = text;
    if (inlineData != null) map['inlineData'] = inlineData!.toJson();
    return map;
  }
}

class Blob {
  final String mimeType;
  final String data;

  Blob({required this.mimeType, required this.data});

  factory Blob.fromJson(Map<String, dynamic> json) {
    return Blob(
      mimeType: json['mimeType'] as String,
      data: json['data'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'mimeType': mimeType, 'data': data};
}

class Content {
  final List<Part>? parts;
  final String? role;

  Content({this.parts, this.role});

  factory Content.fromJson(Map<String, dynamic> json) {
    return Content(
      parts: (json['parts'] as List?)
          ?.map((e) => Part.fromJson(e as Map<String, dynamic>))
          .toList(),
      role: json['role'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (parts != null) map['parts'] = parts!.map((e) => e.toJson()).toList();
    if (role != null) map['role'] = role;
    return map;
  }
}

class GenerationConfig {
  final double? temperature;
  final int? topK;
  final double? topP;
  final int? maxOutputTokens;
  final List<String>? responseModalities;
  final Map<String, dynamic>? speechConfig;

  GenerationConfig({
    this.temperature,
    this.topK,
    this.topP,
    this.maxOutputTokens,
    this.responseModalities,
    this.speechConfig,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (temperature != null) map['temperature'] = temperature;
    if (topK != null) map['top_k'] = topK;
    if (topP != null) map['top_p'] = topP;
    if (maxOutputTokens != null) map['max_output_tokens'] = maxOutputTokens;
    if (responseModalities != null) {
      map['response_modalities'] = responseModalities;
    }
    if (speechConfig != null) map['speech_config'] = speechConfig;
    return map;
  }
}

// Client -> Server Messages
class LiveClientSetup {
  final String model;
  final GenerationConfig? generationConfig;
  final Content? systemInstruction;
  final Map<String, dynamic>? inputAudioTranscription;
  final Map<String, dynamic>? outputAudioTranscription;

  LiveClientSetup({
    required this.model,
    this.generationConfig,
    this.systemInstruction,
    this.inputAudioTranscription,
    this.outputAudioTranscription,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'model': model};
    if (generationConfig != null) {
      map['generation_config'] = generationConfig!.toJson();
    }
    if (systemInstruction != null) {
      map['system_instruction'] = systemInstruction!.toJson();
    }
    if (inputAudioTranscription != null) {
      map['input_audio_transcription'] = inputAudioTranscription;
    }
    if (outputAudioTranscription != null) {
      map['output_audio_transcription'] = outputAudioTranscription;
    }
    return map;
  }
}

class LiveClientContent {
  final List<Content>? turns;
  final bool? turnComplete;

  LiveClientContent({this.turns, this.turnComplete});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (turns != null) {
      map['turns'] = turns!.map((e) => e.toJson()).toList();
    }
    if (turnComplete != null) map['turn_complete'] = turnComplete;
    return map;
  }
}

class LiveClientRealtimeInput {
  final Blob? audio;
  final List<Blob>? mediaChunks;

  LiveClientRealtimeInput({this.audio, this.mediaChunks});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (audio != null) map['media_chunks'] = [audio!.toJson()];
    if (mediaChunks != null) {
      map['media_chunks'] = mediaChunks!.map((e) => e.toJson()).toList();
    }
    return map;
  }
}

class LiveClientMessage {
  final LiveClientSetup? setup;
  final LiveClientContent? clientContent;
  final LiveClientRealtimeInput? realtimeInput;

  LiveClientMessage({this.setup, this.clientContent, this.realtimeInput});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (setup != null) map['setup'] = setup!.toJson();
    if (clientContent != null) {
      map['client_content'] = clientContent!.toJson();
    }
    if (realtimeInput != null) {
      map['realtime_input'] = realtimeInput!.toJson();
    }
    return map;
  }
}

// Server -> Client Messages
class Transcription {
  final String? text;
  final bool? finished;

  Transcription({this.text, this.finished});

  factory Transcription.fromJson(Map<String, dynamic> json) {
    return Transcription(
      text: json['text'] as String?,
      finished: json['finished'] as bool?,
    );
  }
}

class LiveServerContent {
  final Content? modelTurn;
  final bool? turnComplete;
  final bool? interrupted;
  final Transcription? inputTranscription;
  final Transcription? outputTranscription;

  LiveServerContent({
    this.modelTurn,
    this.turnComplete,
    this.interrupted,
    this.inputTranscription,
    this.outputTranscription,
  });

  factory LiveServerContent.fromJson(Map<String, dynamic> json) {
    return LiveServerContent(
      modelTurn: json['modelTurn'] != null
          ? Content.fromJson(json['modelTurn'] as Map<String, dynamic>)
          : null,
      turnComplete: json['turnComplete'] as bool?,
      interrupted: json['interrupted'] as bool?,
      inputTranscription: json['inputTranscription'] != null
          ? Transcription.fromJson(
              json['inputTranscription'] as Map<String, dynamic>)
          : null,
      outputTranscription: json['outputTranscription'] != null
          ? Transcription.fromJson(
              json['outputTranscription'] as Map<String, dynamic>)
          : null,
    );
  }
}

class LiveServerMessage {
  final Map<String, dynamic>? setupComplete;
  final LiveServerContent? serverContent;
  final Map<String, dynamic>? error;

  LiveServerMessage({this.setupComplete, this.serverContent, this.error});

  factory LiveServerMessage.fromJson(Map<String, dynamic> json) {
    return LiveServerMessage(
      setupComplete: json['setupComplete'] as Map<String, dynamic>?,
      serverContent: json['serverContent'] != null
          ? LiveServerContent.fromJson(
              json['serverContent'] as Map<String, dynamic>)
          : null,
      error: json['error'] as Map<String, dynamic>?,
    );
  }

  String? get text {
    return serverContent?.modelTurn?.parts
        ?.map((p) => p.text)
        .where((t) => t != null)
        .join('');
  }
}
