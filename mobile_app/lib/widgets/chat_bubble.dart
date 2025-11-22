import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:math' as math;
import '../models/types.dart';

class ChatBubble extends StatelessWidget {
  final Conversation message;
  final bool isTyping;

  const ChatBubble({
    super.key,
    required this.message,
    this.isTyping = false,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.speaker == Speaker.user;
    final isSystem = message.speaker == Speaker.system;

    if (isSystem) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.yellow.shade50,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.yellow.shade200),
          ),
          child: Text(
            message.text,
            style: TextStyle(color: Colors.yellow.shade900, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
        padding: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isUser ? 20 : 0),
            bottomRight: Radius.circular(isUser ? 0 : 20),
          ),
          boxShadow: [
            if (!isUser)
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
          ],
          border: !isUser ? Border.all(color: Colors.grey.shade100) : null,
        ),
        child: isTyping
            ? const _TypingIndicator()
            : MarkdownBody(
                data: message.text,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: isUser ? Colors.white : Colors.black87,
                    fontSize: 16,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (index) {
          return ScaleTransition(
            scale: DelayTween(begin: 0.5, end: 1.0, delay: index * 0.2)
                .animate(CurvedAnimation(
              parent: _controller,
              curve: Curves.easeInOut,
            )),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                shape: BoxShape.circle,
              ),
            ),
          );
        }),
      ),
    );
  }
}

class DelayTween extends Tween<double> {
  final double delay;

  DelayTween({super.begin, super.end, required this.delay});

  @override
  double lerp(double t) {
    return super.lerp((math.sin((t - delay) * 2 * math.pi) + 1) / 2);
  }
}
