// lib/models/live_models.dart

// Enums
enum Modality {
  TEXT,
  IMAGE,
  AUDIO,
}

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
  final String data; // Base64 encoded string

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
    if (topK != null) map['topK'] = topK;
    if (topP != null) map['topP'] = topP;
    if (maxOutputTokens != null) map['maxOutputTokens'] = maxOutputTokens;
    if (responseModalities != null)
      map['responseModalities'] = responseModalities;
    if (speechConfig != null) map['speechConfig'] = speechConfig;
    return map;
  }
}

// --- Live API Specific Models ---

// Client -> Server
class LiveClientSetup {
  final String model;
  final GenerationConfig? generationConfig;
  final Map<String, dynamic>? systemInstruction;
  final List<dynamic>? tools;

  LiveClientSetup({
    required this.model,
    this.generationConfig,
    this.systemInstruction,
    this.tools,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'model': model};
    if (generationConfig != null)
      map['generationConfig'] = generationConfig!.toJson();
    if (systemInstruction != null) map['systemInstruction'] = systemInstruction;
    if (tools != null) map['tools'] = tools;
    return map;
  }
}

class LiveClientContent {
  final List<Content>? turns;
  final bool? turnComplete;

  LiveClientContent({this.turns, this.turnComplete});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (turns != null) map['turns'] = turns!.map((e) => e.toJson()).toList();
    if (turnComplete != null) map['turnComplete'] = turnComplete;
    return map;
  }
}

class LiveClientRealtimeInput {
  final Blob? audio;
  final List<Blob>? mediaChunks;

  LiveClientRealtimeInput({this.audio, this.mediaChunks});

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (audio != null) map['audio'] = audio!.toJson();
    if (mediaChunks != null)
      map['mediaChunks'] = mediaChunks!.map((e) => e.toJson()).toList();
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
    if (clientContent != null) map['clientContent'] = clientContent!.toJson();
    if (realtimeInput != null) map['realtimeInput'] = realtimeInput!.toJson();
    return map;
  }
}

// Server -> Client
class LiveServerMessage {
  final Map<String, dynamic>? setupComplete;
  final LiveServerContent? serverContent;
  final Map<String, dynamic>? error;

  LiveServerMessage({
    this.setupComplete,
    this.serverContent,
    this.error,
  });

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

class Transcription {
  final String? text;

  Transcription({this.text});

  factory Transcription.fromJson(Map<String, dynamic> json) {
    return Transcription(text: json['text'] as String?);
  }
}
