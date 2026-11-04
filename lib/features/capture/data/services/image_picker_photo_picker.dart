// The constructor keeps a public named param (`picker`) distinct from
// the private field it initializes, matching `record_mic_recorder.dart`'s
// documented convention.
// ignore_for_file: prefer_initializing_formals
import 'package:image_picker/image_picker.dart' as image_picker_pkg;

import '../../domain/services/photo_picker.dart';

/// Wraps `package:image_picker`'s `ImagePicker` behind the [PhotoPicker]
/// port. A `get_it` singleton (Code Map/`capture_injection.dart`) — one
/// real picker for the app's lifetime, reused across every Insertion
/// Modal open, mirroring `RecordMicRecorder`'s own registration shape.
class ImagePickerPhotoPicker implements PhotoPicker {
  ImagePickerPhotoPicker({required image_picker_pkg.ImagePicker picker})
    : _picker = picker;

  final image_picker_pkg.ImagePicker _picker;

  @override
  Future<PickedPhoto?> pickFromCamera() =>
      _pick(image_picker_pkg.ImageSource.camera);

  @override
  Future<PickedPhoto?> pickFromGallery() =>
      _pick(image_picker_pkg.ImageSource.gallery);

  Future<PickedPhoto?> _pick(image_picker_pkg.ImageSource source) async {
    final file = await _picker.pickImage(source: source);
    if (file == null) {
      return null;
    }
    return PickedPhoto(path: file.path, mimeType: _mimeTypeOf(file.path));
  }

  /// Inferred from the picked file's extension only — jpeg/png/webp,
  /// matching `media-ocr`'s contract enum exactly (Boundaries). Anything
  /// else (e.g. iOS HEIC, a known gap — Never: "no HEIC→JPEG conversion
  /// or client-side pre-check this story") falls back to `image/jpeg`,
  /// the most common on-device case; a genuinely unsupported format
  /// still surfaces through the backend's own validation rather than a
  /// client-side guess silently mislabeling it.
  String _mimeTypeOf(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
