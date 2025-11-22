
import { GoogleGenAI, Type } from "@google/genai";
import type { Lesson, LearningHistory, LearningPath, Conversation, LanguagePair } from '../types';

function getAi() {
  if (!process.env.API_KEY) {
    throw new Error("API_KEY environment variable is not set");
  }
  return new GoogleGenAI({ apiKey: process.env.API_KEY });
}

export async function* getOnboardingResponseStream(chatHistory: Conversation[], languages: LanguagePair): AsyncGenerator<string> {
    const ai = getAi();
    const historyText = chatHistory.map(m => `${m.speaker === 'ai' ? 'AI Tutor' : 'User'}: ${m.text}`).join('\n');
    const prompt = `
        You are a friendly and encouraging AI tutor. Your goal is to have a short, natural conversation with a new user to understand their English learning needs.
        The user's native language is ${languages.native} and they want to learn ${languages.target}.
        You MUST conduct this initial conversation in ${languages.native} to make the user comfortable.
        Start by introducing yourself in ${languages.native} and asking what they want to achieve. Ask about their current level, interests, and goals (e.g., travel, business, exams).
        Keep your messages short and engaging, writing in a simple, friendly tone in ${languages.native}.
        
        When you feel you have enough information to create a personalized learning plan, end your final message with a special token on a new line. The token MUST be in the format:
        ONBOARDING_COMPLETE::{"path": "A descriptive learning path based on the conversation"}

        Example path values (should be in English): "Conversational English for a trip to the USA", "Business English for marketing professionals", "Beginner Uzbek to English focusing on grammar".
        
        This is the conversation so far:
        ${historyText}
    `;
    
    try {
        const responseStream = await ai.models.generateContentStream({
            model: 'gemini-3-pro-preview',
            contents: prompt,
        });
        
        for await (const chunk of responseStream) {
            if (chunk.text) {
                yield chunk.text;
            }
        }
    } catch (error) {
        console.error("Error in streaming onboarding chat:", error);
        yield "I'm having a little trouble connecting right now. Let's try again in a moment.";
    }
}

export const generateLessonPlan = async (learningPath: LearningPath, history: LearningHistory, languages: LanguagePair): Promise<Lesson[]> => {
  const ai = getAi();
  const historySummary = `
    Previous Scores: ${history.scores.map(s => `${s.lessonId}: ${s.score}/10`).join(', ') || 'None'}.
    A low score means the user needs more practice on that topic. A high score means they have mastered it.
    Use this history to create a new, adaptive lesson plan. If a topic has a low score, re-introduce it or a similar topic.
  `;

  const prompt = `
    You are an expert language curriculum planner, a master strategist creating detailed lesson plans for an AI tutor.
    The user is a ${languages.native} speaker who wants to learn ${languages.target}.
    Their learning goal is: "${learningPath}".
    Their learning history is: ${historySummary}. Use this to adapt the plan. Avoid repeating mastered topics (high scores) and revisit difficult ones (low scores).

    Generate a personalized lesson plan with 5-7 progressive lessons.
    Return the plan as a JSON array. Each lesson object MUST have the following structure:
    1.  "id": A unique short string (e.g., 'topic-1').
    2.  "title": A concise lesson title in English.
    3.  "description": A brief one-sentence description in English.
    4.  "startingPrompt": The EXACT first sentence the AI tutor MUST say to start the lesson. This MUST be in ${languages.native}.
    5.  "tasks": An array of 3-5 strings. These are specific, ordered instructions for the AI tutor to follow during the lesson. These should be in English. Example: "Introduce the new vocabulary.", "Ask the user to make a sentence with the word '...', then correct their grammar and pronunciation."
    6.  "vocabulary": An array of objects, each with "word" (in ${languages.target}) and "translation" (in ${languages.native}).

    All text fields except 'startingPrompt' and vocabulary 'translation' must be in English.
  `;

  try {
    const response = await ai.models.generateContent({
      model: 'gemini-3-pro-preview',
      contents: prompt,
      config: {
        responseMimeType: 'application/json',
        responseSchema: {
          type: Type.ARRAY,
          items: {
            type: Type.OBJECT,
            properties: {
              id: { type: Type.STRING },
              title: { type: Type.STRING },
              description: { type: Type.STRING },
              startingPrompt: { type: Type.STRING },
              tasks: { type: Type.ARRAY, items: { type: Type.STRING } },
              vocabulary: {
                type: Type.ARRAY,
                items: {
                  type: Type.OBJECT,
                  properties: {
                    word: { type: Type.STRING },
                    translation: { type: Type.STRING },
                  },
                  required: ['word', 'translation'],
                },
              },
            },
            required: ['id', 'title', 'description', 'startingPrompt', 'tasks', 'vocabulary'],
          },
        },
      },
    });

    const jsonText = response.text;
    const lessonPlan = JSON.parse(jsonText);
    return lessonPlan as Lesson[];
  } catch (error) {
    console.error("Error generating lesson plan:", error);
    // Return a fallback plan in case of an error
    return [{
      id: 'fallback-1',
      title: 'Introduction',
      description: 'Start with the basics.',
      startingPrompt: 'Assalomu alaykum! Keling, boshlaymiz. Birinchi darsimiz salomlashish haqida.',
      tasks: ['Teach "Hello" and "Goodbye"', 'Ask user to introduce themselves'],
      vocabulary: [{ word: 'Hello', translation: 'Salom' }]
    }];
  }
};
