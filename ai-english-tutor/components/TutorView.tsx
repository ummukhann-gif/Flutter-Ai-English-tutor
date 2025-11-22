
import React, { useState, useRef, useEffect, useCallback } from 'react';
import { GoogleGenAI, LiveServerMessage, Modality, Blob } from '@google/genai';
import { MicrophoneIcon, UploadIcon, BackIcon, SendIcon, KeyboardIcon, CloseIcon, CameraIcon, ChatIcon, PhoneIcon } from './icons';
import { Lesson, Conversation, Score, LanguagePair } from '../types';
import AudioVisualizer from './AudioVisualizer';

// Helper functions for audio encoding/decoding
function encode(bytes: Uint8Array) {
  let binary = '';
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

function decode(base64: string) {
  const binaryString = atob(base64);
  const len = binaryString.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}

async function decodeAudioData(
    data: Uint8Array,
    ctx: AudioContext,
    sampleRate: number,
    numChannels: number,
): Promise<AudioBuffer> {
  const dataInt16 = new Int16Array(data.buffer);
  const frameCount = dataInt16.length / numChannels;
  const buffer = ctx.createBuffer(numChannels, frameCount, sampleRate);

  for (let channel = 0; channel < numChannels; channel++) {
    const channelData = buffer.getChannelData(channel);
    for (let i = 0; i < frameCount; i++) {
      channelData[i] = dataInt16[i * numChannels + channel] / 32768.0;
    }
  }
  return buffer;
}


interface TutorViewProps {
  lesson: Lesson;
  languages: LanguagePair;
  onLessonComplete: (score: Score) => void;
  onExit: () => void;
  conversationHistory: Conversation[];
  setConversationHistory: (value: Conversation[] | ((val: Conversation[]) => Conversation[])) => void;
}

type ViewMode = 'chat' | 'immersive';

const TutorView: React.FC<TutorViewProps> = ({ lesson, languages, onLessonComplete, onExit, conversationHistory, setConversationHistory }) => {
  const [isRecording, setIsRecording] = useState(false);
  const [isProcessing, setIsProcessing] = useState(false); // Visual state for the tail processing
  const [isAISpeaking, setIsAISpeaking] = useState(false);
  const [isConnecting, setIsConnecting] = useState(true);
  const [isReconnecting, setIsReconnecting] = useState(false);
  const [textInput, setTextInput] = useState('');
  const [mediaStream, setMediaStream] = useState<MediaStream | null>(null);
  const [toastMessage, setToastMessage] = useState<string | null>(null);
  
  // Interface Modes - DEFAULT TO IMMERSIVE
  const [viewMode, setViewMode] = useState<ViewMode>('immersive');
  const [inputMode, setInputMode] = useState<'voice' | 'text'>('voice');
  
  // Karaoke / Streaming Text State for Immersive Mode
  const [transcriptParts, setTranscriptParts] = useState<string[]>([]);
  const [activeRealWordIndex, setActiveRealWordIndex] = useState<number>(-1);
  
  // Attachment State
  const [selectedImage, setSelectedImage] = useState<{ file: File; preview: string } | null>(null);

  // Refs
  const sessionPromiseRef = useRef<any | null>(null);
  const mediaStreamRef = useRef<MediaStream | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const scriptProcessorRef = useRef<ScriptProcessorNode | null>(null);
  const outputAudioContextRef = useRef<AudioContext | null>(null);
  const nextStartTimeRef = useRef<number>(0);
  const audioSourcesRef = useRef<Set<AudioBufferSourceNode>>(new Set());
  const endRecordingTimeoutRef = useRef<number | null>(null);
  
  // Scheduler Refs
  const wordQueueRef = useRef<string[]>([]); // Tracks ONLY real words (no spaces)
  const lastWordTimeRef = useRef<number>(0);
  const lastTextArrivalRef = useRef<number>(0);
  
  // State refs
  const isRecordingRef = useRef(false); // Controls if data is SENT
  const isButtonHeldRef = useRef(false); // Controls PHYSICAL button state
  const silenceStartTimeRef = useRef<number | null>(null); // For VAD

  const isAISpeakingRef = useRef(false);
  const isNewUserUtteranceRef = useRef(true);
  const isNewAIUtteranceRef = useRef(true);
  const isMountedRef = useRef(true);
  const conversationHistoryRef = useRef(conversationHistory);

  const transcriptContainerRef = useRef<HTMLDivElement>(null);
  const transcriptEndRef = useRef<HTMLDivElement>(null);
  const userScrolledUpRef = useRef(false);
  
  const fileInputRef = useRef<HTMLInputElement>(null);
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const immersiveScrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    isAISpeakingRef.current = isAISpeaking;
  }, [isAISpeaking]);

  useEffect(() => {
    conversationHistoryRef.current = conversationHistory;
    
    // If in Immersive mode and streaming response is empty, try to populate it with the last AI message
    if (viewMode === 'immersive' && transcriptParts.length === 0) {
        const lastMsg = conversationHistory[conversationHistory.length - 1];
        if (lastMsg && lastMsg.speaker === 'ai' && !lastMsg.text.includes('LESSON_COMPLETE')) {
            const parts = lastMsg.text.split(/(\s+)/).filter(p => p.length > 0);
            setTranscriptParts(parts);
            const realWordCount = parts.filter(p => p.trim().length > 0).length;
            setActiveRealWordIndex(realWordCount); 
        }
    }
  }, [conversationHistory, viewMode, transcriptParts.length]);

  // Auto-scroll for Immersive Mode - Center Focus
  useEffect(() => {
      if (viewMode === 'immersive' && immersiveScrollRef.current && activeRealWordIndex >= 0) {
          const activeElement = document.getElementById(`word-${activeRealWordIndex}`);
          if (activeElement) {
              activeElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
          }
      }
  }, [activeRealWordIndex, viewMode]);

  const showToast = (msg: string) => {
      setToastMessage(msg);
      setTimeout(() => setToastMessage(null), 3000);
  }

  const addMessage = useCallback((speaker: 'user' | 'ai' | 'system', text: string, attachment?: Conversation['attachment']) => {
    const newMessage: Conversation = { 
        speaker, 
        text, 
        timestamp: new Date().toISOString(),
        attachment 
    };
    setConversationHistory(prev => [...prev, newMessage]);
  }, [setConversationHistory]);

  const connectToLiveSession = useCallback(() => {
    if (!process.env.API_KEY) {
        addMessage('system', 'API Key is not configured.');
        setIsConnecting(false);
        return;
    }
    const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });
    
    setIsConnecting(true);
    setIsReconnecting(false);

    const lessonPlanDetails = `
      - Lesson Title: ${lesson.title}
      - Lesson Tasks: ${lesson.tasks.join('; ')}
      - Key Vocabulary: ${lesson.vocabulary.map(v => `${v.word} (${v.translation})`).join(', ')}
    `;

    const isFirstConnection = conversationHistoryRef.current.length === 0;

    const historyPrompt = isFirstConnection
      ? `\n**YOUR FIRST SENTENCE:**\nYou MUST start the conversation by saying this EXACT phrase in ${languages.native}: "${lesson.startingPrompt}"`
      : `\n**CURRENT CONVERSATION HISTORY:**\n${conversationHistoryRef.current.map(m => `${m.speaker === 'ai' ? 'Tutor' : 'User'}: ${m.text}`).join('\n')}`;


    // UPDATED PROMPT: Stricter instructions moved to the top + VISION CAPABILITIES
    const systemInstruction = `You are a strict, professional language tutor ('ustoz') teaching a ${languages.native} speaker to learn ${languages.target}.

**CRITICAL RULES (MUST FOLLOW):**
1.  **ZERO TOLERANCE FOR IGNORANCE**: If the user says "I don't know", "Bilmayman", "No", or stays silent, you MUST NOT say "Good job" or "Barakalla". Instead, IMMEDIATELY teach them the answer and make them repeat it.
2.  **CORRECT MISTAKES INSTANTLY**: If the user makes a pronunciation or grammar mistake, stop and correct them. Do not praise incorrect attempts.
3.  **SHORT & CLEAR**: Keep your responses concise. Focus on the lesson tasks.
4.  **USE ${languages.native} FOR EXPLANATIONS**: Explain complex concepts in ${languages.native}, but encourage the user to speak in ${languages.target}.
5.  **NO INTERNAL THOUGHTS**: Output ONLY what you want to say to the student. Do not output thinking processes.
6.  **VISION CAPABILITIES**: You can see images the user sends. If they send an image of a book or text, read it and help them. Use the image as context for the lesson.

**YOUR LESSON PLAN:**
${lessonPlanDetails}
${historyPrompt}

**LESSON COMPLETION:**
When completed, end your response (in ${languages.native}) with "LESSON_COMPLETE" on a new line, followed by a score (1-10) and brief feedback.`;

    const sessionPromise = ai.live.connect({
        model: 'gemini-2.5-flash-native-audio-preview-09-2025',
        config: {
            responseModalities: [Modality.AUDIO],
            speechConfig: { voiceConfig: { prebuiltVoiceConfig: { voiceName: 'Zephyr' } } },
            inputAudioTranscription: {},
            outputAudioTranscription: {},
            systemInstruction: systemInstruction,
        },
        callbacks: {
            onopen: async () => {
                console.log('Session opened.');
                if (isMountedRef.current) {
                    setIsConnecting(false);
                    setIsReconnecting(false);
                    await setupPersistentAudioPipeline();
                }
            },
            onmessage: async (message: LiveServerMessage) => {
                if (message.serverContent?.interrupted) {
                    audioSourcesRef.current.forEach(source => {
                        try { source.stop(); } catch (e) {}
                    });
                    audioSourcesRef.current.clear();
                    nextStartTimeRef.current = 0;
                    setIsAISpeaking(false);
                    wordQueueRef.current = [];
                    return;
                }

                if(message.serverContent?.inputTranscription?.text) {
                    const text = message.serverContent.inputTranscription.text;
                    if (isNewUserUtteranceRef.current) {
                        isNewUserUtteranceRef.current = false;
                        addMessage('user', text);
                    } else {
                        setConversationHistory(prev => {
                            const newHistory = [...prev];
                            const lastMessage = newHistory[newHistory.length - 1];
                            if (lastMessage && lastMessage.speaker === 'user') {
                                newHistory[newHistory.length - 1] = { ...lastMessage, text: lastMessage.text + text };
                            }
                            return newHistory;
                        });
                    }
                    
                    setTranscriptParts([]);
                    setActiveRealWordIndex(-1);
                    wordQueueRef.current = [];
                }
                
                const outputText = message.serverContent?.outputTranscription?.text;

                if (outputText) {
                    if (isNewAIUtteranceRef.current) {
                        isNewAIUtteranceRef.current = false;
                        addMessage('ai', outputText);
                    } else {
                        setConversationHistory(prev => {
                            const newHistory = [...prev];
                            const lastMessage = newHistory[newHistory.length - 1];
                            if (lastMessage && lastMessage.speaker === 'ai') {
                                newHistory[newHistory.length - 1] = { ...lastMessage, text: lastMessage.text + outputText };
                            }
                            return newHistory;
                        });
                    }
                    
                    const parts = outputText.split(/(\s+)/).filter(p => p.length > 0);
                    setTranscriptParts(prev => [...prev, ...parts]);
                    
                    const realWords = parts.filter(p => p.trim().length > 0);
                    wordQueueRef.current.push(...realWords);
                    lastTextArrivalRef.current = performance.now();
                }

                if (message.serverContent?.turnComplete) {
                    isNewUserUtteranceRef.current = true;
                    isNewAIUtteranceRef.current = true;
                    
                    setConversationHistory(prev => {
                        const newHistory = [...prev];
                        const lastMessage = newHistory[newHistory.length - 1];

                        if (lastMessage && lastMessage.speaker === 'ai' && lastMessage.text.includes('LESSON_COMPLETE')) {
                            const parts = lastMessage.text.split('LESSON_COMPLETE');
                            const mainText = parts[0].trim();
                            const data = parts[1] || '';
                            const dataParts = data.trim().split('\n');
                            const score = parseInt(dataParts[0], 10) || 8;
                            const feedback = dataParts[1] || "Good job!";
                            
                            newHistory[newHistory.length - 1] = { ...lastMessage, text: mainText };

                            setTimeout(() => {
                                onLessonComplete({ lessonId: lesson.id, score, feedback, completedAt: new Date().toISOString() });
                            }, 4000);
                            
                            return newHistory;
                        }
                        return prev;
                    });
                }

                const audioData = message.serverContent?.modelTurn?.parts?.[0]?.inlineData?.data;
                if (audioData) {
                    setIsAISpeaking(true);
                    const outputCtx = outputAudioContextRef.current!;
                    nextStartTimeRef.current = Math.max(nextStartTimeRef.current, outputCtx.currentTime);
                    const audioBuffer = await decodeAudioData(decode(audioData), outputCtx, 24000, 1);
                    
                    const source = outputCtx.createBufferSource();
                    source.buffer = audioBuffer;
                    source.connect(outputCtx.destination);
                    source.start(nextStartTimeRef.current);
                    nextStartTimeRef.current += audioBuffer.duration;
                    audioSourcesRef.current.add(source);
                    source.onended = () => {
                        audioSourcesRef.current.delete(source);
                        if (audioSourcesRef.current.size === 0) {
                            setIsAISpeaking(false);
                        }
                    };
                }
            },
            onerror: (e: ErrorEvent) => {
                console.error('Session error:', e);
                if (isMountedRef.current) {
                    setIsConnecting(false);
                    setIsReconnecting(true);
                    showToast("Aloqa uzildi. Qayta ulanmoqda...");
                    sessionPromiseRef.current = null;
                    setTimeout(() => { if (isMountedRef.current) connectToLiveSession() }, 3000);
                }
            },
            onclose: (e: CloseEvent) => {
                if (isMountedRef.current) {
                    setIsConnecting(false);
                    setIsReconnecting(true);
                    sessionPromiseRef.current = null;
                    setTimeout(() => { if (isMountedRef.current) connectToLiveSession() }, 3000);
                }
            },
        },
    });
    sessionPromiseRef.current = sessionPromise;

    const setupPersistentAudioPipeline = async () => {
        if (!sessionPromiseRef.current) return;
        
        try {
            const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
            mediaStreamRef.current = stream;
            setMediaStream(stream);
        } catch (error) {
            console.error('Microphone access denied:', error);
            addMessage('system', 'Mikrofon ruxsati kerak.');
            return;
        }

        audioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)({ sampleRate: 16000 });
        
        const source = audioContextRef.current.createMediaStreamSource(mediaStreamRef.current);
        const scriptProcessor = audioContextRef.current.createScriptProcessor(4096, 1, 1);
        scriptProcessorRef.current = scriptProcessor;

        scriptProcessor.onaudioprocess = (audioProcessingEvent) => {
            if (isAISpeakingRef.current) return;

            const inputData = audioProcessingEvent.inputBuffer.getChannelData(0);
            
            let sum = 0;
            for (let i = 0; i < inputData.length; i++) {
                sum += inputData[i] * inputData[i];
            }
            const rms = Math.sqrt(sum / inputData.length);
            
            // VERY SENSITIVE THRESHOLD for identifying "I don't know"
            const SILENCE_THRESHOLD = 0.002; 
            
            if (!isRecordingRef.current) return;

            if (isButtonHeldRef.current) {
                // ACTIVE NOISE FLOOR INJECTION
                if (rms < SILENCE_THRESHOLD) {
                    for (let i = 0; i < inputData.length; i++) {
                        inputData[i] = (Math.random() * 2 - 1) * 0.001; 
                    }
                }
                silenceStartTimeRef.current = null;
            } else {
                if (rms < SILENCE_THRESHOLD) {
                    if (silenceStartTimeRef.current === null) {
                        silenceStartTimeRef.current = Date.now();
                    } else if (Date.now() - silenceStartTimeRef.current > 1000) { 
                         console.log("Smart VAD: Silence detected, stopping early.");
                         stopRecordingNow();
                         return;
                    }
                } else {
                    silenceStartTimeRef.current = null;
                }
            }

            const l = inputData.length;
            const int16 = new Int16Array(l);
            for (let i = 0; i < l; i++) {
                int16[i] = inputData[i] * 32768;
            }
            const pcmBlob: Blob = {
                data: encode(new Uint8Array(int16.buffer)),
                mimeType: 'audio/pcm;rate=16000',
            };
            sessionPromiseRef.current?.then((session: any) => {
                session.sendRealtimeInput({ media: pcmBlob });
            });
        };

        source.connect(scriptProcessor);
        scriptProcessor.connect(audioContextRef.current.destination);
    };

  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lesson, languages]);

  const stopRecordingNow = () => {
      if (endRecordingTimeoutRef.current) {
          clearTimeout(endRecordingTimeoutRef.current);
          endRecordingTimeoutRef.current = null;
      }
      isRecordingRef.current = false;
      setIsProcessing(false);
      setIsRecording(false);
      silenceStartTimeRef.current = null;
  };
  
  const handlePushToTalkStart = (e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    if (isAISpeaking || isConnecting) return;
    
    if (navigator.vibrate) navigator.vibrate(50);

    if (audioContextRef.current?.state === 'suspended') {
        audioContextRef.current.resume();
    }
    if (outputAudioContextRef.current?.state === 'suspended') {
        outputAudioContextRef.current.resume();
    }

    if (endRecordingTimeoutRef.current) {
      clearTimeout(endRecordingTimeoutRef.current);
      endRecordingTimeoutRef.current = null;
    }
    
    setIsProcessing(false); 
    
    isNewUserUtteranceRef.current = true;
    isRecordingRef.current = true; 
    isButtonHeldRef.current = true; 
    setIsRecording(true); 
  };

  const handlePushToTalkEnd = (e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    if (!isRecordingRef.current) return;

    isButtonHeldRef.current = false; 
    setIsRecording(false); 
    setIsProcessing(true); 
    
    endRecordingTimeoutRef.current = window.setTimeout(() => {
        stopRecordingNow();
    }, 1500);
  };

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files && e.target.files[0]) {
      const file = e.target.files[0];
      const reader = new FileReader();
      reader.onload = (ev) => {
        setSelectedImage({
          file,
          preview: ev.target?.result as string
        });
        setViewMode('chat'); 
        setInputMode('text'); 
      };
      reader.readAsDataURL(file);
    }
  };

  const handleSend = async () => {
    if (!sessionPromiseRef.current) return;
    
    // STRICT RULE: Text is mandatory, even if image is selected.
    if (!textInput.trim()) return;

    const session = await sessionPromiseRef.current;
    let attachmentData = undefined;

    if (selectedImage) {
        const base64Image = selectedImage.preview.split(',')[1];
        const mimeType = selectedImage.file.type;
        
        attachmentData = {
            type: 'image' as const,
            data: selectedImage.preview, 
            mimeType: mimeType
        };

        // SEQUENTIAL SEND: Image First
        await session.sendRealtimeInput({ 
            media: { 
                mimeType: mimeType, 
                data: base64Image 
            } 
        });
    }

    // SEQUENTIAL SEND: Text Immediately After
    // This ensures the model receives both parts effectively in the correct order
    await session.sendRealtimeInput({ text: textInput });

    addMessage('user', textInput, attachmentData);
    
    setTextInput('');
    setSelectedImage(null);
    if (fileInputRef.current) fileInputRef.current.value = '';
    if (cameraInputRef.current) cameraInputRef.current.value = '';
    setInputMode('voice');
  };

  const handleCloseTextMode = () => {
      setInputMode('voice');
      setTextInput('');
      setSelectedImage(null);
  };
  
  const renderMessageContent = (msg: Conversation) => {
    const html = msg.text.replace(/\*\*(.*?)\*\*/g, '<strong>$1</strong>');
    return (
        <div>
            {msg.attachment && (
                <div className="mb-2">
                    <img 
                        src={msg.attachment.data} 
                        alt="User attachment" 
                        className="max-w-full h-auto rounded-lg border border-white/20 max-h-60 object-cover"
                    />
                </div>
            )}
            <span dangerouslySetInnerHTML={{ __html: html }} />
        </div>
    );
  };

  useEffect(() => {
    isMountedRef.current = true;
    outputAudioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)({ sampleRate: 24000 });
    connectToLiveSession();

    return () => {
        isMountedRef.current = false;
        if (endRecordingTimeoutRef.current) clearTimeout(endRecordingTimeoutRef.current);
        sessionPromiseRef.current?.then((session: any) => session.close());
        mediaStreamRef.current?.getTracks().forEach(track => track.stop());
        scriptProcessorRef.current?.disconnect();
        audioContextRef.current?.close();
        outputAudioContextRef.current?.close();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
      let animationFrameId: number;

      const scheduler = () => {
          if (viewMode !== 'immersive') {
               animationFrameId = requestAnimationFrame(scheduler);
               return;
          }

          const ctx = outputAudioContextRef.current;
          const now = performance.now();
          const pendingRealWords = wordQueueRef.current.length;

          if (ctx && pendingRealWords > 0) {
              const audioEndTime = nextStartTimeRef.current;
              const currentTime = ctx.currentTime;
              const timeRemaining = audioEndTime - currentTime;

              let delay = 50; 

              if (timeRemaining > 0.05) { 
                   delay = (timeRemaining * 1000) / pendingRealWords;
                   delay = Math.max(50, Math.min(delay, 800));
              } else {
                   if (now - lastTextArrivalRef.current < 1500) {
                       delay = 500; 
                   } else {
                       delay = 40; 
                   }
              }

              if (now - lastWordTimeRef.current > delay) {
                  wordQueueRef.current.shift();
                  setActiveRealWordIndex(prev => prev + 1);
                  lastWordTimeRef.current = now;
              }
          }

          animationFrameId = requestAnimationFrame(scheduler);
      };

      animationFrameId = requestAnimationFrame(scheduler);
      return () => cancelAnimationFrame(animationFrameId);
  }, [viewMode]);

  const handleScroll = () => {
      if (transcriptContainerRef.current) {
          const { scrollTop, scrollHeight, clientHeight } = transcriptContainerRef.current;
          if (scrollHeight - scrollTop - clientHeight > 100) {
              userScrolledUpRef.current = true;
          } else {
              userScrolledUpRef.current = false;
          }
      }
  }

  useEffect(() => {
    if (!userScrolledUpRef.current && viewMode === 'chat') {
        transcriptEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    }
  }, [conversationHistory, selectedImage, inputMode, viewMode]);


  return (
    <div className="flex flex-col h-[100dvh] relative overflow-hidden bg-slate-950 text-slate-100 font-roboto transition-colors duration-500">
      
      {/* Header - Minimal, just back button */}
      <header className="relative z-20 flex items-center justify-between p-4 bg-transparent pointer-events-none">
        <button onClick={onExit} className="p-2 rounded-full bg-slate-800/50 hover:bg-slate-700/80 transition-colors active:scale-95 pointer-events-auto backdrop-blur-sm">
            <BackIcon className="w-6 h-6 text-slate-300" />
        </button>
        
        <div className="w-10 flex justify-end">
            {!isConnecting && <span className="w-2 h-2 bg-green-500 rounded-full animate-pulse shadow-[0_0_10px_rgba(34,197,94,0.5)]"></span>}
        </div>
      </header>
      
      {/* Main Content Area: Switches based on viewMode */}
      {viewMode === 'chat' ? (
          /* ---- MODE 1: CHAT VIEW (History & Bubbles) ---- */
          <main 
            ref={transcriptContainerRef}
            onScroll={handleScroll}
            className="flex-1 overflow-y-auto p-4 space-y-6 relative z-10 hide-scrollbar pb-48"
          >
            {conversationHistory.map((msg, index) => (
                (msg.text || msg.attachment) && (
                <div key={index} className={`flex flex-col ${msg.speaker === 'user' ? 'items-end' : msg.speaker === 'ai' ? 'items-start' : 'items-center'}`}>
                    <div className={`max-w-[85%] px-4 py-3 shadow-md text-[15px] leading-relaxed
                        ${msg.speaker === 'user' 
                            ? 'bg-indigo-600 text-white rounded-2xl rounded-br-none' 
                            : msg.speaker === 'ai' 
                            ? 'bg-slate-800 text-slate-200 rounded-2xl rounded-bl-none border border-slate-700' 
                            : 'bg-slate-800/50 text-slate-400 text-xs rounded-xl py-1 px-3 border border-slate-700/50'
                        }`}>
                        {renderMessageContent(msg)}
                    </div>
                </div>
                )
            ))}
            
            {(isConnecting || isReconnecting) && (
                <div className="flex justify-center my-4">
                    <div className="bg-slate-800/80 backdrop-blur rounded-full px-4 py-2 flex items-center gap-2 border border-slate-700">
                        <div className="w-4 h-4 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin"></div>
                        <span className="text-xs text-slate-300">Aloqa o'rnatilmoqda...</span>
                    </div>
                </div>
            )}
            <div ref={transcriptEndRef} className="h-2" />
          </main>
      ) : (
          /* ---- MODE 2: IMMERSIVE VIEW (Karaoke Style) ---- */
          <main className="flex-1 flex flex-col items-center justify-center relative z-10 w-full h-full">
             
             {/* Connecting State */}
             {(isConnecting || isReconnecting) && (
                 <div className="absolute inset-0 flex items-center justify-center flex-col gap-4 animate-pulse z-20 pointer-events-none">
                     <div className="w-12 h-12 border-4 border-indigo-500 border-t-transparent rounded-full animate-spin"></div>
                     <p className="text-indigo-300 text-sm tracking-wider font-medium">ALOQA O'RNATILMOQDA...</p>
                 </div>
             )}

             {/* Streaming Text Display - Karaoke Style with Gradient Masks */}
             {!isConnecting && (
                 <div className="w-full max-w-3xl h-[60vh] relative flex items-center justify-center">
                     {/* Top Gradient Mask */}
                     <div className="absolute top-0 left-0 right-0 h-32 bg-gradient-to-b from-slate-950 via-slate-950/80 to-transparent z-20 pointer-events-none"></div>

                     <div 
                        ref={immersiveScrollRef}
                        className="w-full h-full overflow-y-auto hide-scrollbar flex flex-col items-center px-6 pt-[25vh] pb-[25vh]"
                     >
                         {transcriptParts.length > 0 ? (
                             <div className="text-3xl md:text-4xl font-bold leading-normal text-center flex flex-wrap justify-center gap-x-2 gap-y-2 transition-all">
                                {(() => {
                                    let realWordCounter = 0;
                                    return transcriptParts.map((part, i) => {
                                        const isRealWord = part.trim().length > 0;
                                        let isSpoken = false;
                                        let currentWordIndex = -1;

                                        if (isRealWord) {
                                            currentWordIndex = realWordCounter;
                                            isSpoken = realWordCounter <= activeRealWordIndex;
                                            realWordCounter++;
                                        } else {
                                            isSpoken = realWordCounter <= activeRealWordIndex + 1;
                                        }
                                        
                                        const isCurrent = isRealWord && currentWordIndex === activeRealWordIndex;

                                        return (
                                            <span 
                                                key={i}
                                                id={isRealWord ? `word-${currentWordIndex}` : undefined}
                                                className={`transition-all duration-300 rounded px-1
                                                    ${isCurrent ? 'scale-110' : ''}
                                                    ${isSpoken
                                                        ? 'text-white opacity-100 drop-shadow-md'
                                                        : 'text-slate-600 opacity-40 blur-[0.5px]'
                                                    }`}
                                            >
                                                {part}
                                            </span>
                                        );
                                    });
                                })()}
                             </div>
                         ) : (
                            <div className="flex flex-col items-center gap-4 opacity-30">
                                <div className="w-16 h-16 rounded-full border-2 border-slate-700 flex items-center justify-center">
                                    <MicrophoneIcon className="w-8 h-8" />
                                </div>
                                <p className="text-slate-500 text-sm font-medium uppercase tracking-widest">Suhbatni boshlang</p>
                            </div>
                         )}
                     </div>
                     
                     {/* Bottom Gradient Mask */}
                     <div className="absolute bottom-0 left-0 right-0 h-32 bg-gradient-to-t from-slate-950 via-slate-950/80 to-transparent z-20 pointer-events-none"></div>
                 </div>
             )}
          </main>
      )}


      {/* Toast Notification */}
      <div className={`absolute top-20 left-1/2 transform -translate-x-1/2 bg-slate-800 text-white px-4 py-2 rounded-lg shadow-lg z-50 transition-opacity duration-300 ${toastMessage ? 'opacity-100' : 'opacity-0 pointer-events-none'}`}>
        {toastMessage}
      </div>

      {/* Backdrop for Text Mode - Click to dismiss */}
      {inputMode === 'text' && (
        <div 
            className="absolute inset-0 z-25 bg-black/40 backdrop-blur-[2px] transition-opacity" 
            onClick={handleCloseTextMode}
        />
      )}

      {/* Bottom Control Surface */}
      <footer className="absolute bottom-0 left-0 right-0 z-30 flex flex-col justify-end">
        
        {/* Gradient Fade for Content */}
        <div className="absolute bottom-0 left-0 right-0 h-48 bg-gradient-to-t from-slate-950 via-slate-950/90 to-transparent -z-10 pointer-events-none"></div>

        {/* Visualizer Area - Only in Voice Mode */}
        <div className="w-full flex justify-center items-end h-24 mb-2 opacity-80 px-4 pointer-events-none">
             <AudioVisualizer stream={mediaStream} isSpeaking={isRecording} isAISpeaking={isAISpeaking} />
        </div>

        {/* Control Area */}
        <div className="relative px-6 pb-8 pt-2 w-full max-w-md mx-auto flex items-end justify-between">

            {/* Hidden File Inputs */}
            <input 
                type="file" 
                accept="image/*" 
                ref={fileInputRef} 
                onChange={handleFileSelect} 
                className="hidden" 
            />
            <input 
                type="file" 
                accept="image/*"
                capture="environment"
                ref={cameraInputRef} 
                onChange={handleFileSelect} 
                className="hidden" 
            />

            {/* MODE: TEXT INPUT */}
            {inputMode === 'text' ? (
                 <div className="w-full flex flex-col gap-3 animate-in slide-in-from-bottom-4 fade-in duration-300 bg-slate-900/95 p-4 rounded-[2rem] border border-slate-800 shadow-2xl backdrop-blur-xl ring-1 ring-white/10">
                     {selectedImage && (
                        <div className="relative self-start mb-1 group">
                             <img src={selectedImage.preview} className="h-24 w-24 object-cover rounded-xl border border-indigo-500/50" alt="Selected" />
                             <button 
                                 onClick={() => setSelectedImage(null)}
                                 onMouseDown={(e) => e.preventDefault()}
                                 className="absolute -top-2 -right-2 bg-red-500 text-white rounded-full p-1 shadow-md"
                             >
                                 <CloseIcon className="w-3 h-3" />
                             </button>
                        </div>
                     )}

                     <div className="flex items-end gap-2 w-full">
                         <button 
                             onClick={handleCloseTextMode} 
                             onMouseDown={(e) => e.preventDefault()}
                             className="p-3.5 rounded-full bg-slate-800 text-slate-400 hover:bg-slate-700 border border-slate-700"
                         >
                             {selectedImage ? <CloseIcon className="w-5 h-5" /> : <MicrophoneIcon className="w-5 h-5" />}
                         </button>
                         
                         <textarea
                            rows={1}
                            value={textInput}
                            onChange={(e) => {
                                setTextInput(e.target.value);
                                e.target.style.height = 'auto';
                                e.target.style.height = Math.min(e.target.scrollHeight, 100) + 'px';
                            }}
                            onBlur={() => setTimeout(handleCloseTextMode, 100)}
                            placeholder={selectedImage ? "Rasmga izoh yozing (majburiy)..." : "Xabar yozish..."}
                            className="flex-1 bg-slate-800/50 text-white placeholder-slate-500 focus:outline-none resize-none py-3.5 px-5 rounded-2xl border border-slate-700 focus:border-indigo-500/50 max-h-24 text-[16px]"
                            onKeyDown={(e) => {
                                if (e.key === 'Enter' && !e.shiftKey) {
                                    e.preventDefault();
                                    handleSend();
                                }
                            }}
                            autoFocus
                        />

                        <button 
                            onClick={handleSend}
                            onMouseDown={(e) => e.preventDefault()}
                            className="p-3.5 rounded-full bg-indigo-600 text-white shadow-lg disabled:opacity-50 disabled:bg-slate-700"
                            disabled={!textInput.trim()}
                        >
                            <SendIcon className="w-5 h-5" />
                        </button>
                     </div>
                 </div>
            ) : (
                /* MODE: VOICE CONTROLS - SPLIT FOOTER */
                <div className="w-full grid grid-cols-3 items-end">
                    
                    {/* LEFT ACTION: Chat Toggle or Camera/Upload */}
                    <div className="flex justify-start pb-2">
                        {viewMode === 'immersive' ? (
                            <button 
                                onClick={() => setViewMode('chat')}
                                className="p-4 rounded-full bg-slate-800/60 hover:bg-slate-700 border border-slate-700 text-slate-300 backdrop-blur-md transition-all active:scale-95 hover:scale-105"
                            >
                                <ChatIcon className="w-6 h-6" />
                            </button>
                        ) : (
                            <div className="flex gap-2">
                                <button 
                                    onClick={() => cameraInputRef.current?.click()}
                                    className="p-4 rounded-full bg-slate-800/60 hover:bg-slate-700 border border-slate-700 text-slate-300 backdrop-blur-md transition-all active:scale-95 hover:scale-105"
                                >
                                    <CameraIcon className="w-6 h-6" />
                                </button>
                                <button 
                                    onClick={() => fileInputRef.current?.click()}
                                    className="p-4 rounded-full bg-slate-800/60 hover:bg-slate-700 border border-slate-700 text-slate-300 backdrop-blur-md transition-all active:scale-95 hover:scale-105"
                                >
                                    <UploadIcon className="w-6 h-6" />
                                </button>
                            </div>
                        )}
                    </div>

                    {/* CENTER: BIG MIC BUTTON */}
                    <div className="flex justify-center relative z-10">
                         {/* Ring Animation */}
                         {(isRecording || isProcessing) && (
                             <>
                                <div className={`absolute inset-0 rounded-full animate-ping opacity-75 duration-1000 ${isProcessing ? 'bg-amber-500' : 'bg-indigo-500'}`}></div>
                                <div className={`absolute -inset-3 rounded-full animate-pulse opacity-30 duration-1500 ${isProcessing ? 'bg-amber-500' : 'bg-indigo-500'}`}></div>
                             </>
                         )}
                         
                         <button 
                            onMouseDown={handlePushToTalkStart}
                            onMouseUp={handlePushToTalkEnd}
                            onMouseLeave={handlePushToTalkEnd}
                            onTouchStart={handlePushToTalkStart}
                            onTouchEnd={handlePushToTalkEnd}
                            onTouchCancel={handlePushToTalkEnd}
                            disabled={isAISpeaking || isConnecting}
                            className={`relative w-24 h-24 rounded-full flex items-center justify-center shadow-[0_0_30px_rgba(79,70,229,0.3)] transition-all duration-200
                                ${isAISpeaking 
                                    ? 'bg-slate-800 cursor-wait opacity-80 border-2 border-slate-700' 
                                    : isRecording 
                                        ? 'bg-gradient-to-br from-rose-500 to-red-600 scale-110 shadow-[0_0_60px_rgba(225,29,72,0.6)] border-4 border-red-400/30' 
                                        : isProcessing
                                            ? 'bg-gradient-to-br from-amber-500 to-orange-600 scale-105 shadow-[0_0_50px_rgba(245,158,11,0.5)] border-4 border-amber-400/30'
                                            : 'bg-gradient-to-br from-indigo-600 to-violet-700 hover:shadow-[0_0_50px_rgba(79,70,229,0.6)] active:scale-95 border-4 border-indigo-400/20'
                                }`}
                         >
                            <MicrophoneIcon className={`w-10 h-10 text-white drop-shadow-lg ${isRecording ? 'animate-pulse' : isProcessing ? 'animate-bounce' : ''}`} />
                         </button>
                    </div>

                    {/* RIGHT ACTION: Keyboard (in Chat) or Voice Switch (if needed later) */}
                    <div className="flex justify-end pb-2">
                        {viewMode === 'chat' ? (
                            <div className="flex gap-2">
                                <button 
                                    onClick={() => setViewMode('immersive')}
                                    className="p-4 rounded-full bg-slate-800/60 hover:bg-slate-700 border border-slate-700 text-indigo-300 backdrop-blur-md transition-all active:scale-95 hover:scale-105"
                                >
                                    <PhoneIcon className="w-6 h-6" />
                                </button>
                                <button 
                                    onClick={() => setInputMode('text')}
                                    className="p-4 rounded-full bg-slate-800/60 hover:bg-slate-700 border border-slate-700 text-slate-300 backdrop-blur-md transition-all active:scale-95 hover:scale-105"
                                >
                                    <KeyboardIcon className="w-6 h-6" />
                                </button>
                            </div>
                        ) : (
                             /* Empty spacer for Immersive mode to keep mic centered */
                            <div className="w-12"></div>
                        )}
                    </div>
                </div>
            )}
        </div>
      </footer>
    </div>
  );
};

export default TutorView;
