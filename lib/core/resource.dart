import 'failure/failure.dart';

/// AD-12 — generic fetch-lifecycle state for screens with exactly one data
/// source and one fetch (`idle` / `loading` / `data` / `error`).
///
/// Used only where that shape fits (e.g. a single `GET` on screen entry).
/// RF02's capture pipeline, RF04's chat stream and RF07's composite
/// auth × sync × data state each define their own sealed state class instead
/// — never forced into this one (AD-12).
sealed class Resource<T> {
  const Resource();
}

final class ResourceIdle<T> extends Resource<T> {
  const ResourceIdle();
}

final class ResourceLoading<T> extends Resource<T> {
  const ResourceLoading();
}

final class ResourceData<T> extends Resource<T> {
  const ResourceData(this.data);

  final T data;
}

final class ResourceError<T> extends Resource<T> {
  const ResourceError(this.failure);

  final Failure failure;
}
