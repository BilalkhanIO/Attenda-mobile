import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/common.dart';

class OpenShiftsScreen extends StatefulWidget {
  const OpenShiftsScreen({super.key});
  @override
  State<OpenShiftsScreen> createState() => _OpenShiftsScreenState();
}

class _OpenShiftsScreenState extends State<OpenShiftsScreen> {
  List<Map<String, dynamic>> _offers = [];
  bool _loading = true;
  String? _error;
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final offers = await api.getOpenShiftOffers();
      if (!mounted) return;
      setState(() {
        _offers = offers.cast<Map<String, dynamic>>();
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiFailure.fromError(error).userMessage;
        _loading = false;
      });
    }
  }

  Future<void> _claim(Map<String, dynamic> offer) async {
    final id = offer['id'] as String?;
    if (id == null) return;
    setState(() => _busyId = id);
    try {
      await api.claimOpenShift(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Shift claimed and added to your schedule.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
      await _load();
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _cancel(Map<String, dynamic> offer) async {
    final id = offer['id'] as String?;
    if (id == null) return;
    setState(() => _busyId = id);
    try {
      await api.cancelOpenShiftOffer(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency offer withdrawn.')));
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  DateTime _offerDate(String value) {
    final parts = value.substring(0, 10).split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  Future<void> _createOffer() async {
    try {
      final templates =
          (await api.getShiftTemplates()).cast<Map<String, dynamic>>();
      if (!mounted) return;
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Create a shift template before offering emergency cover.')));
        return;
      }
      final created = await showModalBottomSheet<bool>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _EmergencyOfferSheet(templates: templates),
      );
      if (created == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Emergency offer sent to eligible employees.')));
        await _load();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency shifts'),
        actions: [
          if (auth.hasPermission('shifts.assign'))
            IconButton(
                tooltip: 'Offer an emergency shift',
                onPressed: _createOffer,
                icon: const Icon(Icons.add_alert_rounded)),
        ],
      ),
      body: RefreshIndicator(
        color: primary,
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 90),
                    EmptyStateWidget(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not load open shifts',
                        description: _error!,
                        action: AppButton(
                            label: 'Retry', onPressed: _load, fullWidth: false))
                  ])
                : _offers.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 70),
                        EmptyStateWidget(
                            icon: Icons.notifications_none_rounded,
                            title: 'No emergency shifts',
                            description:
                                'Open shifts will appear here when your team needs extra cover.')
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                        itemCount: _offers.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final offer = _offers[index];
                          final shift = (offer['shift'] as Map?)
                                  ?.cast<String, dynamic>() ??
                              const <String, dynamic>{};
                          final eligibility = (offer['eligibility'] as Map?)
                                  ?.cast<String, dynamic>() ??
                              const <String, dynamic>{};
                          final canClaim = eligibility['can_claim'] != false;
                          final id = offer['id'] as String? ?? '';
                          final color =
                              parseHexColor(shift['color'] as String?);
                          final expiresAt = DateTime.tryParse(
                                  offer['expires_at'] as String? ?? '')
                              ?.toLocal();
                          return GlassCard(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                            width: 4,
                                            height: 52,
                                            decoration: BoxDecoration(
                                                color: color,
                                                borderRadius:
                                                    BorderRadius.circular(3))),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(
                                                  shift['name'] as String? ??
                                                      'Shift',
                                                  style: AppTextStyles.title),
                                              const SizedBox(height: 5),
                                              Text(
                                                  '${_offerDate(offer['date'] as String).toLocal().toString().split(' ').first} · ${shift['start_time'] ?? '--'}–${shift['end_time'] ?? '--'}',
                                                  style:
                                                      AppTextStyles.bodyStrong),
                                            ])),
                                        const GlassBadge(
                                            text: 'URGENT',
                                            color: AppColors.warning500,
                                            icon: Icons.bolt_rounded),
                                      ]),
                                  if ((offer['note'] as String?)?.isNotEmpty ==
                                      true) ...[
                                    const SizedBox(height: 12),
                                    Text(offer['note'] as String,
                                        style: AppTextStyles.body),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                      expiresAt == null
                                          ? 'Offer expires soon'
                                          : 'Claim by ${DateFormat('EEE, h:mm a').format(expiresAt)}',
                                      style: AppTextStyles.caption),
                                  if (!canClaim) ...[
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      const Icon(Icons.info_outline_rounded,
                                          size: 15,
                                          color: AppColors.warning500),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              eligibility['reason']
                                                      as String? ??
                                                  'This shift conflicts with your schedule.',
                                              style: const TextStyle(
                                                  color: AppColors.warning800,
                                                  fontSize: 12)))
                                    ]),
                                  ],
                                  const SizedBox(height: 12),
                                  if (canClaim)
                                    SizedBox(
                                        width: double.infinity,
                                        child: AppButton(
                                            label: 'Claim shift',
                                            icon: Icons
                                                .check_circle_outline_rounded,
                                            loading: _busyId == id,
                                            onPressed: () => _claim(offer)))
                                  else if (auth.hasPermission('shifts.assign'))
                                    AppButton(
                                        label: 'Withdraw offer',
                                        icon: Icons.close_rounded,
                                        loading: _busyId == id,
                                        onPressed: () => _cancel(offer),
                                        outline: true),
                                ]),
                          );
                        },
                      ),
      ),
    );
  }
}

