import 'dart:developer' as developer;

class AppLogger {
  static final List<String> _logs = [];
  static const int _maxLogs = 500;

  static void log(String message, {String? level, String? tag}) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry =
        '[$timestamp] [${level ?? 'INFO'}] [${tag ?? 'APP'}] $message';

    _logs.add(logEntry);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    developer.log(message, name: tag ?? 'APP', level: level ?? 'INFO');
    print(logEntry);
  }

  static void info(String message, {String? tag}) {
    log(message, level: 'INFO', tag: tag);
  }

  static void error(String message,
      {String? tag, Object? error, StackTrace? stackTrace}) {
    final errorMessage = error != null ? '$message: $error' : message;
    log(errorMessage, level: 'ERROR', tag: tag);
    if (stackTrace != null) {
      log('Stack trace: $stackTrace', level: 'ERROR', tag: tag);
    }
  }

  static void warning(String message, {String? tag}) {
    log(message, level: 'WARNING', tag: tag);
  }

  static void debug(String message, {String? tag}) {
    log(message, level: 'DEBUG', tag: tag);
  }

  static List<String> getLogs() {
    return List.unmodifiable(_logs);
  }

  static void clearLogs() {
    _logs.clear();
    info('Logs cleared', tag: 'LOGGER');
  }

  static void logSupabaseOperation(String operation,
      {bool success = true, String? error}) {
    if (success) {
      info('Supabase operation successful: $operation', tag: 'SUPABASE');
    } else {
      error('Supabase operation failed: $operation',
          tag: 'SUPABASE', error: error);
    }
  }

  static void logMapOperation(String operation,
      {bool success = true, String? error}) {
    if (success) {
      info('Map operation successful: $operation', tag: 'MAP');
    } else {
      error('Map operation failed: $operation', tag: 'MAP', error: error);
    }
  }

  static void logLocationOperation(String operation,
      {bool success = true, String? error}) {
    if (success) {
      info('Location operation successful: $operation', tag: 'LOCATION');
    } else {
      error('Location operation failed: $operation',
          tag: 'LOCATION', error: error);
    }
  }

  static void logRideOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      info('Ride operation successful: $operation', tag: 'RIDE');
      if (data != null) {
        debug('Ride data: $data', tag: 'RIDE');
      }
    } else {
      error('Ride operation failed: $operation', tag: 'RIDE', error: error);
    }
  }

  static void logDriverOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      info('Driver operation successful: $operation', tag: 'DRIVER');
      if (data != null) {
        debug('Driver data: $data', tag: 'DRIVER');
      }
    } else {
      error('Driver operation failed: $operation', tag: 'DRIVER', error: error);
    }
  }
}
