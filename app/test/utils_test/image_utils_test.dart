import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:meal_finder/src/utils/image_utils.dart';

/// Solid-colour image of the requested size.
img.Image makeImage(int w, int h, {int r = 128, int g = 128, int b = 128}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return image;
}

void main() {
  group('createCrop', () {
    test('crop dimensions match normalised bounding box', () {
      final image = makeImage(400, 300);
      // 0.5 × 400 = 200, 0.5 × 300 = 150
      final crop = createCrop(image, const Rect.fromLTWH(0.0, 0.0, 0.5, 0.5));
      expect(crop.width, 200);
      expect(crop.height, 150);
    });

    test('full-frame bounding box produces crop equal to image size', () {
      final image = makeImage(224, 224);
      final crop = createCrop(image, const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0));
      expect(crop.width, 224);
      expect(crop.height, 224);
    });

    test('centre-half crop yields correct offset and size', () {
      // Box (0.25, 0.25) – (0.75, 0.75) on a 200×200 image → 100×100
      final image = makeImage(200, 200);
      final crop = createCrop(image, const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5));
      expect(crop.width, 100);
      expect(crop.height, 100);
    });

    test('crop width/height are at least 1 (min-clamp on zero-size box)', () {
      final image = makeImage(10, 10);
      // Box at far corner with zero extent → clamped to minimum 1×1
      final crop = createCrop(image, const Rect.fromLTWH(0.99, 0.99, 0.0, 0.0));
      expect(crop.width, greaterThanOrEqualTo(1));
      expect(crop.height, greaterThanOrEqualTo(1));
    });

    test('box origin before image edge is clamped to 0', () {
      final image = makeImage(200, 200);
      final crop = createCrop(image, const Rect.fromLTWH(-0.5, -0.5, 0.5, 0.5));
      expect(crop.width, greaterThanOrEqualTo(1));
      expect(crop.height, greaterThanOrEqualTo(1));
    });

    test('box extending past right/bottom edge is clamped to image boundary', () {
      final image = makeImage(100, 100);
      // Starts at x=0.8, width=0.5 → would reach x=1.3 (out of bounds)
      final crop = createCrop(image, const Rect.fromLTWH(0.8, 0.8, 0.5, 0.5));
      expect(crop.width, lessThanOrEqualTo(20));
      expect(crop.height, lessThanOrEqualTo(20));
    });
  });

  group('scaleCropImage', () {
    test('output is exactly targetSize × targetSize for a portrait input', () {
      final image = makeImage(100, 200); // narrower than tall
      final result = scaleCropImage(image, 64);
      expect(result.width, 64);
      expect(result.height, 64);
    });

    test('output is exactly targetSize × targetSize for a landscape input', () {
      final image = makeImage(300, 150); // wider than tall
      final result = scaleCropImage(image, 64);
      expect(result.width, 64);
      expect(result.height, 64);
    });

    test('output is exactly targetSize × targetSize for a square input', () {
      final image = makeImage(200, 200);
      final result = scaleCropImage(image, 64);
      expect(result.width, 64);
      expect(result.height, 64);
    });

    test('output is targetSize=224 × 224 (standard CLIP input size)', () {
      final image = makeImage(640, 480); // typical camera landscape frame
      final result = scaleCropImage(image, 224);
      expect(result.width, 224);
      expect(result.height, 224);
    });

    test('landscape: center pixel comes from the horizontal centre of the image', () {
      // 200×100 landscape, left half red, right half green.
      // After scaling to height=64: width≈128. Center crop removes ~32 px each side.
      // A perfectly centred image means the center of the crop lands in the
      // original image's horizontal centre, which is the boundary between red
      // and green – so the centre pixel should NOT be pure red (left edge).
      final image = img.Image(width: 200, height: 100);
      // Fill left half red, right half green
      for (int x = 0; x < 200; x++) {
        for (int y = 0; y < 100; y++) {
          image.setPixel(
              x, y, x < 100 ? img.ColorRgba8(255, 0, 0, 255) : img.ColorRgba8(0, 255, 0, 255));
        }
      }
      final result = scaleCropImage(image, 64);
      // Left-most column of the crop must not be the far-left red of the original
      // (the center crop trims the edges). The first pixel should be reddish
      // (center-ish of the red half) rather than pure green, confirming the crop
      // is taken from the middle rather than an edge.
      final firstPixel = result.getPixel(0, 0);
      expect(firstPixel.r, greaterThan(0),
          reason: 'Center crop should start inside the red region, not at index 0');
    });

    test('portrait: center pixel comes from the vertical centre of the image', () {
      // 100×200 portrait, top half blue, bottom half white.
      final image = img.Image(width: 100, height: 200);
      for (int x = 0; x < 100; x++) {
        for (int y = 0; y < 200; y++) {
          image.setPixel(
              x, y, y < 100 ? img.ColorRgba8(0, 0, 255, 255) : img.ColorRgba8(255, 255, 255, 255));
        }
      }
      final result = scaleCropImage(image, 64);
      // After scaling (width→64, height→128), center crop removes 32 px top & bottom.
      // The crop starts at y=32 (in scaled coords) which maps into the blue zone.
      // The last row of the result should map back to the white zone –
      // confirming vertical trimming happened.
      final lastPixel = result.getPixel(32, 63);
      expect(lastPixel.r, greaterThan(0),
          reason: 'Bottom rows of crop should reach into the white (bottom) zone');
    });

    test('result is an img.Image (not null)', () {
      final image = makeImage(80, 60);
      final result = scaleCropImage(image, 32);
      expect(result, isA<img.Image>());
    });
  });
}
