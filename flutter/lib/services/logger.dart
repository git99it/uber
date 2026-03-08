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

    // Fix: developer.log level parameter expects int, not String
    int logLevel = 0; // Default to INFO level
    switch (level?.toUpperCase()) {
      case 'ERROR':
        logLevel = 1000;
        break;
      case 'WARNING':
        logLevel = 900;
        break;
      case 'DEBUG':
        logLevel = 500;
        break;
      case 'INFO':
      default:
        logLevel = 800;
        break;
    }

    developer.log(message, name: tag ?? 'APP', level: logLevel);
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
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      final message = data != null
          ? 'Supabase operation successful: $operation (data: $data)'
          : 'Supabase operation successful: $operation';
      info(message, tag: 'SUPABASE');
    } else {
      final errorMessage = error != null
          ? 'Supabase operation failed: $operation (error: $error)'
          : 'Supabase operation failed: $operation';
      log(errorMessage, level: 'ERROR', tag: 'SUPABASE');
    }
  }

  static void logMapOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      final message = data != null
          ? 'Map operation successful: $operation (data: $data)'
          : 'Map operation successful: $operation';
      info(message, tag: 'MAP');
    } else {
      final errorMessage = error != null
          ? 'Map operation failed: $operation (error: $error)'
          : 'Map operation failed: $operation';
      log(errorMessage, level: 'ERROR', tag: 'MAP');
    }
  }

  static void logLocationOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      final message = data != null
          ? 'Location operation successful: $operation (data: $data)'
          : 'Location operation successful: $operation';
      info(message, tag: 'LOCATION');
    } else {
      final errorMessage = error != null
          ? 'Location operation failed: $operation (error: $error)'
          : 'Location operation failed: $operation';
      log(errorMessage, level: 'ERROR', tag: 'LOCATION');
    }
  }

  static void logRideOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      final message = data != null
          ? 'Ride operation successful: $operation (data: $data)'
          : 'Ride operation successful: $operation';
      info(message, tag: 'RIDE');
      if (data != null) {
        debug('Ride data: $data', tag: 'RIDE');
      }
    } else {
      final errorMessage = error != null
          ? 'Ride operation failed: $operation (error: $error)'
          : 'Ride operation failed: $operation';
      log(errorMessage, level: 'ERROR', tag: 'RIDE');
    }
  }

  static void logDriverOperation(String operation,
      {bool success = true, String? error, dynamic data}) {
    if (success) {
      final message = data != null
          ? 'Driver operation successful: $operation (data: $data)'
          : 'Driver operation successful: $operation';
      info(message, tag: 'DRIVER');
      if (data != null) {
        debug('Driver data: $data', tag: 'DRIVER');
      }
    } else {
      final errorMessage = error != null
          ? 'Driver operation failed: $operation (error: $error)'
          : 'Driver operation failed: $operation';
      log(errorMessage, level: 'ERROR', tag: 'DRIVER');
    }
  }
}
