import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../utils/theme.dart';

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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(StatusColors.icon(status), size: small ? 10 : 12, color: StatusColors.fg(status)),
          const SizedBox(width: 4),
          Text(
            StatusColors.label(status),
            style: TextStyle(fontSize: small ? 10 : 11, fontWeight: FontWeight.w600, color: StatusColors.fg(status)),
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
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: AppColors.primary600,
        borderRadius: BorderRadius.circular(size / 2),
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

// ─── App Card ─────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gray200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: onTap != null
          ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16), child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child))
          : Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
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
    final bg   = color ?? AppColors.primary600;
    final child = loading
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)))
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16), const SizedBox(width: 8)],
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ],
          );

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      height: 50,
      child: outline
          ? OutlinedButton(
              onPressed: loading ? null : onPressed,
              style: OutlinedButton.styleFrom(foregroundColor: bg, side: BorderSide(color: bg), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: child,
            )
          : ElevatedButton(
              onPressed: loading ? null : onPressed,
              style: ElevatedButton.styleFrom(backgroundColor: bg, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
              child: child,
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
      baseColor: AppColors.gray100,
      highlightColor: AppColors.gray50,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(radius)),
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
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark950)),
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
  final Color bg;
  const KpiChip({super.key, required this.label, required this.value, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color.withOpacity(0.8))),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: AppColors.gray100, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: AppColors.gray500, size: 26),
            ),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.dark950)),
            const SizedBox(height: 6),
            Text(description, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.gray500)),
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      content: Text(message, style: const TextStyle(color: AppColors.gray500)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDanger ? AppColors.danger500 : AppColors.primary600,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}
