
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:animate_do/animate_do.dart';
import '../providers/app_provider.dart';
import '../models/types.dart';

class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              FadeInDown(
                child: Text(
                  'Xush kelibsiz!',
                  style: Theme.of(context).textTheme.displayLarge,
                ),
              ),
              const SizedBox(height: 10),
              FadeInDown(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'Qaysi tilni o\'rganmoqchisiz?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.normal,
                      ),
                ),
              ),
              const SizedBox(height: 60),
              FadeInUp(
                delay: const Duration(milliseconds: 400),
                child: _LanguageCard(
                  flag: '🇺🇸',
                  title: 'Ingliz tili',
                  subtitle: 'O\'zbek tili orqali',
                  onTap: () {
                    context.read<AppProvider>().setLanguages(
                          LanguagePair(native: 'Uzbek', target: 'English'),
                        );
                  },
                ),
              ),
              const SizedBox(height: 20),
              FadeInUp(
                delay: const Duration(milliseconds: 600),
                child: _LanguageCard(
                  flag: '🇷🇺',
                  title: 'Ingliz tili',
                  subtitle: 'Rus tili orqali',
                  onTap: () {
                    context.read<AppProvider>().setLanguages(
                          LanguagePair(native: 'Russian', target: 'English'),
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
  final VoidCallback onTap;

  const _LanguageCard({
    required this.flag,
    required this.title,
    required this.subtitle,
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
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
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
              color: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }
}
