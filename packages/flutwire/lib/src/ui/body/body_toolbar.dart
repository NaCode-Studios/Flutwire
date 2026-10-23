import 'package:flutter/material.dart';

import '../scope.dart';

/// One mode of the viewer, as a pill the user can pick.
class ModeChip extends StatelessWidget {
  /// Creates a pill that says [label].
  const ModeChip({
    super.key,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  /// The name of the mode.
  final String label;

  /// Whether this is the mode in force.
  final bool selected;

  /// Whether the mode can be picked.
  final bool enabled;

  /// Called when the pill is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    final color = !enabled
        ? tokens.faint.withValues(alpha: 0.6)
        : selected
        ? tokens.ink
        : tokens.muted;
    // The pill is the touch target: 40 logical pixels tall, like the icon
    // buttons beside it, so the ink of a press fills it exactly.
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? tokens.lineStrong : Colors.transparent,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      child: Material(
        color: selected ? tokens.raised : Colors.transparent,
        shape: shape,
        animationDuration: Duration.zero,
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: shape,
          child: SizedBox(
            height: 40,
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  label,
                  style: tokens.mono(
                    size: 12.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon button of the toolbar: 40 logical pixels square, quiet until it is
/// switched on.
class ToolButton extends StatelessWidget {
  /// Creates a button that shows [icon].
  const ToolButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  /// The icon.
  final IconData icon;

  /// What the button does, said aloud and on hover.
  final String tooltip;

  /// Called when the button is pressed.
  final VoidCallback onPressed;

  /// Whether the thing the button switches is on.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: selected,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        foregroundColor: selected ? tokens.ink : tokens.muted,
        backgroundColor: selected ? tokens.raised : Colors.transparent,
        fixedSize: const Size.square(40),
        minimumSize: const Size.square(40),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// One line of a copy or save menu: what it says and what it does.
class MenuEntry {
  /// Creates an entry.
  const MenuEntry(this.label, this.run);

  /// The text of the menu line.
  final String label;

  /// What choosing it does.
  final Future<void> Function() run;
}

/// A toolbar button that opens a menu of [MenuEntry]s, built when it opens.
class MenuButton extends StatelessWidget {
  /// Creates a button that shows [icon] and lists [entries].
  const MenuButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.entries,
    required this.onSelected,
  });

  /// The icon.
  final IconData icon;

  /// What the menu is for, said aloud and on hover.
  final String tooltip;

  /// Works out the lines of the menu. It runs when the menu opens, so
  /// something costly to prepare is prepared only if it is wanted.
  final List<MenuEntry> Function() entries;

  /// Called with the entry that was chosen.
  final Future<void> Function(MenuEntry entry) onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MenuEntry>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final entry in entries())
          PopupMenuItem(value: entry, child: Text(entry.label)),
      ],
      child: ToolIcon(icon: icon, color: context.fw.muted),
    );
  }
}

/// The icon of a toolbar button that opens a menu: the size of a [ToolButton]
/// without the button around it.
class ToolIcon extends StatelessWidget {
  /// Creates the icon in [color].
  const ToolIcon({super.key, required this.icon, required this.color});

  /// The icon.
  final IconData icon;

  /// Its colour.
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: 40, child: Icon(icon, size: 20, color: color));
}

/// A note above the content: the body was cut, or it was decoded.
class NoteBanner extends StatelessWidget {
  /// Creates a note with [text] beside [icon], tinted with [color].
  const NoteBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  /// The icon at the start of the note.
  final IconData icon;

  /// The colour of the icon and of the tint behind the note.
  final Color color;

  /// What the note says.
  final String text;

  /// The label of the button at the end of the note, if it has one.
  final String? actionLabel;

  /// Called when that button is pressed.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = context.fw;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.only(left: 12),
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        color: tokens.tint(color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                text,
                style: tokens.body(size: 12.5, color: tokens.text),
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: tokens.syntaxKey,
                minimumSize: const Size(40, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: tokens.body(size: 12.5, weight: FontWeight.w600),
              ),
              child: Text(actionLabel!),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}
