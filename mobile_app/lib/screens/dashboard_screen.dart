
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/app_provider.dart';
import '../models/types.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final plan = provider.lessonPlan;
    final history = provider.history;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mening Rejam',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              provider.learningPath ?? '',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.grey),
            onPressed: () {
              // Confirm reset
              showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Qayta boshlash'),
                  content: const Text('Barcha natijalar o\'chiriladi. Rostdan ham qayta boshlamoqchimisiz?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const Text('Yo\'q'),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.pop(c);
                        context.read<AppProvider>().resetApp();
                      },
                      child: const Text('Ha', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: plan.length,
        itemBuilder: (context, index) {
          final lesson = plan[index];
          final score = history.scores.firstWhere(
            (s) => s.lessonId == lesson.id,
            orElse: () => Score(lessonId: '', score: -1, feedback: '', completedAt: DateTime(1900)),
          );
          final isCompleted = score.score != -1;
          final isLocked = index > 0 && !history.scores.any((s) => s.lessonId == plan[index - 1].id);
          
          // Allow viewing history even if locked (though logic says only next is unlocked)
          // Actually, let's strictly follow: 
          // - Completed: Green check, click to review.
          // - Current (First uncompleted): Play button, click to start.
          // - Locked: Lock icon, disabled.
          
          final isCurrent = !isCompleted && !isLocked;

          return FadeInUp(
            delay: Duration(milliseconds: index * 100),
            child: _LessonCard(
              lesson: lesson,
              isCompleted: isCompleted,
              isLocked: isLocked,
              isCurrent: isCurrent,
              score: isCompleted ? score.score : null,
              onTap: () {
                if (isLocked) return;
                context.read<AppProvider>().startLesson(lesson);
              },
            ),
          );
        },
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isLocked;
  final bool isCurrent;
  final int? score;
  final VoidCallback onTap;

  const _LessonCard({
    required this.lesson,
    required this.isCompleted,
    required this.isLocked,
    required this.isCurrent,
    this.score,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: isCurrent 
            ? Border.all(color: Theme.of(context).primaryColor, width: 2)
            : Border.all(color: Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildIcon(context),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isLocked ? Colors.grey : Colors.black87,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lesson.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (isCompleted && score != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$score/10',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon(BuildContext context) {
    if (isCompleted) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.green.shade100,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check_rounded, color: Colors.green),
      );
    } else if (isLocked) {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.lock_rounded, color: Colors.grey),
      );
    } else {
      return Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.play_arrow_rounded, color: Colors.white),
      );
    }
  }
}
