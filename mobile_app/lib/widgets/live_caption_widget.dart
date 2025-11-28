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

  final ScrollController _scrollController = ScrollController();
  bool _showTopShadow = false;
  bool _showBottomShadow = false;

  @override
  void initState() {
    super.initState();

    _fullText = widget.initialText;

    if (widget.currentTurnText.isNotEmpty) {
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

    _scrollController.addListener(_onScroll);

    _subscribe();

    if (_wordQueue.isNotEmpty) {
      _processQueue();
    }

    // Check initial scroll state
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final offset = _scrollController.offset;

    // reverse: true logic
    // offset 0 is visually at the bottom (end of text)
    // offset maxScroll is visually at the top (start of text)

    // Show top shadow if we are NOT at the top (start of text) -> offset < maxScroll
    final showTop = offset < maxScroll - 5;

    // Show bottom shadow if we are NOT at the bottom (end of text) -> offset > 0
    final showBottom = offset > 5;

    if (showTop != _showTopShadow || showBottom != _showBottomShadow) {
      setState(() {
        _showTopShadow = showTop;
        _showBottomShadow = showBottom;
      });
    }
  }

  void _subscribe() {
    _subscription = widget.textStream.listen((newChunk) {
      if (newChunk.isEmpty || !mounted) return;

      setState(() {
        _fullText += newChunk;
      });

      // Check scroll again after text update
      WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());

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
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Playful, larger font
    final mainTextStyle = GoogleFonts.nunito(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: const Color(0xFF2D3748), // Dark grey/blue
      height: 1.4,
    );

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min, // Shrink vertically
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 24.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  SingleChildScrollView(
                    controller: _scrollController,
                    reverse: true,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _fullText,
                      textAlign: TextAlign.center,
                      style: mainTextStyle,
                    ),
                  ),

                  // Top Shadow (Visual Top) - corresponds to maxScrollExtent in reverse list?
                  // Wait, Stack positions are visual. Top: 0 is visual top.
                  if (_showTopShadow)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Bottom Shadow (Visual Bottom)
                  if (_showBottomShadow)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 24),

        // Popping word animation
        SizedBox(
          height: 80,
          child: Center(
            child: AnimatedBuilder(
              animation: _popController,
              builder: (context, child) {
                if (_currentWord.isEmpty) return const SizedBox();

                return Opacity(
                  opacity: _opacityAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ]
                      ),
                      child: Text(
                        _currentWord,
                        style: GoogleFonts.nunito(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.blueAccent,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
