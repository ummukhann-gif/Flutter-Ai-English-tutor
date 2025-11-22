
# AI English Tutor - Mobile App

This is a Flutter mobile application port of the AI English Tutor web app.

## Setup

1.  **Initialize Flutter Project:**
    Since this folder was created manually, you need to generate the platform-specific code (Android, iOS, etc.).
    Run this command inside the `mobile_app` folder:
    ```bash
    flutter create . --org com.example.ai_english_tutor
    ```
    *Note: If `pubspec.yaml` is overwritten, please add the dependencies back from the list below.*

2.  **Dependencies:**
    Ensure your `pubspec.yaml` contains:
    ```yaml
    dependencies:
      flutter:
        sdk: flutter
      google_generative_ai: ^0.4.0
      shared_preferences: ^2.2.2
      flutter_markdown: ^0.6.18+3
      google_fonts: ^6.1.0
      provider: ^6.1.1
      uuid: ^4.3.3
      intl: ^0.19.0
      animate_do: ^3.3.2
      flutter_svg: ^2.0.9
      cupertino_icons: ^1.0.6
    ```

3.  **API Key:**
    You need a Google Gemini API Key. Get one from [Google AI Studio](https://aistudio.google.com/).

## Running the App

Run the app with your API key:

```bash
flutter run --dart-define=API_KEY=YOUR_ACTUAL_API_KEY
```

## Features

-   **Language Selection:** Choose native and target languages.
-   **AI Onboarding:** Chat with AI to set your goals.
-   **Personalized Plan:** AI generates a lesson plan based on your goals.
-   **Interactive Lessons:** Chat-based lessons with specific tasks and vocabulary.
-   **Review & Scoring:** Get feedback and scores (0-10) after each lesson.
-   **Modern UI:** Minimalist, card-based design with animations.
