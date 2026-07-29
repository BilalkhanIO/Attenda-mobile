import 'dart:ui';
import 'package:flutter/material.dart';

// ─── Quick Actions ─────────────────────────────────────

class QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const QuickAction(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
}

/// Renders the row of glass quick-action tiles. Which actions appear (feature
/// flags, attendance state) is decided by the caller.
class QuickActionsRow extends StatelessWidget {
  final List<QuickAction> actions;
  const QuickActionsRow({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: actions
          .map((a) => Expanded(
                  child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: a.onTap,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              a.color.withValues(alpha: 0.22),
                              a.color.withValues(alpha: 0.1)
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border:
                              Border.all(color: a.color.withValues(alpha: 0.3)),
                        ),
                        child: Column(children: [
                          Icon(a.icon, color: a.color, size: 24),
                          const SizedBox(height: 6),
                          Text(a.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: a.color,
                                  height: 1.3)),
                        ]),
                      ),
                    ),
                  ),
                ),
              )))
          .toList(),
    );
  }
}
