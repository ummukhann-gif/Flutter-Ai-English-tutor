
import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';

class LoadingScreen extends StatelessWidget {
  final String message;

  const LoadingScreen({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ZoomIn(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Theme.of(context).primaryColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FadeInUp(
              child: Text(
                message,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                'AI siz uchun maxsus reja tuzmoqda...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
