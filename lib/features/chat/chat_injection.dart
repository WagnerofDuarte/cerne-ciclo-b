import 'package:hive_ce/hive_ce.dart';

import '../../core/di/injection_container.dart';
import '../../core/network/api_client.dart';
import 'data/datasources/chat_remote_data_source.dart';
import 'data/repositories/chat_repository_impl.dart';
import 'domain/repositories/chat_repository.dart';
import 'presentation/cubit/chat_cubit.dart';

/// The `chat_sessions`/`chat_messages` Hive box names — two boxes (Code
/// Map: "Hive box cache for `listSessions`/`listMessages`"), mirroring
/// `entries_injection.dart`'s `entriesBoxName` pattern but split in two
/// since each caches a structurally different DTO shape.
const chatSessionsBoxName = 'chat_sessions';
const chatMessagesBoxName = 'chat_messages';

/// Registers the `chat` feature into the project's single `get_it`
/// instance (`sl`) — mirrors `entries_injection.dart`'s pattern. Called
/// from `setupCoreDependencies()` after `Hive.initFlutter()` has already
/// run (Code Map), same ordering requirement `registerEntriesFeature()`
/// documents for itself.
Future<void> registerChatFeature() async {
  final sessionsBox = await Hive.openBox<Map>(chatSessionsBoxName);
  final messagesBox = await Hive.openBox<Map>(chatMessagesBoxName);
  // `instanceName` disambiguates the two `Box<Map>` singletons from each
  // other and from `entries_injection.dart`'s own unnamed one — `get_it`
  // keys a registration by type + instance name, so three same-typed
  // singletons coexist safely.
  sl.registerSingleton<Box<Map>>(sessionsBox, instanceName: chatSessionsBoxName);
  sl.registerSingleton<Box<Map>>(messagesBox, instanceName: chatMessagesBoxName);

  sl.registerLazySingleton<ChatRemoteDataSource>(
    () => ChatRemoteDataSource(sl<ApiClient>()),
  );

  sl.registerLazySingleton<ChatRepository>(
    () => ChatRepositoryImpl(
      remoteDataSource: sl<ChatRemoteDataSource>(),
      sessionsBox: sl<Box<Map>>(instanceName: chatSessionsBoxName),
      messagesBox: sl<Box<Map>>(instanceName: chatMessagesBoxName),
    ),
  );

  // A `lazySingleton`, not a factory (Code Map), mirroring
  // `MeusRegistrosCubit`: long-lived, so a session bootstrapped on one
  // visit to Home/Chat survives leaving and returning within the same app
  // session (`ChatCubit.init()`'s own no-op guard). `dispose:` wires
  // `close()` into `get_it`'s own reset lifecycle, same convention every
  // other long-lived cubit in this codebase already uses.
  sl.registerLazySingleton<ChatCubit>(
    () => ChatCubit(sl<ChatRepository>()),
    dispose: (cubit) => cubit.close(),
  );
}
