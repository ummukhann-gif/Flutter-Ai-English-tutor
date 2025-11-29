import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_ai/firebase_ai.dart';
import '../models/types.dart';

class GeminiService {
  static final String _apiKey =
      dotenv.env['API_KEY'] ?? const String.fromEnvironment('API_KEY', defaultValue: '');
  static final String _chatModelName = dotenv.env['GEMINI_CHAT_MODEL'] ??
      const String.fromEnvironment('GEMINI_CHAT_MODEL', defaultValue: 'gemini-1.5-flash-latest');
  static final String _planModelName = dotenv.env['GEMINI_PLAN_MODEL'] ??
      const String.fromEnvironment('GEMINI_PLAN_MODEL', defaultValue: 'gemini-1.5-flash-latest');
  static final String _onboardingModelName = dotenv.env['GEMINI_ONBOARDING_MODEL'] ??
      const String.fromEnvironment('GEMINI_ONBOARDING_MODEL', defaultValue: 'gemini-1.5-flash-latest');

  late final GenerativeModel _chatModel;
  late final GenerativeModel _planModel;
  late final GenerativeModel _onboardingModel;
  
  ChatSession? _onboardingSession;

  GeminiService() {
    final firebaseAI = FirebaseAI.googleAI();

    _chatModel = firebaseAI.generativeModel(
      model: _chatModelName,
    );

    _planModel = firebaseAI.generativeModel(
      model: _planModelName,
    );

    _onboardingModel = firebaseAI.generativeModel(
      model: _onboardingModelName,
    );
  }

  Stream<String> getOnboardingResponseStream(
      List<Conversation> chatHistory, LanguagePair languages) async* {
    
    if (_onboardingSession == null || chatHistory.length <= 1) {
       final systemPrompt = '''
        You are a friendly and encouraging AI tutor. Your goal is to have a short, natural conversation with a new user to understand their English learning needs.
        The user's native language is ${languages.native} and they want to learn ${languages.target}.
        You MUST conduct this initial conversation in ${languages.native} to make the user comfortable.
        Start by introducing yourself in ${languages.native} and asking what they want to achieve. Ask about their current level, interests, and goals (e.g., travel, business, exams).
        Keep your messages short and engaging, writing in a simple, friendly tone in ${languages.native}.
        
        When you feel you have enough information to create a personalized learning plan, end your final message with a special token on a new line. The token MUST be in the format:
        ONBOARDING_COMPLETE::{"path": "A descriptive learning path based on the conversation"}

        Example path values (should be in English): "Conversational English for a trip to the USA", "Business English for marketing professionals", "Beginner Uzbek to English focusing on grammar".
    ''';
    
      _onboardingSession = _onboardingModel.startChat(
         history: [
             Content.text(systemPrompt),
             Content.model([TextPart("Tushunarli. Men tayyorman. (Understood. I am ready.)")])
         ]
      );
    }
    
    final lastUserMsg = chatHistory.lastOrNull;
    if (lastUserMsg == null || lastUserMsg.speaker != Speaker.user) {
        yield "";
        return;
    }

    try {
      final response = _onboardingSession!.sendMessageStream(Content.text(lastUserMsg.text));

      await for (final chunk in response) {
        if (chunk.text != null) {
          yield chunk.text!;
        }
      }
    } catch (e) {
      print("Error in streaming onboarding chat: $e");
      yield "I'm having a little trouble connecting right now. Let's try again in a moment.";
      _onboardingSession = null;
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
      final response = await _planModel.generateContent(
        [Content.text(prompt)],
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
                    // requiredProperties removed as optionalProperties defaults to none meaning all are required
                  ),
                ),
              },
              // requiredProperties removed as optionalProperties defaults to none meaning all are required
            ),
          ),
        ),
      );

      if (response.text == null) {
        throw Exception("Empty response from AI");
      }

      final List<dynamic> jsonList = jsonDecode(response.text!);
      return jsonList.map((json) => Lesson.fromJson(json)).toList();
    } catch (e) {
      print("Error generating lesson plan: $e");
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
}
