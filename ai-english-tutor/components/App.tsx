
import React, { useState, useEffect, useRef } from 'react';
import useLocalStorage from './hooks/useLocalStorage';
import { Lesson, LearningHistory, LearningPath, Score, Conversation, LanguagePair } from './types';
import { generateLessonPlan, getOnboardingResponseStream } from './services/geminiService';
import TutorView from './components/TutorView';
import LanguageSelection from './components/LanguageSelection';
import Dashboard from './components/Dashboard';
import { SendIcon, BackIcon } from './components/icons';

const OnboardingChat: React.FC<{
    conversation: Conversation[];
    setConversation: (updater: Conversation[] | ((val: Conversation[]) => Conversation[])) => void;
    onOnboardingComplete: (path: LearningPath) => void;
    languages: LanguagePair;
}> = ({ conversation, setConversation, onOnboardingComplete, languages }) => {
    const [textInput, setTextInput] = useState('');
    const [isAITyping, setIsAITyping] = useState(false);
    const transcriptEndRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        if (conversation.length === 0) {
            setConversation([{ speaker: 'ai', text: `Assalomu alaykum! Men sizning shaxsiy AI ingliz tili o'qituvchingiz Kai. Boshlash uchun, o'quv maqsadlaringiz haqida bir oz gapirib bera olasizmi?`, timestamp: new Date().toISOString() }]);
        }
    // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);


    const handleSend = async () => {
        if (!textInput.trim() || isAITyping) return;

        const userMessage: Conversation = { speaker: 'user', text: textInput, timestamp: new Date().toISOString() };
        const newConversation = [...conversation, userMessage];
        setConversation(newConversation);
        setTextInput('');
        setIsAITyping(true);

        const aiTypingMessage: Conversation = { speaker: 'ai', text: '', timestamp: new Date().toISOString() };
        setConversation(prev => [...prev, aiTypingMessage]);
        
        let fullResponse = '';
        try {
            const responseStream = getOnboardingResponseStream(newConversation, languages);

            for await (const chunk of responseStream) {
                fullResponse += chunk;
                setConversation(prev => {
                    const newHistory = [...prev];
                    const lastMessage = newHistory[newHistory.length - 1];
                    if (lastMessage && lastMessage.speaker === 'ai') {
                        newHistory[newHistory.length - 1] = { ...lastMessage, text: fullResponse };
                        return newHistory;
                    }
                    return prev;
                });
            }
        } catch (error) {
            console.error("Streaming failed:", error);
            const errorMessage: Conversation = { speaker: 'system', text: 'Sorry, an error occurred.', timestamp: new Date().toISOString() };
            setConversation(prev => {
                const newHistory = [...prev];
                if (newHistory.length > 0 && newHistory[newHistory.length - 1].speaker === 'ai') {
                    newHistory[newHistory.length - 1] = errorMessage;
                    return newHistory;
                }
                return [...newHistory, errorMessage];
            })
        }

        setIsAITyping(false);

        const onboardingToken = 'ONBOARDING_COMPLETE::';
        if (fullResponse.includes(onboardingToken)) {
            const parts = fullResponse.split(onboardingToken);
            const aiMessageText = parts[0].trim();
            const jsonPart = parts[1];
            
            setConversation(prev => {
                const newHistory = [...prev];
                const lastMessage = newHistory[newHistory.length - 1];
                if (lastMessage && lastMessage.speaker === 'ai') {
                     newHistory[newHistory.length - 1] = { ...lastMessage, text: aiMessageText };
                     return newHistory;
                }
                return prev;
            });

            try {
                const { path } = JSON.parse(jsonPart);
                if (path) {
                    setTimeout(() => onOnboardingComplete(path), 1500);
                }
            } catch (e) {
                console.error("Failed to parse onboarding JSON", e);
                const setupErrorMessage: Conversation = { speaker: 'system', text: 'Something went wrong setting up your plan. Let\'s try again.', timestamp: new Date().toISOString() };
                setConversation(prev => [...prev, setupErrorMessage]);
            }
        }
    };

    useEffect(() => {
        transcriptEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }, [conversation]);

    return (
        <div className="flex flex-col h-[100dvh] max-w-lg mx-auto bg-slate-900 font-roboto">
            <header className="text-center pt-6 pb-4">
                <div className="inline-block mb-2 p-2 bg-indigo-500/10 rounded-full">
                    <div className="w-8 h-8 bg-indigo-600 rounded-full flex items-center justify-center text-xs font-bold text-white">AI</div>
                </div>
                <h1 className="text-lg font-bold text-white">Maqsadni aniqlash</h1>
            </header>
            <main className="flex-1 overflow-y-auto p-4 space-y-4">
                {conversation.map((msg, index) => (
                    <div key={index} className={`flex ${msg.speaker === 'user' ? 'justify-end' : 'justify-start'}`}>
                        <div className={`max-w-[85%] px-4 py-3 rounded-2xl text-sm shadow-sm
                            ${msg.speaker === 'user' 
                                ? 'bg-indigo-600 text-white rounded-br-none' 
                                : msg.speaker === 'system' 
                                    ? 'bg-yellow-500/10 text-yellow-500 text-center w-full text-xs' 
                                    : 'bg-slate-800 text-slate-200 border border-slate-700 rounded-bl-none'}`}>
                            <p className="leading-relaxed">{msg.text}</p>
                        </div>
                    </div>
                ))}
                {isAITyping && 
                    <div className="flex justify-start">
                         <div className="px-4 py-3 rounded-2xl bg-slate-800 rounded-bl-none border border-slate-700">
                            <div className="flex items-center space-x-1">
                                <div className="w-1.5 h-1.5 bg-slate-400 rounded-full animate-bounce"></div>
                                <div className="w-1.5 h-1.5 bg-slate-400 rounded-full animate-bounce delay-75"></div>
                                <div className="w-1.5 h-1.5 bg-slate-400 rounded-full animate-bounce delay-150"></div>
                            </div>
                        </div>
                    </div>
                }
                <div ref={transcriptEndRef} />
            </main>
            <footer className="p-4 pb-6 bg-slate-900">
                <div className="flex items-center space-x-2 bg-slate-800 p-2 rounded-full border border-slate-700 shadow-lg">
                    <input
                        type="text"
                        value={textInput}
                        onChange={(e) => setTextInput(e.target.value)}
                        onKeyPress={(e) => e.key === 'Enter' && handleSend()}
                        placeholder="Maqsadlaringiz..."
                        className="flex-1 bg-transparent focus:outline-none px-4 text-white placeholder-slate-500 text-sm"
                        disabled={isAITyping}
                        autoFocus
                    />
                    <button onClick={handleSend} className="p-3 rounded-full bg-indigo-600 text-white hover:bg-indigo-500 disabled:opacity-50 disabled:scale-100 transition-transform active:scale-95" disabled={!textInput.trim() || isAITyping}>
                        <SendIcon className="w-4 h-4" />
                    </button>
                </div>
            </footer>
        </div>
    );
};

