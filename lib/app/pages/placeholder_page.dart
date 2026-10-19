// A page whose feature is not built yet: header plus one line of text.

import 'package:flutter/material.dart';
import 'package:taskpin_design/taskpin_design.dart';

import '../shell/app_page.dart';

/// Page header and a centered empty state with one line.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.message,
    this.icon,
  });

  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: title,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 64),
          child: TpEmptyState(title: message, icon: icon),
        ),
      ],
    );
  }
}
