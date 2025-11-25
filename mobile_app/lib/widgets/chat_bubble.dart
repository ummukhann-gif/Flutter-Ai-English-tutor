import 'package:flutter/material.dart';
import '../models/types.dart';

/// A widget that displays a chat message bubble
class ChatBubble extends StatelessWidget {
  final Conversation message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.speaker == Speaker.user;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: SelectableText(
                message.text,
                style: TextStyle(
                  color: isUser
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
