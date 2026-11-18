import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class WorkerDestination {
  const WorkerDestination(this.label, this.icon, {this.unread = false});

  final String label;
  final IconData icon;
  final bool unread;
}

class WorkerBottomNavigation extends StatelessWidget {
  const WorkerBottomNavigation({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<WorkerDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26192D48),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xCFFFFFFF), Color(0xADDBE5F5)],
              ),
              border: Border.all(color: const Color(0xCFFFFFFF)),
              borderRadius: BorderRadius.circular(36),
            ),
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                height: 72,
                child: Row(
                  children: [
                    for (var index = 0; index < destinations.length; index++)
                      _tab(context, index, destinations[index]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _tab(BuildContext context, int index, WorkerDestination destination) {
    final selected = selectedIndex == index;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final color = selected ? WorkerColors.deepBlue : AppColors.navy;
    void select() => onDestinationSelected(index);
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: destination.unread
            ? '${destination.label}, unread notifications'
            : destination.label,
        onTap: select,
        child: ExcludeSemantics(
          child: InkWell(
            onTap: select,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: AnimatedContainer(
                  duration: duration,
                  constraints: const BoxConstraints(
                    minWidth: 60,
                    minHeight: 55,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: selected
                          ? const [Color(0x88A1B7E4), Color(0xDCFFFFFF)]
                          : const [Colors.transparent, Colors.transparent],
                    ),
                    shape: StadiumBorder(
                      side: BorderSide(
                        color: selected
                            ? const Color(0x688195BB)
                            : Colors.transparent,
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Badge(
                        isLabelVisible: destination.unread,
                        child: Icon(destination.icon, size: 22, color: color),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
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
  }
}
