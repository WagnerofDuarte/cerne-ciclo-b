import 'package:hive_ce/hive_ce.dart';

import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import 'data/datasources/entries_remote_data_source.dart';
import 'data/repositories/entries_repository_impl.dart';
import 'domain/repositories/entries_repository.dart';

/// The `entries` Hive box's name — the first `hive_ce` box in the app
/// (Code Map). A raw `Box<Map>`, not a generated `HiveObject`/
/// `TypeAdapter` (Design Notes: avoids adapter codegen for a box nothing
/// reads yet).
const entriesBoxName = 'entries';

/// Registers the `entries` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `features/account/account_injection.dart`'s
/// pattern. Called from `setupCoreDependencies()` right after
/// `Hive.initFlutter()` (Code Map), which must already have run by the
/// time this opens its box.
Future<void> registerEntriesFeature() async {
  final entriesBox = await Hive.openBox<Map>(entriesBoxName);
  sl.registerSingleton<Box<Map>>(entriesBox);

  sl.registerLazySingleton<EntriesRemoteDataSource>(
    () => EntriesRemoteDataSource(sl<ApiClient>()),
  );

  sl.registerLazySingleton<EntriesRepository>(
    () => EntriesRepositoryImpl(
      remoteDataSource: sl<EntriesRemoteDataSource>(),
      entriesBox: sl<Box<Map>>(),
    ),
  );
}
