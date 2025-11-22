
import React, { useState } from 'react';
import { LanguagePair } from '../types';

interface LanguageSelectionProps {
  onLanguagesSelected: (languages: LanguagePair) => void;
}

const availableLanguages = [
  { code: 'Uzbek', name: 'Oʻzbekcha', flag: '🇺🇿' },
  { code: 'English', name: 'English', flag: '🇺🇸' },
  { code: 'Russian', name: 'Русский', flag: '🇷🇺' },
];

const LanguageSelection: React.FC<LanguageSelectionProps> = ({ onLanguagesSelected }) => {
  const [nativeLang, setNativeLang] = useState('');
  const [targetLang, setTargetLang] = useState('');

  const handleStart = () => {
    if (nativeLang && targetLang) {
      onLanguagesSelected({ native: nativeLang, target: targetLang });
    }
  };

  return (
    <div className="min-h-[100dvh] flex items-center justify-center p-4 bg-slate-900 font-roboto">
      <div className="w-full max-w-md">
        
        <div className="bg-slate-800 rounded-3xl p-8 shadow-2xl border border-slate-700">
            <div className="text-center mb-8">
                <h1 className="text-2xl font-bold text-white mb-2">Xush kelibsiz</h1>
                <p className="text-slate-400 text-sm">Davom etish uchun tillarni tanlang</p>
            </div>
            
            <div className="space-y-6">
                <div>
                    <label className="block text-xs font-bold text-indigo-400 mb-3 uppercase tracking-wider ml-1">Mening ona tilim</label>
                    <div className="grid grid-cols-1 gap-2">
                        {availableLanguages.map(lang => (
                            <button
                                key={lang.code}
                                onClick={() => setNativeLang(lang.code)}
                                className={`flex items-center p-3 rounded-xl border transition-all duration-200 text-left ${
                                    nativeLang === lang.code 
                                    ? 'bg-indigo-600 border-indigo-500 text-white shadow-md' 
                                    : 'bg-slate-700/50 border-transparent text-slate-300 hover:bg-slate-700'
                                }`}
                            >
                                <span className="text-xl mr-3">{lang.flag}</span>
                                <span className="font-medium text-sm">{lang.name}</span>
                            </button>
                        ))}
                    </div>
                </div>
                
                <div>
                    <label className="block text-xs font-bold text-indigo-400 mb-3 uppercase tracking-wider ml-1">O'rganmoqchi bo'lgan tilim</label>
                     <div className="grid grid-cols-1 gap-2">
                        {availableLanguages.filter(l => l.code !== nativeLang).map(lang => (
                            <button
                                key={lang.code}
                                onClick={() => setTargetLang(lang.code)}
                                disabled={!nativeLang}
                                className={`flex items-center p-3 rounded-xl border transition-all duration-200 text-left ${
                                    targetLang === lang.code 
                                    ? 'bg-indigo-600 border-indigo-500 text-white shadow-md' 
                                    : 'bg-slate-700/50 border-transparent text-slate-300 hover:bg-slate-700 disabled:opacity-40 disabled:cursor-not-allowed'
                                }`}
                            >
                                <span className="text-xl mr-3">{lang.flag}</span>
                                <span className="font-medium text-sm">{lang.name}</span>
                            </button>
                        ))}
                    </div>
                </div>
            </div>

            <div className="mt-10">
            <button
                onClick={handleStart}
                disabled={!nativeLang || !targetLang}
                className="w-full py-4 rounded-2xl font-bold text-white text-md transition-all duration-200
                           bg-indigo-600 hover:bg-indigo-500 active:scale-[0.98] shadow-lg shadow-indigo-900/20
                           disabled:bg-slate-700 disabled:text-slate-500 disabled:cursor-not-allowed disabled:shadow-none"
            >
                Boshlash
            </button>
            </div>
        </div>
      </div>
    </div>
  );
};

export default LanguageSelection;
