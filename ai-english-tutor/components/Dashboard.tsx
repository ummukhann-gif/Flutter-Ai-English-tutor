
import React from 'react';
import { Lesson, LearningPath, LearningHistory, Score } from '../types';

interface DashboardProps {
    learningPath: LearningPath;
    lessonPlan: Lesson[];
    history: LearningHistory;
    onStartLesson: (lesson: Lesson) => void;
    onReset: () => void;
}

const Dashboard: React.FC<DashboardProps> = ({ learningPath, lessonPlan, history, onStartLesson, onReset }) => {
    const getLessonScore = (lessonId: string): Score | null => {
        for (let i = history.scores.length - 1; i >= 0; i--) {
            if (history.scores[i].lessonId === lessonId) {
                return history.scores[i];
            }
        }
        return null;
    };

    return (
        <div className="min-h-screen p-6 pb-20 bg-slate-900 font-roboto text-slate-200">
            <div className="max-w-2xl mx-auto">
                <header className="mb-10 pt-6">
                    <h1 className="text-3xl font-bold text-white tracking-tight mb-2">Darslar rejasi</h1>
                    <div className="inline-flex items-center px-3 py-1 rounded-lg bg-indigo-900/30 border border-indigo-500/30 text-indigo-300 text-sm font-medium">
                        {learningPath}
                    </div>
                </header>

                <div className="relative space-y-0 ml-4 border-l-2 border-slate-800 pl-8 py-2">
                    {lessonPlan.map((lesson, index) => {
                        const scoreData = getLessonScore(lesson.id);
                        const isCompleted = scoreData !== null;
                        const isLocked = index > 0 && !getLessonScore(lessonPlan[index - 1].id);
                        const isCurrent = !isLocked && !isCompleted;

                        return (
                            <div key={lesson.id} className="relative mb-10 last:mb-0 group">
                                
                                {/* Timeline Dot */}
                                <div className={`absolute -left-[41px] top-0 w-5 h-5 rounded-full border-4 transition-all duration-300 z-10 box-content
                                    ${isCompleted 
                                        ? 'bg-slate-900 border-green-500' 
                                        : isCurrent 
                                            ? 'bg-indigo-500 border-indigo-900 shadow-[0_0_0_4px_rgba(99,102,241,0.3)]' 
                                            : 'bg-slate-800 border-slate-900'}`}
                                >
                                    {isCompleted && <div className="text-green-500 absolute -right-6 top-0 text-xs font-bold">✓</div>}
                                </div>

                                {/* Card Content */}
                                <div 
                                    onClick={() => !isLocked && onStartLesson(lesson)}
                                    className={`relative rounded-2xl p-5 border transition-all duration-300
                                    ${isLocked 
                                        ? 'bg-slate-800/20 border-slate-800 text-slate-500 cursor-not-allowed' 
                                        : isCompleted
                                            ? 'bg-slate-800/40 border-green-900/50 hover:bg-slate-800/60 cursor-pointer'
                                            : 'bg-indigo-600/10 border-indigo-500/30 hover:bg-indigo-600/20 hover:border-indigo-500/50 hover:shadow-lg cursor-pointer active:scale-[0.99]'
                                    }`}
                                >
                                    <div className="flex justify-between items-start mb-2">
                                        <span className={`text-[10px] font-bold uppercase tracking-widest 
                                            ${isCompleted ? 'text-green-400' : isCurrent ? 'text-indigo-400' : 'text-slate-600'}`}>
                                            {index + 1}-DARS
                                        </span>
                                        {scoreData && (
                                            <span className="text-sm font-bold text-green-400 bg-green-900/20 px-2 py-0.5 rounded">
                                                {scoreData.score}/10
                                            </span>
                                        )}
                                    </div>
                                    
                                    <h3 className={`text-lg font-semibold mb-1 ${isLocked ? 'text-slate-500' : 'text-slate-100'}`}>{lesson.title}</h3>
                                    <p className={`text-sm leading-relaxed ${isLocked ? 'text-slate-600' : 'text-slate-400'}`}>{lesson.description}</p>
                                    
                                    {isCurrent && (
                                        <div className="mt-4">
                                            <button className="bg-indigo-600 text-white text-sm font-medium px-4 py-2 rounded-lg shadow-lg shadow-indigo-500/20">
                                                Boshlash
                                            </button>
                                        </div>
                                    )}
                                </div>
                            </div>
                        );
                    })}
                </div>

                <div className="mt-16 text-center">
                    <button onClick={onReset} className="text-slate-500 hover:text-slate-300 text-sm font-medium transition-colors px-4 py-2 rounded hover:bg-slate-800">
                        Dasturni qayta sozlash
                    </button>
                </div>
            </div>
        </div>
    );
};

export default Dashboard;
