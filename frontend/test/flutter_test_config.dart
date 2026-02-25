import 'dart:async';

import 'package:hydrated_bloc/hydrated_bloc.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HydratedBloc.storage = _InMemoryStorage();
  await testMain();
}

class _InMemoryStorage implements Storage {
  final Map<String, dynamic> _store = <String, dynamic>{};

  @override
  dynamic read(String key) {
    return _store[key];
  }

  @override
  Future<void> write(String key, dynamic value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<void> clear() async {
    _store.clear();
  }

  @override
  Future<void> close() async {}
}
