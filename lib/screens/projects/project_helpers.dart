import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

String projectLabel(String value) => value
    .split('_')
    .where((part) => part.isNotEmpty)
    .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
    .join(' ');

Color projectStatusColor(String value) {
  const known = <String, Color>{
    'planning': AppColors.gray500,
    'todo': AppColors.gray500,
    'active': AppColors.info500,
    'in_progress': AppColors.info500,
    'on_hold': AppColors.warning500,
    'blocked': AppColors.danger500,
    'completed': AppColors.success500,
    'done': AppColors.success500,
    'cancelled': AppColors.danger500,
  };
  final existingColor = known[value];
  if (existingColor != null) return existingColor;
  var hash = 0;
  for (final code in value.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  return [
    AppColors.purple500,
    AppColors.info500,
    AppColors.teal700,
    AppColors.warning500,
  ][hash % 4];
}

Color projectPriorityColor(String value) => switch (value) {
      'urgent' => AppColors.danger500,
      'high' => AppColors.warning500,
      'low' => AppColors.gray500,
      _ => AppColors.info500,
    };

String projectDate(dynamic value, {String fallback = 'Not set'}) {
  if (value == null) return fallback;
  final date = DateTime.tryParse(value.toString());
  if (date == null) return fallback;
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

Widget projectBadge(String label, Color color) => GlassBadge(
      text: projectLabel(label),
      color: color,
    );

Future<DateTime?> pickProjectDate(BuildContext context, DateTime? initial) =>
    showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

String? apiDate(DateTime? date) => date == null
    ? null
    : '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
