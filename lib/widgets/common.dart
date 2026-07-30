import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:provider/provider.dart';
import '../utils/theme.dart';
import '../services/theme_controller.dart';

// ─── Card ─────────────────────────────────────────────
// Solid surface, hairline border, one soft shadow. The `blurSigma` parameter
// is retained for call-site compatibility but no longer has any effect —
// the minimal design uses no blur or translucency.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final double blurSigma;
  final double borderRadius;
  final Color? tint;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.blurSigma = 0,
    this.borderRadius = AppRadius.card,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.card),
      child: child,
    );
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        // Tinted cards (banners, notices): ≤10% alpha fill, no border.
        color: tint != null ? tint!.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: radius,
        border: tint != null ? null : Border.all(color: AppColors.border),
        boxShadow: tint != null
            ? null
            : [
                BoxShadow(
                  color: AppColors.gray900.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: onTap != null
          ? Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: inner,
              ),
            )
          : inner,
    );
  }
}

// ─── Badge ────────────────────────────────────────────
// Flat tinted chip: ≤10% alpha background, no border.
class GlassBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  const GlassBadge({super.key, required this.text, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }
}

// ─── App Card ─────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: padding,
      onTap: onTap,
      tint: color,
      child: child,
    );
  }
}

// ─── Status Badge ─────────────────────────────────────
class StatusBadge extends StatelessWidget {
  final String status;
  final bool small;
  const StatusBadge({super.key, required this.status, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 8 : 10, vertical: small ? 3 : 5),
      decoration: BoxDecoration(
        color: StatusColors.bg(status),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(StatusColors.icon(status), size: small ? 10 : 12, color: StatusColors.fg(status)),
          const SizedBox(width: 4),
          Text(
            StatusColors.label(status),
            style: TextStyle(fontSize: small ? 10 : 11, fontWeight: FontWeight.w700, color: StatusColors.fg(status)),
          ),
        ],
      ),
    );
  }
}

// ─── Avatar ───────────────────────────────────────────
class UserAvatar extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final double size;
  const UserAvatar({super.key, required this.name, this.imageUrl, this.size = 40});

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final themeController = context.watch<ThemeController>();
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: imageUrl != null ? Colors.transparent : themeController.palette.primary,
        borderRadius: BorderRadius.circular(size / 2),
        border: Border.all(color: AppColors.border),
        image: imageUrl != null
            ? DecorationImage(image: NetworkImage(imageUrl!), fit: BoxFit.cover)
            : null,
      ),
      child: imageUrl == null
          ? Center(child: Text(_initials, style: TextStyle(color: Colors.white, fontSize: size * 0.35, fontWeight: FontWeight.w700)))
          : null,
    );
  }
}

// ─── Primary Button ───────────────────────────────────
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final bool outline;
  final Color? color;
  final IconData? icon;
  final bool fullWidth;
  const AppButton({
    super.key, required this.label, this.onPressed,
    this.loading = false, this.outline = false,
    this.color, this.icon, this.fullWidth = true,
  });

  @override
  Widget build(BuildContext context) {
    final themePrimary = Theme.of(context).colorScheme.primary;
    final fill = color ?? themePrimary;

    final buttonChild = loading
        ? SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: outline ? fill : Colors.white,
            ))
        : Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]);

    if (outline) {
      return SizedBox(
        width: fullWidth ? double.infinity : null, height: 50,
        child: OutlinedButton(
          onPressed: loading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: fill,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          child: buttonChild,
        ),
      );
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null, height: 50,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: fill,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.gray200,
          disabledForegroundColor: AppColors.gray500,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
        child: buttonChild,
      ),
    );
  }
}

// ─── Shimmer Skeleton ─────────────────────────────────
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  const SkeletonBox({super.key, required this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.gray200,
      highlightColor: AppColors.gray100,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: AppColors.gray200,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ─── Section Header ───────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTextStyles.title),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ─── KPI Chip ─────────────────────────────────────────
class KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool compact;

  const KpiChip({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 8 : 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: compact ? 18 : 24,
                  fontWeight: FontWeight.w700,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.gray500)),
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;
  const EmptyStateWidget({super.key, required this.icon, required this.title, required this.description, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: AppColors.gray100,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Icon(icon, color: AppColors.gray400, size: 28),
            ),
            const SizedBox(height: AppSpacing.x4),
            Text(title, style: AppTextStyles.title),
            const SizedBox(height: 6),
            Text(description, textAlign: TextAlign.center, style: AppTextStyles.body),
            if (action != null) ...[const SizedBox(height: AppSpacing.x5), action!],
          ],
        ),
      ),
    );
  }
}

// ─── Detail Row ───────────────────────────────────────
class GlassDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  final Color? highlightColor;

  const GlassDetailRow({
    super.key,
    required this.label,
    required this.value,
    this.highlight = false,
    this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.body),
          const SizedBox(width: AppSpacing.x3),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                    color: highlight
                        ? (highlightColor ?? Theme.of(context).colorScheme.primary)
                        : AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

Widget glassDetailRow(String label, String value,
        {bool highlight = false, Color? highlightColor}) =>
    GlassDetailRow(
        label: label,
        value: value,
        highlight: highlight,
        highlightColor: highlightColor);

// ─── Accent Icon (legacy gradient signature) ──────────
// Renders a flat single-color icon; the gradient's first stop is used as the
// color so existing `Gradient`-typed call sites keep working.
class GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final Gradient gradient;

  const GradientIcon({
    super.key,
    required this.icon,
    this.size = 24,
    this.gradient = AppGradients.aurora,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(icon, size: size, color: gradient.colors.first);
  }
}

// ─── Confirm Dialog ───────────────────────────────────
Future<bool?> showConfirmDialog(BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool isDanger = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel', style: TextStyle(color: AppColors.gray500)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? AppColors.danger500 : Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
