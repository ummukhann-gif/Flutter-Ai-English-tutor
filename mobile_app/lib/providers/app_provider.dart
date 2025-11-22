
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/types.dart';
import '../services/gemini_service.dart';

enum AppStateStatus {
  languageSelection,
  onboarding,
  generatingPlan,
  dashboard,
  lesson,
  review
}

class AppProvider with ChangeNotifier {
  final GeminiService _geminiService = GeminiService();
  
  LanguagePair? _languages;
  String? _learningPath;
  List<Lesson> _lessonPlan = [];
  LearningHistory _history = LearningHistory(scores: [], conversations: {}, onboardingConversation: []);
  
  Lesson? _currentLesson;
  Lesson? _viewingHistoryLesson;
  
  AppStateStatus _status = AppStateStatus.languageSelection;
  bool _isLoading = false;

  // Getters
  LanguagePair? get languages => _languages;
  String? get learningPath => _learningPath;
  List<Lesson> get lessonPlan => _lessonPlan;
  LearningHistory get history => _history;
  Lesson? get currentLesson => _currentLesson;
  Lesson? get viewingHistoryLesson => _viewingHistoryLesson;
  AppStateStatus get status => _status;
  bool get isLoading => _isLoading;

  AppProvider() {
    _loadState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    
    final langJson = prefs.getString('languages');
    if (langJson != null) {
      _languages = LanguagePair.fromJson(jsonDecode(langJson));
    }

    _learningPath = prefs.getString('learningPath');
    
    final planJson = prefs.getString('lessonPlan');
    if (planJson != null) {
      final List<dynamic> decoded = jsonDecode(planJson);
      _lessonPlan = decoded.map((e) => Lesson.fromJson(e)).toList();
    }

    final historyJson = prefs.getString('learningHistory');
    if (historyJson != null) {
      _history = LearningHistory.fromJson(jsonDecode(historyJson));
    }

    _updateStatus();
    notifyListeners();
  }

  void _updateStatus() {
    if (_languages == null) {
      _status = AppStateStatus.languageSelection;
    } else if (_learningPath != null && _lessonPlan.isNotEmpty) {
      _status = AppStateStatus.dashboard;
    } else if (_learningPath != null && _lessonPlan.isEmpty) {
      _status = AppStateStatus.generatingPlan;
      generatePlan(); // Auto-trigger
    } else {
      _status = AppStateStatus.onboarding;
    }
  }

  Future<void> setLanguages(LanguagePair langs) async {
    _languages = langs;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languages', jsonEncode(langs.toJson()));
    _updateStatus();
    notifyListeners();
  }

  Future<void> completeOnboarding(String path) async {
    _learningPath = path;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('learningPath', path);
    
    // Clear old plan
    _lessonPlan = [];
    await prefs.remove('lessonPlan');
    
    // Clear onboarding history from main history if desired, or keep it
    // _history = _history.copyWith(onboardingConversation: []); 
    // await _saveHistory();

    _status = AppStateStatus.generatingPlan;
    notifyListeners();
    await generatePlan();
  }

  Future<void> generatePlan() async {
    if (_learningPath == null || _languages == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      final newPlan = await _geminiService.generateLessonPlan(_learningPath!, _history, _languages!);
      _lessonPlan = newPlan;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lessonPlan', jsonEncode(_lessonPlan.map((e) => e.toJson()).toList()));
      
      _status = AppStateStatus.dashboard;
    } catch (e) {
      print("Error generating plan: $e");
      // Handle error state
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startLesson(Lesson lesson) async {
    final isCompleted = _history.scores.any((s) => s.lessonId == lesson.id);
    if (isCompleted) {
      _viewingHistoryLesson = lesson;
      _status = AppStateStatus.review;
    } else {
      _currentLesson = lesson;
      _status = AppStateStatus.lesson;
    }
    notifyListeners();
  }

  Future<void> completeLesson(Score score) async {
    final updatedScores = List<Score>.from(_history.scores)..add(score);
    _history = _history.copyWith(scores: updatedScores);
    await _saveHistory();
    
    _currentLesson = null;
    _status = AppStateStatus.dashboard;
    notifyListeners();
  }

  Future<void> updateConversationHistory(String lessonId, List<Conversation> conversation) async {
    final updatedConversations = Map<String, List<Conversation>>.from(_history.conversations);
    updatedConversations[lessonId] = conversation;
    _history = _history.copyWith(conversations: updatedConversations);
    await _saveHistory();
    notifyListeners();
  }
  
  Future<void> updateOnboardingConversation(List<Conversation> conversation) async {
    _history = _history.copyWith(onboardingConversation: conversation);
    await _saveHistory();
    notifyListeners();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('learningHistory', jsonEncode(_history.toJson()));
  }

  Future<void> resetApp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    
    _languages = null;
    _learningPath = null;
    _lessonPlan = [];
    _history = LearningHistory(scores: [], conversations: {}, onboardingConversation: []);
    _currentLesson = null;
    _viewingHistoryLesson = null;
    _status = AppStateStatus.languageSelection;
    
    notifyListeners();
  }

  void exitLesson() {
    _currentLesson = null;
    _viewingHistoryLesson = null;
    _status = AppStateStatus.dashboard;
    notifyListeners();
  }
}
