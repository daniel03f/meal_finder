import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

/// Decodes JPEG bytes and rotates from sensor orientation to display orientation.
/// Used via [compute] to run in an isolate.
/// args[0]: Uint8List (JPEG bytes)
/// args[1]: bool (isFrontCamera)
/// args[2]: bool (isLandscape)
img.Image? decodeAndRotate(List<dynamic> args) {
  final Uint8List imageData = args[0] as Uint8List;
  final bool isFrontCamera = args[1] as bool;
  final bool isLandscape = args[2] as bool;

  final img.Image? decoded = img.decodeJpg(imageData);
  if (decoded == null) return null;

  // In landscape mode the sensor orientation already matches display
  if (isLandscape) return decoded;

  return isFrontCamera
      ? img.copyRotate(decoded, angle: 90)
      : img.copyRotate(decoded, angle: 270);
}

/// Maps a normalizedBox (0-1 range, relative to the full camera frame)
/// to screen pixel coordinates, accounting for the FILL_CENTER scaling
/// that the native camera preview applies.
Rect normalizedToScreenRect(
    Rect normalizedBox, double viewWidth, double viewHeight,
    {double cameraAspect = 3.0 / 4.0}) {
  final double viewAspect = viewWidth / viewHeight;

  double scaleX = 1.0;
  double scaleY = 1.0;

  if (cameraAspect >= viewAspect) {
    // Camera is relatively wider → height fills exactly, horizontal is cropped
    scaleX = cameraAspect / viewAspect;
  } else {
    // Camera is relatively taller → width fills exactly, vertical is cropped
    scaleY = viewAspect / cameraAspect;
  }

  return Rect.fromLTRB(
    (normalizedBox.left * scaleX - (scaleX - 1) / 2) * viewWidth,
    (normalizedBox.top * scaleY - (scaleY - 1) / 2) * viewHeight,
    (normalizedBox.right * scaleX - (scaleX - 1) / 2) * viewWidth,
    (normalizedBox.bottom * scaleY - (scaleY - 1) / 2) * viewHeight,
  );
}

// Create a crop from the detected bounding box
img.Image createCrop(img.Image decodedImage, Rect boundingBox) {
  // Ensure bounding box is within image bounds
  final x = (boundingBox.left * decodedImage.width)
      .toInt()
      .clamp(0, decodedImage.width - 1);
  final y = (boundingBox.top * decodedImage.height)
      .toInt()
      .clamp(0, decodedImage.height - 1);
  final w = (boundingBox.width * decodedImage.width)
      .toInt()
      .clamp(1, decodedImage.width - x);
  final h = (boundingBox.height * decodedImage.height)
      .toInt()
      .clamp(1, decodedImage.height - y);

  // Create the crop using the calculated pixel coordinates
  return img.copyCrop(
    decodedImage,
    x: x,
    y: y,
    width: w,
    height: h,
  );
}

// Resize and center-crop the image to the target size while maintaining aspect ratio
img.Image scaleCropImage(img.Image image, int targetSize) {
  // Resize so the shorter side is targetSize px (maintain aspect ratio)
  final img.Image scaled;
  if (image.width < image.height) {
    scaled = img.copyResize(image,
        width: targetSize, interpolation: img.Interpolation.cubic);
  } else {
    scaled = img.copyResize(image,
        height: targetSize, interpolation: img.Interpolation.cubic);
  }

  // Center crop to targetSize x targetSize
  final int cropX = (scaled.width - targetSize) ~/ 2;
  final int cropY = (scaled.height - targetSize) ~/ 2;
  return img.copyCrop(scaled,
      x: cropX, y: cropY, width: targetSize, height: targetSize);
}
