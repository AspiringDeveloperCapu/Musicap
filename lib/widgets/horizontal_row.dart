import 'package:flutter/material.dart';

/// A horizontally scrollable section with a title, edge chevron buttons and a
/// always-visible scrollbar, so content past the right edge stays reachable
/// with a mouse (wheel scrolling alone only moves vertically on the web).
class HorizontalRow extends StatefulWidget {
  /// Optional section title; chevrons only render when a title is present.
  final String? title;

  /// Optional widget trailing the title (e.g. a "See all" button).
  final Widget? titleTrailing;

  /// Height of the list itself (scrollbar sits below it).
  final double height;

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;

  /// Extra width inserted after each item.
  final double itemSpacing;

  const HorizontalRow({
    super.key,
    this.title,
    this.titleTrailing,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 12),
    this.itemSpacing = 0,
  });

  @override
  State<HorizontalRow> createState() => _HorizontalRowState();
}

class _HorizontalRowState extends State<HorizontalRow> {
  final ScrollController _controller = ScrollController();
  bool _canLeft = false;
  bool _canRight = false;
  bool _overflowing = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
  }

  @override
  void didUpdateWidget(covariant HorizontalRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateEdges());
    }
  }

  void _updateEdges() {
    if (!_controller.hasClients || !mounted) return;
    final position = _controller.position;
    final canLeft = position.pixels > position.minScrollExtent + 1;
    final canRight = position.pixels < position.maxScrollExtent - 1;
    final overflowing =
        position.maxScrollExtent > position.minScrollExtent + 1;
    if (canLeft != _canLeft ||
        canRight != _canRight ||
        overflowing != _overflowing) {
      setState(() {
        _canLeft = canLeft;
        _canRight = canRight;
        _overflowing = overflowing;
      });
    }
  }

  void _scrollBy(double fraction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final target = (position.pixels + fraction * position.viewportDimension)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _showHeader =>
      widget.title != null || widget.titleTrailing != null;

  Widget _buildArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 28),
      color: enabled
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.onSurface.withOpacity(0.25),
      tooltip: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                if (widget.title != null)
                  Text(
                    widget.title!,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                const Spacer(),
                if (widget.titleTrailing != null) widget.titleTrailing!,
                if (_overflowing) ...[
                  _buildArrow(
                    icon: Icons.chevron_left,
                    enabled: _canLeft,
                    onPressed: () => _scrollBy(-0.75),
                  ),
                  _buildArrow(
                    icon: Icons.chevron_right,
                    enabled: _canRight,
                    onPressed: () => _scrollBy(0.75),
                  ),
                ],
              ],
            ),
          ),
        // Scrollbar needs room below the list for its thumb.
        SizedBox(
          height: widget.height + 10,
          child: Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            interactive: true,
            thickness: 5,
            radius: const Radius.circular(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: widget.height,
                  child: ListView.builder(
                    controller: _controller,
                    scrollDirection: Axis.horizontal,
                    padding: widget.padding,
                    itemCount: widget.itemCount,
                    itemBuilder: (context, index) {
                      final child = widget.itemBuilder(context, index);
                      if (widget.itemSpacing <= 0) return child;
                      return Padding(
                        padding: EdgeInsets.only(right: widget.itemSpacing),
                        child: child,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
