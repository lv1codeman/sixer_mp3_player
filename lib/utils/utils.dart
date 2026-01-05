// 自製全域toast
import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

//  自訂提示toast
void myToast(String message, {double durationSeconds = 2.0}) {
  final overlayState = navigatorKey.currentState?.overlay;
  if (overlayState == null) return;

  late OverlayEntry overlayEntry;
  overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).size.height * 0.5,
      width: MediaQuery.of(context).size.width,
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 12.0,
            ),
            margin: const EdgeInsets.symmetric(horizontal: 20.0),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(25.0),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16.0),
            ),
          ),
        ),
      ),
    ),
  );

  overlayState.insert(overlayEntry);

  Future.delayed(Duration(milliseconds: (durationSeconds * 1000).toInt()), () {
    overlayEntry.remove();
  });
}

// 自訂全域確認對話框，支援自訂標題、內容與確認後的回呼
void myConfirmDialog({
  required String title,
  required String content,
  required VoidCallback onConfirm,
  String confirmText = "確定",
  String cancelText = "取消",
  Color confirmColor = Colors.red,
}) {
  final context = navigatorKey.currentContext;
  if (context == null) return;

  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(cancelText),
        ),
        TextButton(
          onPressed: () {
            onConfirm(); // 執行傳入的刪除動作
            Navigator.pop(ctx);
          },
          child: Text(confirmText, style: TextStyle(color: confirmColor)),
        ),
      ],
    ),
  );
}
