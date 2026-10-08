import 'package:flutter/material.dart';

/// Asks whether to throw away unsaved edits; true means discard.
Future<bool> confirmDiscard(
  BuildContext context, {
  required String title,
  required String body,
  required String discardLabel,
  required String keepLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(keepLabel)),
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(discardLabel)),
      ],
    ),
  );
  return result ?? false;
}