const ConversationReview: React.FC<{
    lesson: Lesson;
    conversation: Conversation[];
    score?: Score;
    onBack: () => void;
    onPracticeAgain: () => void;
}> = ({ lesson, conversation, score, onBack, onPracticeAgain }) => {
     const transcriptEndRef = useRef<HTMLDivElement>(null);
     useEffect(() => {
        transcriptEndRef.current?.scrollIntoView({ behavior: 'smooth' });
     }, [conversation]);

    return (
        <div className="flex flex-col h-[100dvh] bg-slate-900 font-roboto">
            <header className="flex items-center justify-between p-4 m-2 rounded-2xl bg-slate-800">
                <button onClick={onBack} className="p-2 rounded-full hover:bg-slate-700 transition">
                    <BackIcon className="w-6 h-6 text-slate-300" />
                </button>
                <div className="text-center">
                    <h1 className="font-bold text-white text-sm">{lesson.title}</h1>
                    <p className="text-xs text-slate-400">Natija</p>
                </div>
                <div className="w-10 text-center font-bold text-lg text-green-400">{score?.score}<span className="text-xs text-slate-500">/10</span></div>
            </header>
            <main className="flex-1 overflow-y-auto p-4 space-y-4">
                 {conversation.map((msg, index) => (
                    <div key={index} className={`flex ${msg.speaker === 'user' ? 'justify-end' : 'justify-start'}`}>
                         <div className={`max-w-[85%] p-3 rounded-2xl text-sm ${
                             msg.speaker === 'user' 
                             ? 'bg-indigo-600/20 border border-indigo-500/30 text-indigo-100' 
                             : msg.speaker === 'system' 
                                ? 'bg-yellow-900/20 text-yellow-400 text-center w-full italic text-xs' 
                                : 'bg-slate-800 border border-slate-700 text-slate-300'
                             }`}>
                             {msg.attachment && (
                                <div className="mb-2">
                                    <img 
                                        src={msg.attachment.data} 
                                        alt="User attachment" 
                                        className="max-w-full h-auto rounded-lg border border-white/10 max-h-48 object-cover"
                                    />
                                </div>
                             )}
                            <p dangerouslySetInnerHTML={{ __html: msg.text }} />
                        </div>
                    </div>
                ))}
                <div ref={transcriptEndRef} />
            </main>
            <footer className="p-6 text-center bg-slate-900">
                <button onClick={onPracticeAgain} className="bg-indigo-600 hover:bg-indigo-500 text-white font-medium py-3 px-8 rounded-full shadow-lg shadow-indigo-900/40 transition-all transform active:scale-95">
                    Qayta mashq qilish ↻
                </button>
            </footer>
        </div>
    );
};

