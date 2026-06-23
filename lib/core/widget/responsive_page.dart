import 'package:flutter/material.dart';

class ResponsivePage extends StatelessWidget {
  const ResponsivePage({
    super.key,
    required this.child,
    this.maxWidth = 920,
    this.padding = const EdgeInsets.all(16),
    this.alignment = Alignment.topCenter,
    this.safeAreaTop = false,
    this.safeAreaBottom = false,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;
  final bool safeAreaTop;
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: safeAreaTop,
      bottom: safeAreaBottom,
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class ResponsiveListPage extends StatelessWidget {
  const ResponsiveListPage({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.safeAreaBottom = true,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  final bool safeAreaBottom;

  @override
  Widget build(BuildContext context) {
    return ResponsivePage(
      maxWidth: maxWidth,
      padding: EdgeInsets.zero,
      safeAreaBottom: safeAreaBottom,
      child: ListView(padding: padding, children: children),
    );
  }
}

class SliverResponsivePage extends StatelessWidget {
  const SliverResponsivePage({
    super.key,
    required this.sliver,
    this.maxWidth = 920,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget sliver;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final availableWidth = constraints.crossAxisExtent - resolvedPadding.horizontal;
        final extraInset = availableWidth > maxWidth ? (availableWidth - maxWidth) / 2 : 0.0;
        return SliverPadding(
          padding: resolvedPadding.copyWith(
            left: resolvedPadding.left + extraInset,
            right: resolvedPadding.right + extraInset,
          ),
          sliver: sliver,
        );
      },
    );
  }
}
