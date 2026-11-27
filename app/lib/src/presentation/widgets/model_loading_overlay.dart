import 'package:flutter/material.dart';

/// A loading overlay widget that displays model loading progress
class ModelLoadingOverlay extends StatelessWidget {
  const ModelLoadingOverlay({
    super.key,
    required this.loadingMessage,
    required this.loadingProgress,
  });

  final String loadingMessage;
  final double loadingProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              width: 120,
              height: 120,
              color: Colors.white.withOpacity(0.8),
            ),
            const SizedBox(height: 32),
            Text(
              loadingMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            if (loadingProgress > 0) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: 200,
                child: LinearProgressIndicator(
                  value: loadingProgress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${(loadingProgress * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}