
import React, { useEffect, useRef } from 'react';

interface AudioVisualizerProps {
  stream: MediaStream | null;
  isSpeaking: boolean;
  isAISpeaking: boolean;
}

const AudioVisualizer: React.FC<AudioVisualizerProps> = ({ stream, isSpeaking, isAISpeaking }) => {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animationRef = useRef<number | null>(null);
  const analyserRef = useRef<AnalyserNode | null>(null);
  const audioContextRef = useRef<AudioContext | null>(null);
  const sourceRef = useRef<MediaStreamAudioSourceNode | null>(null);

  useEffect(() => {
    if (!stream) return;

    if (!audioContextRef.current) {
      audioContextRef.current = new (window.AudioContext || (window as any).webkitAudioContext)();
    }

    const audioCtx = audioContextRef.current;
    
    if (analyserRef.current) analyserRef.current.disconnect();
    if (sourceRef.current) sourceRef.current.disconnect();

    const analyser = audioCtx.createAnalyser();
    analyser.fftSize = 256;
    const source = audioCtx.createMediaStreamSource(stream);
    source.connect(analyser);

    analyserRef.current = analyser;
    sourceRef.current = source;

    return () => {
       // Cleanup is handled by parent stopping stream, but we disconnect nodes
       if (sourceRef.current) sourceRef.current.disconnect();
       if (analyserRef.current) analyserRef.current.disconnect();
    };
  }, [stream]);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const render = () => {
      const width = canvas.width;
      const height = canvas.height;
      ctx.clearRect(0, 0, width, height);

      if (isAISpeaking) {
        // AI Speaking Visual - Sine waves
        const time = Date.now() / 100;
        ctx.beginPath();
        ctx.lineWidth = 3;
        ctx.strokeStyle = '#22d3ee'; // Cyan
        for (let x = 0; x < width; x++) {
          const y = height / 2 + Math.sin(x * 0.05 + time) * 20 * Math.sin(time * 0.5);
          if (x === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();

        ctx.beginPath();
        ctx.lineWidth = 2;
        ctx.strokeStyle = '#a78bfa'; // Purple
        for (let x = 0; x < width; x++) {
           const y = height / 2 + Math.cos(x * 0.04 + time * 1.2) * 15 * Math.cos(time * 0.3);
           if (x === 0) ctx.moveTo(x, y);
           else ctx.lineTo(x, y);
        }
        ctx.stroke();

      } else if (isSpeaking && analyserRef.current) {
        // User Speaking Visual - Frequency Bars
        const bufferLength = analyserRef.current.frequencyBinCount;
        const dataArray = new Uint8Array(bufferLength);
        analyserRef.current.getByteFrequencyData(dataArray);

        const barWidth = (width / bufferLength) * 2.5;
        let x = 0;

        for (let i = 0; i < bufferLength; i++) {
          const barHeight = (dataArray[i] / 255) * height;
          
          const gradient = ctx.createLinearGradient(0, height - barHeight, 0, height);
          gradient.addColorStop(0, '#f472b6'); // Pink
          gradient.addColorStop(1, '#ec4899'); // Darker Pink

          ctx.fillStyle = gradient;
          
          // Round caps for bars
          ctx.beginPath();
          ctx.roundRect(x, height / 2 - barHeight / 2, barWidth, barHeight, 5);
          ctx.fill();

          x += barWidth + 2;
        }
      } else {
        // Idle state - Breathing dot
        const time = Date.now() / 1000;
        const radius = 5 + Math.sin(time * 2) * 1;
        ctx.beginPath();
        ctx.arc(width / 2, height / 2, radius, 0, 2 * Math.PI);
        ctx.fillStyle = '#4b5563';
        ctx.fill();
      }

      animationRef.current = requestAnimationFrame(render);
    };

    render();

    return () => {
      if (animationRef.current) cancelAnimationFrame(animationRef.current);
    };
  }, [isSpeaking, isAISpeaking]);

  return <canvas ref={canvasRef} width={300} height={100} className="w-full h-24" />;
};

export default AudioVisualizer;