function App() {
    const [languages, setLanguages] = useLocalStorage<LanguagePair | null>('languages', null);
    const [learningPath, setLearningPath] = useLocalStorage<LearningPath | null>('learningPath', null);
    const [lessonPlan, setLessonPlan] = useLocalStorage<Lesson[]>('lessonPlan', []);
    const [history, setHistory] = useLocalStorage<LearningHistory>('learningHistory', { scores: [], conversations: {}, onboardingConversation: [] });
    const [currentLesson, setCurrentLesson] = useState<Lesson | null>(null);
    const [viewingHistory, setViewingHistory] = useState<Lesson | null>(null);
    const [appState, setAppState] = useState<'language_selection' | 'onboarding' | 'generating_plan' | 'dashboard'>('language_selection');

    useEffect(() => {
        if (!languages) {
            setAppState('language_selection');
        } else if (learningPath && lessonPlan.length > 0) {
            setAppState('dashboard');
        } else if (learningPath && lessonPlan.length === 0) {
            setAppState('generating_plan');
        } else {
            setAppState('onboarding');
        }
    }, [languages, learningPath, lessonPlan]);

    useEffect(() => {
        if (appState === 'generating_plan' && learningPath && languages) {
            generateLessonPlan(learningPath, history, languages)
                .then(newPlan => {
                    setLessonPlan(newPlan);
                    setAppState('dashboard');
                });
        }
    }, [appState, learningPath, history, setLessonPlan, languages]);
    
    const handleOnboardingComplete = (path: LearningPath) => {
        setLearningPath(path);
        setLessonPlan([]); // Clear old plan
        setHistory(prev => ({...prev, onboardingConversation: []}));
        setAppState('generating_plan');
    };
    
    const resetApp = () => {
        setLanguages(null);
        setLearningPath(null);
        setLessonPlan([]);
        setHistory({ scores: [], conversations: {}, onboardingConversation: [] });
        setCurrentLesson(null);
        setViewingHistory(null);
        setAppState('language_selection');
    }
    
    const handleLessonComplete = async (score: Score) => {
        const updatedHistory = {
            ...history,
            scores: [...history.scores, score],
        };
        setHistory(updatedHistory);
        setCurrentLesson(null);
    };
    
    const setConversationHistoryForLesson = (lessonId: string, conversationUpdater: Conversation[] | ((val: Conversation[]) => Conversation[])) => {
        setHistory(prev => {
            const oldConversation = prev.conversations[lessonId] || [];
            const newConversation = typeof conversationUpdater === 'function' ? conversationUpdater(oldConversation) : conversationUpdater;
            return { ...prev, conversations: { ...prev.conversations, [lessonId]: newConversation }};
        });
    };

    const setOnboardingConversation = (updater: Conversation[] | ((val: Conversation[]) => Conversation[])) => {
        setHistory(prev => {
            const oldConversation = prev.onboardingConversation || [];
            const newConversation = typeof updater === 'function' ? updater(oldConversation) : updater;
            return { ...prev, onboardingConversation: newConversation };
        });
    };

    const handleStartLesson = (lesson: Lesson) => {
        const isCompleted = history.scores.some(s => s.lessonId === lesson.id);
        if (isCompleted) {
            setViewingHistory(lesson);
        } else {
            setCurrentLesson(lesson);
        }
    };

    if (appState === 'language_selection') {
        return <LanguageSelection onLanguagesSelected={(langs) => {
            setLanguages(langs);
            setAppState('onboarding');
        }} />;
    }

    if (viewingHistory) {
        return <ConversationReview
            lesson={viewingHistory}
            conversation={history.conversations[viewingHistory.id] || []}
            score={history.scores.find(s => s.lessonId === viewingHistory.id)}
            onBack={() => setViewingHistory(null)}
            onPracticeAgain={() => {
                setViewingHistory(null);
                setCurrentLesson(viewingHistory);
            }}
        />
    }

    if (currentLesson && languages) {
        return <TutorView 
            lesson={currentLesson} 
            languages={languages}
            onLessonComplete={handleLessonComplete}
            onExit={() => setCurrentLesson(null)}
            conversationHistory={history.conversations[currentLesson.id] || []}
            setConversationHistory={(updater) => setConversationHistoryForLesson(currentLesson.id, updater)}
        />;
    }

    if (appState === 'onboarding' && languages) {
        return <OnboardingChat
            conversation={history.onboardingConversation || []}
            setConversation={setOnboardingConversation}
            onOnboardingComplete={handleOnboardingComplete}
            languages={languages}
        />;
    }

    if (appState === 'generating_plan') {
         return (
            <div className="flex flex-col items-center justify-center h-[100dvh] p-4 text-center bg-slate-900 font-roboto">
                <div className="bg-slate-800 p-8 rounded-3xl border border-slate-700 max-w-xs w-full shadow-2xl">
                    <div className="w-12 h-12 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin mx-auto mb-6"></div>
                    <h1 className="text-xl font-bold mb-2 text-white">Reja tuzilmoqda...</h1>
                    <p className="text-slate-400 text-sm">Siz uchun maxsus darslik tayyorlanmoqda.</p>
                </div>
            </div>
        );
    }

    if (appState === 'dashboard' && learningPath) {
        return <Dashboard 
            learningPath={learningPath}
            lessonPlan={lessonPlan}
            history={history}
            onStartLesson={handleStartLesson}
            onReset={resetApp}
        />;
    }
    
    return <div className="flex items-center justify-center h-screen text-white bg-slate-900">Loading...</div>;
}

export default App;
