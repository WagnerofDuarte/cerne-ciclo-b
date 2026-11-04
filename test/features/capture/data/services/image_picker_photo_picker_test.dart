import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:mocktail/mocktail.dart';

import 'package:cerne/features/capture/data/services/image_picker_photo_picker.dart';

class MockImagePicker extends Mock implements image_picker_pkg.ImagePicker {}

/// Covers spec-3-3's Code Map wrapper directly — `package:image_picker`'s
/// own `ImagePicker` is mocked (mocktail), never a real native platform
/// channel call (Never: no automated test exercises the real plugin),
/// same "mock the plugin class directly" convention
/// `record_mic_recorder_test.dart` already uses for `AudioRecorder`.
void main() {
  setUpAll(() {
    registerFallbackValue(image_picker_pkg.ImageSource.camera);
  });

  late MockImagePicker mockPicker;
  late ImagePickerPhotoPicker photoPicker;

  setUp(() {
    mockPicker = MockImagePicker();
    photoPicker = ImagePickerPhotoPicker(picker: mockPicker);
  });

  group('pickFromCamera()', () {
    test('calls ImagePicker.pickImage(source: camera), inferring mimeType '
        'from the extension', () async {
      when(
        () => mockPicker.pickImage(source: image_picker_pkg.ImageSource.camera),
      ).thenAnswer((_) async => image_picker_pkg.XFile('/tmp/foto.jpg'));

      final result = await photoPicker.pickFromCamera();

      expect(result, isNotNull);
      expect(result!.path, '/tmp/foto.jpg');
      expect(result.mimeType, 'image/jpeg');
    });

    test('the user canceling (null) -> null', () async {
      when(
        () => mockPicker.pickImage(source: image_picker_pkg.ImageSource.camera),
      ).thenAnswer((_) async => null);

      final result = await photoPicker.pickFromCamera();

      expect(result, isNull);
    });
  });

  group('pickFromGallery()', () {
    test('calls ImagePicker.pickImage(source: gallery)', () async {
      when(
        () =>
            mockPicker.pickImage(source: image_picker_pkg.ImageSource.gallery),
      ).thenAnswer((_) async => image_picker_pkg.XFile('/tmp/foto.png'));

      final result = await photoPicker.pickFromGallery();

      expect(result, isNotNull);
      expect(result!.path, '/tmp/foto.png');
      expect(result.mimeType, 'image/png');
      verify(
        () =>
            mockPicker.pickImage(source: image_picker_pkg.ImageSource.gallery),
      ).called(1);
    });

    test('the user canceling (null) -> null', () async {
      when(
        () =>
            mockPicker.pickImage(source: image_picker_pkg.ImageSource.gallery),
      ).thenAnswer((_) async => null);

      final result = await photoPicker.pickFromGallery();

      expect(result, isNull);
    });
  });

  group('mimeType inference', () {
    test('.webp -> image/webp', () async {
      when(() => mockPicker.pickImage(source: any(named: 'source')))
          .thenAnswer((_) async => image_picker_pkg.XFile('/tmp/a.webp'));

      final result = await photoPicker.pickFromGallery();

      expect(result!.mimeType, 'image/webp');
    });

    test(
      '.WEBP (uppercase extension) -> image/webp, case-insensitive',
      () async {
        when(() => mockPicker.pickImage(source: any(named: 'source')))
            .thenAnswer((_) async => image_picker_pkg.XFile('/tmp/A.WEBP'));

        final result = await photoPicker.pickFromGallery();

        expect(result!.mimeType, 'image/webp');
      },
    );

    test('an unrecognized extension (e.g. iOS HEIC, a known gap — Never: no '
        'HEIC conversion this story) falls back to image/jpeg', () async {
      when(() => mockPicker.pickImage(source: any(named: 'source')))
          .thenAnswer((_) async => image_picker_pkg.XFile('/tmp/a.heic'));

      final result = await photoPicker.pickFromGallery();

      expect(result!.mimeType, 'image/jpeg');
    });
  });
}
