import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/types.dart';

class GeminiService {
  // TODO: Replace with your actual API key or use --dart-define=API_KEY=...
  static const String _apiKey =
      String.fromEnvironment('API_KEY', defaultValue: '');

  late final GenerativeModel _model;

  GeminiService() {
    if (_apiKey.isEmpty) {
      print('Warning: API_KEY is not set. AI features will not work.');
    }
    _model = GenerativeModel(
      model:
          'gemini-1.5-flash', // Using flash for speed/cost, or use 'gemini-pro'
      apiKey: _apiKey,
    );
  }

  Stream<String> getOnboardingResponseStream(
      List<Conversation> chatHistory, LanguagePair languages) async* {
    final historyText = chatHistory
        .map((m) =>
            '${m.speaker == Speaker.ai ? 'AI Tutor' : 'User'}: ${m.text}')
        .join('\n');

    final prompt = '''
        You are a friendly and encouraging AI tutor. Your goal is to have a short, natural conversation with a new user to understand their English learning needs.
        The user's native language is ${languages.native} and they want to learn ${languages.target}.
        You MUST conduct this initial conversation in ${languages.native} to make the user comfortable.
        Start by introducing yourself in ${languages.native} and asking what they want to achieve. Ask about their current level, interests, and goals (e.g., travel, business, exams).
        Keep your messages short and engaging, writing in a simple, friendly tone in ${languages.native}.
        
        When you feel you have enough information to create a personalized learning plan, end your final message with a special token on a new line. The token MUST be in the format:
        ONBOARDING_COMPLETE::{"path": "A descriptive learning path based on the conversation"}

        Example path values (should be in English): "Conversational English for a trip to the USA", "Business English for marketing professionals", "Beginner Uzbek to English focusing on grammar".
        
        This is the conversation so far:
        $historyText
    ''';

    try {
      final content = [Content.text(prompt)];
      final response = _model.generateContentStream(content);

      await for (final chunk in response) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      print("Error in streaming onboarding chat: $e");
      yield "I'm having a little trouble connecting right now. Let's try again in a moment.";
    }
  }

  Future<List<Lesson>> generateLessonPlan(String learningPath,
      LearningHistory history, LanguagePair languages) async {
    final historySummary = history.scores.isEmpty
        ? 'None'
        : history.scores.map((s) => '${s.lessonId}: ${s.score}/10').join(', ');

    final prompt = '''
      You are an expert language curriculum planner, a master strategist creating detailed lesson plans for an AI tutor.
      The user is a ${languages.native} speaker who wants to learn ${languages.target}.
      Their learning goal is: "$learningPath".
      Their learning history is: Previous Scores: $historySummary. 
      Use this history to create a new, adaptive lesson plan. If a topic has a low score, re-introduce it or a similar topic. Avoid repeating mastered topics.

      Generate a personalized lesson plan with 5-7 progressive lessons.
      Return the plan as a JSON array. Each lesson object MUST have the following structure:
      1.  "id": A unique short string (e.g., 'topic-1').
      2.  "title": A concise lesson title in English.
      3.  "description": A brief one-sentence description in English.
      4.  "startingPrompt": The EXACT first sentence the AI tutor MUST say to start the lesson. This MUST be in ${languages.native}.
      5.  "tasks": An array of 3-5 strings. These are specific, ordered instructions for the AI tutor to follow during the lesson. These should be in English.
      6.  "vocabulary": An array of objects, each with "word" (in ${languages.target}) and "translation" (in ${languages.native}).

      All text fields except 'startingPrompt' and vocabulary 'translation' must be in English.
    ''';

    try {
      // Create a model specifically for JSON generation
      final jsonModel = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
        generationConfig: GenerationConfig(
          responseMimeType: 'application/json',
          responseSchema: Schema.array(
            items: Schema.object(
              properties: {
                'id': Schema.string(),
                'title': Schema.string(),
                'description': Schema.string(),
                'startingPrompt': Schema.string(),
                'tasks': Schema.array(items: Schema.string()),
                'vocabulary': Schema.array(
                  items: Schema.object(
                    properties: {
                      'word': Schema.string(),
                      'translation': Schema.string(),
                    },
                    requiredProperties: ['word', 'translation'],
                  ),
                ),
              },
              requiredProperties: [
                'id',
                'title',
                'description',
                'startingPrompt',
                'tasks',
                'vocabulary'
              ],
            ),
          ),
        ),
      );

      final response = await jsonModel.generateContent([Content.text(prompt)]);

      if (response.text == null) {
        throw Exception("Empty response from AI");
      }

      final List<dynamic> jsonList = jsonDecode(response.text!);
      return jsonList.map((json) => Lesson.fromJson(json)).toList();
    } catch (e) {
      print("Error generating lesson plan: $e");
      // Fallback plan
      return [
        Lesson(
          id: 'fallback-1',
          title: 'Introduction',
          description: 'Start with the basics.',
          startingPrompt:
              'Assalomu alaykum! Keling, boshlaymiz. Birinchi darsimiz salomlashish haqida.',
          tasks: [
            'Teach "Hello" and "Goodbye"',
            'Ask user to introduce themselves'
          ],
          vocabulary: [VocabularyItem(word: 'Hello', translation: 'Salom')],
        )
      ];
    }
  }

  // Helper for chat during a lesson (TutorView logic)
  Stream<String> getTutorResponseStream(Lesson lesson,
      List<Conversation> chatHistory, LanguagePair languages) async* {
    final historyText = chatHistory
        .map((m) =>
            '${m.speaker == Speaker.ai ? 'AI Tutor' : 'User'}: ${m.text}')
        .join('\n');

    final prompt = '''
      You are a friendly, patient, and effective English tutor.
      Current Lesson: "${lesson.title}"
      Description: "${lesson.description}"
      
      Your Tasks for this lesson (follow these strictly in order):
      ${lesson.tasks.asMap().entries.map((entry) => "${entry.key + 1}. ${entry.value}").join('\n')}
      
      Vocabulary to teach:
      ${lesson.vocabulary.map((v) => "${v.word} (${v.translation})").join(', ')}

      The user speaks ${languages.native} and is learning ${languages.target}.
      
      Rules:
      1. Keep your responses short (1-3 sentences).
      2. Correct the user's mistakes gently but clearly.
      3. Move through the tasks one by one.
      4. Encourage the user.
      5. If the user completes all tasks, end the lesson by saying "LESSON_COMPLETE" on a new line, followed by a score (0-10) and brief feedback JSON.
      Example end format:
      LESSON_COMPLETE
      {"score": 8, "feedback": "Good job with the vocabulary, but watch your verb tenses."}

      Conversation History:
      $historyText
    ''';

    try {
      final response = _model.generateContentStream([Content.text(prompt)]);
      await for (final chunk in response) {
        if (chunk.text != null) yield chunk.text!;
      }
    } catch (e) {
      print("Error in tutor stream: $e");
      yield "Sorry, I lost connection. Can you say that again?";
    }
  }
}
