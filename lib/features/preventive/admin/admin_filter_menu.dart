import 'package:flutter/material.dart';

import 'pointer_hover_fill.dart';

class AdminFilterMenu extends StatefulWidget {
  const AdminFilterMenu({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label, value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  State<AdminFilterMenu> createState() => _AdminFilterMenuState();
}

class _AdminFilterMenuState extends State<AdminFilterMenu> {
  final _triggerFocus = FocusNode();
  static const _focusOverlay = WidgetStateProperty<Color?>.fromMap({
    WidgetState.focused: Colors.black12,
    WidgetState.any: Colors.transparent,
  });

  @override
  void dispose() {
    _triggerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.hasBoundedWidth ? constraints.maxWidth : 240.0;
      return MenuAnchor(
        childFocusNode: _triggerFocus,
        alignmentOffset: const Offset(0, 6),
        clipBehavior: Clip.antiAlias,
        onOpen: () => setState(() {}),
        onClose: () => setState(() {}),
        style: MenuStyle(
          backgroundColor: const WidgetStatePropertyAll(Colors.white),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: const WidgetStatePropertyAll(Color(0x38172940)),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 6),
          ),
          fixedSize: WidgetStatePropertyAll(Size(width, double.infinity)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        menuChildren: [
          for (final option in widget.options.entries)
            Semantics(
              selected: option.key == widget.value,
              child: MenuItemButton(
                requestFocusOnHover: false,
                onPressed: () => widget.onChanged(option.key),
                style: MenuItemButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size(width, 44),
                  alignment: AlignmentDirectional.centerStart,
                  shape: const RoundedRectangleBorder(),
                ).copyWith(overlayColor: _focusOverlay),
                child: SizedBox(
                  width: width,
                  child: PointerHoverFill(
                    minHeight: 44,
                    content: (color) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        option.value,
                        style: TextStyle(
                          color: color,
                          fontWeight: option.key == widget.value
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        builder: (context, controller, _) => Semantics(
          expanded: controller.isOpen,
          child: SizedBox(
            width: width,
            child: OutlinedButton(
              focusNode: _triggerFocus,
              clipBehavior: Clip.antiAlias,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: EdgeInsets.zero,
                minimumSize: Size(width, 52),
                alignment: AlignmentDirectional.centerStart,
                side: const BorderSide(color: Colors.black26),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ).copyWith(overlayColor: _focusOverlay),
              child: SizedBox(
                width: width,
                child: PointerHoverFill(
                  minHeight: 52,
                  content: (color) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(color: color, fontSize: 12),
                        ),
                        Text(
                          widget.options[widget.value] ?? widget.value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: color),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
