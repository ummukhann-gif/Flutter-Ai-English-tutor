import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// A widget that displays a preview of a selected image with a remove button
class ImagePreview extends StatelessWidget {
  final XFile image;
  final VoidCallback onRemove;
  final double height;
  final double maxWidth;

  const ImagePreview({
    super.key,
    required this.image,
    required this.onRemove,
    this.height = 120,
    this.maxWidth = 200,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.only(bottom: 8),
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(image.path),
                fit: BoxFit.cover,
                width: maxWidth,
                height: height,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onPressed: onRemove,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
