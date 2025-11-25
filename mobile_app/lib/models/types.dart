
class Lesson {
  final String id;
  final String title;
  final String description;
  final String startingPrompt;
  final List<String> tasks;
  final List<VocabularyItem> vocabulary;

  Lesson({
    required this.id,
    required this.title,
    required this.description,
    required this.startingPrompt,
    required this.tasks,
    required this.vocabulary,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      startingPrompt: json['startingPrompt'] as String,
      tasks: (json['tasks'] as List).map((e) => e as String).toList(),
      vocabulary: (json['vocabulary'] as List)
          .map((e) => VocabularyItem.fromJson(e))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startingPrompt': startingPrompt,
      'tasks': tasks,
      'vocabulary': vocabulary.map((e) => e.toJson()).toList(),
    };
  }
}

class VocabularyItem {
  final String word;
  final String translation;

  VocabularyItem({required this.word, required this.translation});

  factory VocabularyItem.fromJson(Map<String, dynamic> json) {
    return VocabularyItem(
      word: json['word'] as String,
      translation: json['translation'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'word': word, 'translation': translation};
}

class Score {
  final String lessonId;
  final int score;
  final String feedback;
  final DateTime completedAt;

  Score({
    required this.lessonId,
    required this.score,
    required this.feedback,
    required this.completedAt,
  });

  factory Score.fromJson(Map<String, dynamic> json) {
    return Score(
      lessonId: json['lessonId'] as String,
      score: json['score'] as int,
      feedback: json['feedback'] as String,
      completedAt: DateTime.parse(json['completedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lessonId': lessonId,
      'score': score,
      'feedback': feedback,
      'completedAt': completedAt.toIso8601String(),
    };
  }
}

enum Speaker { user, ai, system }

class Conversation {
  final Speaker speaker;
  final String text;
  final DateTime timestamp;

  Conversation({
    required this.speaker,
    required this.text,
    required this.timestamp,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      speaker: Speaker.values.firstWhere((e) => e.name == json['speaker']),
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speaker': speaker.name,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class LanguagePair {
  final String native;
  final String target;

  LanguagePair({required this.native, required this.target});

  factory LanguagePair.fromJson(Map<String, dynamic> json) {
    return LanguagePair(
      native: json['native'] as String,
      target: json['target'] as String,
    );
  }

  Map<String, dynamic> toJson() => {'native': native, 'target': target};
}

class LearningHistory {
  final List<Score> scores;
  final Map<String, List<Conversation>> conversations;
  final List<Conversation> onboardingConversation;
  final List<DateTime> studyDates; // Streak uchun - o'qigan kunlar

  LearningHistory({
    required this.scores,
    required this.conversations,
    required this.onboardingConversation,
    this.studyDates = const [],
  });

  // Hozirgi streak hisoblash
  int get currentStreak {
    if (studyDates.isEmpty) return 0;

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // Unique kunlarni olish va tartiblash (eng yangidan eskiga)
    final uniqueDates = studyDates
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));

    int streak = 0;
    DateTime expectedDate = todayOnly;

    for (final date in uniqueDates) {
      // Bugun yoki kutilgan kun bo'lsa
      if (date == expectedDate) {
        streak++;
        expectedDate = expectedDate.subtract(const Duration(days: 1));
      }
      // Kecha bo'lsa (bugun hali o'qilmagan)
      else if (streak == 0 && date == todayOnly.subtract(const Duration(days: 1))) {
        streak++;
        expectedDate = date.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // O'rtacha ball
  double get averageScore {
    if (scores.isEmpty) return 0;
    return scores.map((s) => s.score).reduce((a, b) => a + b) / scores.length;
  }

  factory LearningHistory.fromJson(Map<String, dynamic> json) {
    final conversationsMap = <String, List<Conversation>>{};
    if (json['conversations'] != null) {
      (json['conversations'] as Map<String, dynamic>).forEach((key, value) {
        conversationsMap[key] =
            (value as List).map((e) => Conversation.fromJson(e)).toList();
      });
    }

    return LearningHistory(
      scores:
          (json['scores'] as List?)?.map((e) => Score.fromJson(e)).toList() ??
              [],
      conversations: conversationsMap,
      onboardingConversation: (json['onboardingConversation'] as List?)
              ?.map((e) => Conversation.fromJson(e))
              .toList() ??
          [],
      studyDates: (json['studyDates'] as List?)
              ?.map((e) => DateTime.parse(e as String))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scores': scores.map((e) => e.toJson()).toList(),
      'conversations': conversations.map(
        (key, value) => MapEntry(key, value.map((e) => e.toJson()).toList()),
      ),
      'onboardingConversation':
          onboardingConversation.map((e) => e.toJson()).toList(),
      'studyDates': studyDates.map((e) => e.toIso8601String()).toList(),
    };
  }

  LearningHistory copyWith({
    List<Score>? scores,
    Map<String, List<Conversation>>? conversations,
    List<Conversation>? onboardingConversation,
    List<DateTime>? studyDates,
  }) {
    return LearningHistory(
      scores: scores ?? this.scores,
      conversations: conversations ?? this.conversations,
      onboardingConversation:
          onboardingConversation ?? this.onboardingConversation,
      studyDates: studyDates ?? this.studyDates,
    );
  }
}
