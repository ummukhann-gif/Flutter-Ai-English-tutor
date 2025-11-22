
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../widgets/chat_bubble.dart';

class ReviewScreen extends StatelessWidget {
  const ReviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final lesson = provider.viewingHistoryLesson;
    if (lesson == null) return const SizedBox();

    final history = provider.history.conversations[lesson.id] ?? [];
    final score = provider.history.scores.firstWhere((s) => s.lessonId == lesson.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(lesson.title),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded),
          onPressed: () => provider.exitLesson(),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                '${score.score}/10',
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: history.length,
              itemBuilder: (context, index) {
                return ChatBubble(message: history[index]);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  provider.exitLesson();
                  provider.startLesson(lesson); // Re-practice
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                ),
                child: const Text('Qayta mashq qilish'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
