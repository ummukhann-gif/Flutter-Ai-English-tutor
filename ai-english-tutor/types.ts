
export interface Lesson {
  id: string;
  title: string;
  description: string;
  startingPrompt: string; // The exact first sentence the AI tutor should say.
  tasks: string[]; // A list of steps for the lesson.
  vocabulary: { word: string; translation: string; }[]; // Vocabulary with native translation.
}

export interface Score {
  lessonId: string;
  score: number; // e.g., 0-10
  feedback: string;
  completedAt: string;
}

export interface Conversation {
  speaker: 'user' | 'ai' | 'system';
  text: string;
  timestamp: string;
  attachment?: {
    type: 'image';
    data: string; // Base64 string
    mimeType: string;
  };
}

export interface LanguagePair {
  native: string;
  target: string;
}

export interface LearningHistory {
  scores: Score[];
  conversations: { [lessonId: string]: Conversation[] };
  onboardingConversation?: Conversation[];
}

// Changed from enum to type to allow for dynamic, AI-generated learning paths
export type LearningPath = string;
