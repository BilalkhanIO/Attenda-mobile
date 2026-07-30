import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../utils/theme.dart';
import '../../../widgets/common.dart';

// ─── Shift Card ────────────────────────────────────────

class ShiftCard extends StatelessWidget {
  final String shiftName;
  final String startTime;
  final String endTime;
  final Color shiftColor;
  final String? dateStr; // ISO date; null hides the trailing date label

  const ShiftCard(
      {super.key,
      required this.shiftName,
      required this.startTime,
      required this.endTime,
      required this.shiftColor,
      required this.dateStr});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Row(children: [
        Container(
          width: 4,
          height: 52,
          decoration: BoxDecoration(
              color: shiftColor, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shiftName, style: AppTextStyles.title),
          const SizedBox(height: 3),
          Text('$startTime – $endTime',
              style: AppTextStyles.body
                  .copyWith(fontFeatures: [FontFeature.tabularFigures()])),
        ])),
        if (dateStr != null)
          Text(DateFormat('EEE, d MMM').format(DateTime.parse(dateStr!)),
              style: AppTextStyles.caption),
      ]),
    );
  }
}
