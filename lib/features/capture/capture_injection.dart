import 'package:image_picker/image_picker.dart' as image_picker_pkg;
import 'package:record/record.dart' as record_pkg;
import 'package:whisper_ggml/whisper_ggml.dart';

import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import '../entries/domain/repositories/entries_repository.dart';
import 'data/datasources/media_remote_data_source.dart';
import 'data/repositories/media_repository_impl.dart';
import 'data/services/image_picker_photo_picker.dart';
import 'data/services/record_mic_recorder.dart';
import 'data/services/whisper_audio_transcriber.dart';
import 'domain/repositories/media_repository.dart';
import 'domain/services/audio_transcriber.dart';
import 'domain/services/mic_recorder.dart';
import 'domain/services/photo_picker.dart';
import 'presentation/cubit/audio_entry_cubit.dart';
import 'presentation/cubit/photo_entry_cubit.dart';
import 'presentation/cubit/text_entry_cubit.dart';

/// Registers the `capture` feature into the project's single `get_it`
/// instance (`sl`). Unlike every other feature's cubit in this codebase
/// (`AccountSettingsCubit`/`AuthCubit`, lazy singletons), [TextEntryCubit]/
/// [AudioEntryCubit] are both **factories** — the Insertion Modal needs a
/// fresh instance of each per "+" tap (Boundaries: "Modal open resets"),
/// not one long-lived instance reused across opens. [MicRecorder]/
/// [AudioTranscriber] (and the raw `record`/`whisper_ggml` plugin
/// instances underneath them) stay lazy singletons instead — one real
/// recorder/transcriber for the app's lifetime, shared across every modal
/// open, mirroring `EntriesRepository`'s own registration shape. Called
/// from `setupCoreDependencies()` right after `registerEntriesFeature()`
/// (Code Map).
void registerCaptureFeature() {
  sl.registerFactory<TextEntryCubit>(
    () => TextEntryCubit(sl<EntriesRepository>()),
  );

  sl.registerLazySingleton<record_pkg.AudioRecorder>(
    record_pkg.AudioRecorder.new,
  );
  sl.registerLazySingleton<MicRecorder>(
    () => RecordMicRecorder(recorder: sl<record_pkg.AudioRecorder>()),
  );

  sl.registerLazySingleton<WhisperController>(WhisperController.new);
  sl.registerLazySingleton<AudioTranscriber>(
    () => WhisperAudioTranscriber(controller: sl<WhisperController>()),
  );

  sl.registerFactory<AudioEntryCubit>(
    () => AudioEntryCubit(
      sl<MicRecorder>(),
      sl<AudioTranscriber>(),
      sl<EntriesRepository>(),
    ),
  );

  sl.registerLazySingleton<image_picker_pkg.ImagePicker>(
    image_picker_pkg.ImagePicker.new,
  );
  sl.registerLazySingleton<PhotoPicker>(
    () => ImagePickerPhotoPicker(picker: sl<image_picker_pkg.ImagePicker>()),
  );

  sl.registerLazySingleton<MediaRemoteDataSource>(
    () => MediaRemoteDataSource(sl<ApiClient>()),
  );
  sl.registerLazySingleton<MediaRepository>(
    () => MediaRepositoryImpl(remoteDataSource: sl<MediaRemoteDataSource>()),
  );

  sl.registerFactory<PhotoEntryCubit>(
    () => PhotoEntryCubit(
      sl<PhotoPicker>(),
      sl<MediaRepository>(),
      sl<EntriesRepository>(),
    ),
  );
}
