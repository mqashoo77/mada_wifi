import 'package:flutter/material.dart';

class AppDialog extends StatelessWidget {
  final Widget title;
  final List<Widget> fields;
  final List<Widget> actions;
  final double spacing;
  const AppDialog({
    super.key,
    required this.title,
    required this.fields,
    required this.actions,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: title,
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: spacing,
            children: fields,
          ),
        ),
      ),
      actions: actions,
    );
  }
}

class DialogError extends StatelessWidget {
  final String text;
  const DialogError(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
        ),
      ]),
    );
  }
}
