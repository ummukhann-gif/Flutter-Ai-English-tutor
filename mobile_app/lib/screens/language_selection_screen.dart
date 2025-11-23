
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/app_provider.dart';
import '../models/types.dart';

class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeInDown(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Text('AI', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.primary)),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('AI English Tutor', style: theme.textTheme.labelLarge),
                        Text('Boshlash uchun tilni tanlang', style: theme.textTheme.bodyMedium),
                      ],
                    )
                  ],
                ),
              ),
              const SizedBox(height: 28),
              FadeInDown(
                delay: const Duration(milliseconds: 120),
                child: Text('Xush kelibsiz 👋', style: theme.textTheme.displayMedium),
              ),
              const SizedBox(height: 8),
              FadeInDown(
                delay: const Duration(milliseconds: 220),
                child: Text(
                  "Qaysi til orqali ingliz tilini o'rganasiz?",
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey[700]),
                ),
              ),
              const SizedBox(height: 28),
              FadeInUp(
                delay: const Duration(milliseconds: 280),
                child: _LanguageCard(
                  flag: '🇺🇸',
                  title: 'Ingliz tili',
                  subtitle: "O'zbek tili orqali",
                  accent: theme.colorScheme.primary,
                  onTap: () {
                    context.read<AppProvider>().setLanguages(
                          LanguagePair(native: 'Uzbek', target: 'English'),
                        );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FadeInUp(
                delay: const Duration(milliseconds: 380),
                child: _LanguageCard(
                  flag: '🇺🇸',
                  title: 'Ingliz tili',
                  subtitle: 'Rus tili orqali',
                  accent: theme.colorScheme.secondary,
                  onTap: () {
                    context.read<AppProvider>().setLanguages(
                          LanguagePair(native: 'Russian', target: 'English'),
                        );
                  },
                ),
              ),
              const SizedBox(height: 16),
              FadeInUp(
                delay: const Duration(milliseconds: 480),
                child: _LanguageCard(
                  flag: '🇺🇸',
                  title: 'Ingliz tili',
                  subtitle: 'Qozoq tili orqali',
                  accent: theme.colorScheme.tertiary,
                  onTap: () {
                    context.read<AppProvider>().setLanguages(
                          LanguagePair(native: 'Kazakh', target: 'English'),
                        );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  final String flag;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.flag,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(0.12),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: accent.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  flag,
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              ],
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: accent,
            ),
          ],
        ),
      ),
    );
  }
}
