// lib/widgets/mini_player.dart
import 'package:flutter/material.dart';

class SubHeader extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SubHeader({super.key, required this.text, this.trailing});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Container(
        width: double.infinity,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white10
            : Colors.black12,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(text, style: const TextStyle(fontSize: 12)),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
