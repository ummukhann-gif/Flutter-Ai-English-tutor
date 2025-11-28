import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LiveCaptionWidget extends StatefulWidget {
  final Stream<String> textStream;
  final String initialText;
  final String currentTurnText;

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

  final List<String> _wordQueue = [];
  bool _isAnimating = false;

  late AnimationController _popController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Tarixni yuklaymiz
    _fullText = widget.initialText;

    // 2. MUHIM FIX: Widget ochilguncha kelib bo'lgan matnni ham qo'shamiz
    if (widget.currentTurnText.isNotEmpty) {
      _fullText += widget.currentTurnText;
      final existingWords = widget.currentTurnText
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      _wordQueue.addAll(existingWords);
    }

    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _popController, curve: Curves.elasticOut),
    );

    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _popController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // 3. Streamni tinglashni boshlaymiz
    _subscribe();

    // 4. Agar boshlang'ich so'zlar bo'lsa, darhol animatsiyani boshlaymiz
    if (_wordQueue.isNotEmpty) {
      _processQueue();
    }
  }

  void _subscribe() {
    _subscription = widget.textStream.listen((newChunk) {
      if (newChunk.isEmpty || !mounted) return;

      setState(() {
        _fullText += newChunk;
      });

      final newWords = newChunk
          .trim()
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      _wordQueue.addAll(newWords);

      if (!_isAnimating) {
        _processQueue();
      }
    });
  }

  void _processQueue() async {
    if (_wordQueue.isEmpty || !mounted) {
      _isAnimating = false;
      return;
    }
    _isAnimating = true;

    final nextWord = _wordQueue.removeAt(0);

    setState(() {
      _currentWord = nextWord;
    });

    _popController.reset();
    _popController.forward();

    int delay = 300;
    if (_wordQueue.length > 10) {
      delay = 50;
    } else if (_wordQueue.length > 5) {
      delay = 150;
    } else if (_wordQueue.length > 2) {
      delay = 200;
    }

    await Future.delayed(Duration(milliseconds: delay));

    if (mounted) {
      _processQueue();
    }
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

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
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
                      style: GoogleFonts.nunito(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.blueAccent,
                      ),
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
