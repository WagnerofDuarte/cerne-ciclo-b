/// A picked photo — the on-disk file [path] plus its [mimeType], inferred
/// by the concrete `data/` implementation from the file's extension
/// (jpeg/png/webp only, matching `media-ocr`'s contract enum). Plain
/// Dart, not `package:image_picker`'s own `XFile` — keeps this port, and
/// every caller that depends on it ([PhotoEntryCubit]), decoupled from
/// that package's shape (mirrors `MicRecording`, `mic_recorder.dart`).
class PickedPhoto {
  const PickedPhoto({required this.path, required this.mimeType});

  final String path;
  final String mimeType;
}

/// Capture's own photo-picking port — the `image_picker`-backed
/// `ImagePickerPhotoPicker` is the only implementation (Code Map),
/// mirroring [MicRecorder]'s port convention. `PhotoEntryCubit` depends
/// on this interface only, never on `package:image_picker` directly
/// (RNF06-style boundary, extended to any native package, not just
/// `data/`).
abstract class PhotoPicker {
  /// Opens the camera. `null` means the user canceled with no file
  /// chosen (I/O matrix: "User cancels picker").
  Future<PickedPhoto?> pickFromCamera();

  /// Opens the photo gallery. Same `null`-means-canceled convention as
  /// [pickFromCamera].
  Future<PickedPhoto?> pickFromGallery();
}