class _EmergencyOfferSheet extends StatefulWidget {
  const _EmergencyOfferSheet({required this.templates});
  final List<Map<String, dynamic>> templates;
  @override
  State<_EmergencyOfferSheet> createState() => _EmergencyOfferSheetState();
}

class _EmergencyOfferSheetState extends State<_EmergencyOfferSheet> {
  late String _shiftId = widget.templates.first['id'] as String;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  int _expiryMinutes = 240;
  final TextEditingController _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(today.year, today.month, today.day),
        lastDate: today.add(const Duration(days: 90)));
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      await api.createOpenShiftOffer(
          shiftId: _shiftId,
          date: DateFormat('yyyy-MM-dd').format(_date),
          expiresInMinutes: _expiryMinutes,
          note: _note.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.card))),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: SafeArea(
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              const Text('Offer an emergency shift',
                  style: AppTextStyles.display),
              const SizedBox(height: 6),
              const Text(
                  'Eligible employees with no shift or approved leave that day will be notified.',
                  style: AppTextStyles.body),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _shiftId,
                decoration: const InputDecoration(labelText: 'Shift template'),
                items: widget.templates
                    .map((item) => DropdownMenuItem(
                        value: item['id'] as String,
                        child: Text(
                            '${item['name']} · ${item['start_time']}–${item['end_time']}')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _shiftId = value);
                },
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(DateFormat('EEE, d MMM yyyy').format(_date))),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                initialValue: _expiryMinutes,
                decoration: const InputDecoration(labelText: 'Offer expiry'),
                items: const [
                  DropdownMenuItem(value: 30, child: Text('30 minutes')),
                  DropdownMenuItem(value: 60, child: Text('1 hour')),
                  DropdownMenuItem(value: 240, child: Text('4 hours')),
                  DropdownMenuItem(value: 720, child: Text('12 hours')),
                  DropdownMenuItem(value: 1440, child: Text('24 hours')),
                  DropdownMenuItem(value: 10080, child: Text('7 days'))
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _expiryMinutes = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                  controller: _note,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Message to the team (optional)',
                      hintText: 'Why is extra cover needed?')),
              const SizedBox(height: 16),
              SizedBox(
                  width: double.infinity,
                  child: AppButton(
                      label: 'Notify eligible employees',
                      icon: Icons.notifications_active_outlined,
                      loading: _saving,
                      onPressed: _submit)),
            ]))),
      ),
    );
  }
}
