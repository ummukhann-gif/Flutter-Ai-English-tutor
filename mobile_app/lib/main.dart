import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'theme/app_theme.dart';
import 'providers/app_provider.dart';
import 'screens/language_selection_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/tutor_screen.dart';
import 'screens/review_screen.dart';
import 'screens/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  // Allow runtime fetching so GoogleFonts doesn't crash if assets are missing.
  GoogleFonts.config.allowRuntimeFetching = true;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
      ],
      child: MaterialApp(
        title: 'AI English Tutor',
        theme: AppTheme.lightTheme,
        home: const AppNavigator(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class AppNavigator extends StatelessWidget {
  const AppNavigator({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppProvider>();

    switch (appState.status) {
      case AppStateStatus.languageSelection:
        return const LanguageSelectionScreen();
      case AppStateStatus.onboarding:
        return const OnboardingScreen();
      case AppStateStatus.generatingPlan:
        return const LoadingScreen(message: 'Reja tuzilmoqda...');
      case AppStateStatus.dashboard:
        return const DashboardScreen();
      case AppStateStatus.lesson:
        return const TutorScreen();
      case AppStateStatus.review:
        return const ReviewScreen();
    }
  }
}
