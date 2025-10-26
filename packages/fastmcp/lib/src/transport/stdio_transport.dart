import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

import 'transport.dart';

/// Transport implementation using standard input/output streams.
///
/// This transport is designed for a single client-server connection over
/// the command line, making it ideal for local process communication.
class StdioTransport implements ServerTransport {
  final _messageController = StreamController<TransportMessage>.broadcast();
  final _closeCompleter = Completer<void>();
  final Logger _log = Logger('StdioTransport');
  StreamSubscription? _stdinSubscription;

  static const String _stdioTransportId = 'stdio_connection';
  String? _sessionId;

  StdioTransport() {
    _initialize();
  }

  void _initialize() {
    _log.info('Initializing STDIO transport.');

    if (_stdinSubscription != null) {
      _log.warning('STDIO transport is already initialized. Skipping.');
      return;
    }

    _stdinSubscription = stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (line.isNotEmpty) {
              try {
                final data = jsonDecode(line);
                _messageController.add(
                  TransportMessage(
                    data: data,
                    transportId: _stdioTransportId,
                    sessionId: _sessionId,
                  ),
                );
              } catch (e) {
                _log.warning('Failed to parse incoming JSON line: "$line"', e);
              }
            }
          },
          onDone: close,
          onError: (e) {
            _log.severe('Error on stdin stream. Closing transport.', e);
            close();
          },
        );
  }

  @override
  Stream<TransportMessage> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  /// Sends a message to `stdout`.
  /// The [sessionId] is ignored as there is only one client.
  @override
  void send(dynamic message, {String? sessionId, Object? transportContext}) {
    if (_closeCompleter.isCompleted) {
      _log.warning('Attempted to send message on a closed transport.');
      return;
    }
    try {
      final jsonMessage = jsonEncode(message);
      stdout.writeln(jsonMessage);
    } catch (e, s) {
      _log.severe('Failed to encode and send message.', e, s);
    }
  }

  /// Associates the single stdio connection with its official session ID.
  @override
  void associateSession(String transportId, String sessionId) {
    if (transportId == _stdioTransportId) {
      _sessionId = sessionId;
      _log.info('STDIO transport associated with session ID: $sessionId');
    }
  }

  @override
  void close() {
    if (_closeCompleter.isCompleted) return;

    _log.info('Closing STDIO transport.');
    _stdinSubscription?.cancel();
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    _closeCompleter.complete();
  }
}
