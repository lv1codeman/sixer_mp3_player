import 'package:flutter/foundation.dart';

class Logger {
  static const String _tag = "SixerMP3";

  /// 一般訊息 (藍色)
  static void i(String message) {
    _printLog("INFO", message, "🟦");
  }

  /// 調試訊息 (綠色)
  static void d(String message) {
    if (kDebugMode) {
      _printLog("DEBUG", message, "🟩");
    }
  }

  /// 警告訊息 (黃色)
  static void w(String message) {
    _printLog("WARN", message, "🟧");
  }

  /// 錯誤訊息 (紅色)
  static void e(String message, [dynamic error, StackTrace? stack]) {
    _printLog("ERROR", message, "🟥");
    if (error != null) {
      debugPrint("   └─ Error: $error");
    }
    if (stack != null) {
      debugPrint("   └─ Stack: $stack");
    }
  }

  static void _printLog(String level, String message, String emoji) {
    final time = DateTime.now().toString().split(' ').last.substring(0, 12);
    // 使用 debugPrint 確保在大訊息時不會被 Android 系統截斷
    debugPrint("$emoji [$level][$time][$_tag] $message");
  }
}
