// One long-lived worker isolate for sync, cache and JSON work. Before 4.0.0
// every job spawned its own isolate (`Isolate.run`); a worker that stays up
// starts each job at once, so syncing, live log updates and saving the cache
// never wait for an isolate to start and never run on the screen's thread.
// Jobs run one at a time in order. If the worker can't start (or dies), the
// job falls back to `Isolate.run`, so nothing changes for the result.

import 'dart:async';
import 'dart:isolate';

class BackgroundWorker {
  BackgroundWorker._();
  static final BackgroundWorker instance = BackgroundWorker._();

  SendPort? _send;
  Future<SendPort?>? _starting;
  bool _broken = false;

  Future<SendPort?> _port() {
    if (_send != null) return Future.value(_send);
    if (_broken) return Future.value(null);
    return _starting ??= () async {
      try {
        final ready = ReceivePort();
        final exit = ReceivePort();
        await Isolate.spawn(_main, ready.sendPort, debugName: 'MediaFlow worker', errorsAreFatal: false, onExit: exit.sendPort);
        final port = await ready.first.timeout(const Duration(seconds: 10)) as SendPort;
        exit.listen((_) {
          // The worker went away: the next job starts a new one.
          _send = null;
          _starting = null;
          exit.close();
        });
        _send = port;
        return port;
      } catch (_) {
        _broken = true;
        return null;
      } finally {
        _starting = null;
      }
    }();
  }

  /// Runs [work] on the worker and returns its result.
  Future<R> run<R>(FutureOr<R> Function() work) async {
    final port = await _port();
    if (port == null) return Isolate.run(work);
    final reply = ReceivePort();
    try {
      port.send((work, reply.sendPort));
    } catch (_) {
      // The job holds something that can't be sent (or the worker is gone).
      reply.close();
      return Isolate.run(work);
    }
    final msg = await reply.first;
    reply.close();
    if (msg is _Failure) Error.throwWithStackTrace(msg.error, msg.stack);
    return msg as R;
  }

  static Future<void> _main(SendPort ready) async {
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    await for (final msg in inbox) {
      final (work, reply) = msg as (FutureOr<Object?> Function(), SendPort);
      try {
        reply.send(await work());
      } catch (e, s) {
        try {
          reply.send(_Failure(e, s));
        } catch (_) {
          reply.send(_Failure(StateError('$e'), s));
        }
      }
    }
  }
}

class _Failure {
  _Failure(this.error, this.stack);
  final Object error;
  final StackTrace stack;
}

/// [BackgroundRunner] for the worker.
Future<R> runOnWorker<R>(FutureOr<R> Function() work) => BackgroundWorker.instance.run(work);
