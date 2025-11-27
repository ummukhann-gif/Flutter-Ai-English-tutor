import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LiveCaptionWidget extends StatefulWidget {
  final Stream<String> textStream;
  final String initialText;
  final String currentTurnText; // Hozirgi turn uchun matn (TutorScreen dan)

  const LiveCaptionWidget({
    super.key,
    required this.textStream,
    this.initialText = '',
    this.currentTurnText = '',
  });

  @override
  State<LiveCaptionWidget> createState() => _LiveCaptionWidgetState();
}

class _LiveCaptionWidgetState extends State<LiveCaptionWidget>
    with TickerProviderStateMixin {
  String _fullText = '';
  String _currentWord = '';
  StreamSubscription<String>? _subscription;

  late AnimationController _popController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    // Boshlang'ich matnni o'rnatish
    _fullText = widget.initialText;
    
    // Agar currentTurnText bor bo'lsa, oxirgi so'zni olish
    if (widget.currentTurnText.isNotEmpty) {
      final words = widget.currentTurnText.trim().split(RegExp(r'\s+'));
      if (words.isNotEmpty) {
        _currentWord = words.last;
      }
    }

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _popController,
        curve: Curves.elasticOut,
      ),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _popController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
      ),
    );

    _subscribe();
  }

  void _subscribe() {
    _subscription = widget.textStream.listen((newChunk) {
      if (newChunk.isEmpty || !mounted) return;

      setState(() {
        // Yuqoridagi matn uchun
        _fullText += newChunk;

        // Hozirgi so'zni yangi chunk dan olish
        final words = newChunk.trim().split(RegExp(r'\s+'));
        if (words.isNotEmpty && words.last.isNotEmpty) {
          _currentWord = words.last;
        }
      });

      // Animatsiyani ishga tushirish
      _popController.reset();
      _popController.forward();
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _popController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mainTextStyle = GoogleFonts.nunito(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
      height: 1.5,
    );

    final highlightTextStyle = GoogleFonts.nunito(
      fontSize: 36,
      fontWeight: FontWeight.w900,
      color: Colors.blueAccent,
      shadows: [
        Shadow(
          color: Colors.blue.withValues(alpha: 0.3),
          offset: const Offset(2, 2),
          blurRadius: 4,
        ),
      ],
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 1. To'liq matn (tepada)
        Expanded(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: SingleChildScrollView(
              reverse: true,
              physics: const BouncingScrollPhysics(),
              child: Text(
                _fullText,
                textAlign: TextAlign.center,
                style: mainTextStyle,
              ),
            ),
          ),
        ),

        // 2. Hozirgi so'z (pastda, animatsiya bilan)
        SizedBox(
          height: 100,
          child: Center(
            child: AnimatedBuilder(
              animation: _popController,
              builder: (context, child) {
                if (_currentWord.isEmpty) return const SizedBox();

                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Text(
                      _currentWord,
                      style: highlightTextStyle,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}
