import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../constants/app_colors.dart';
import '../models/booking_slot.dart';
import '../models/product.dart';
import '../services/api_service.dart';

/// Lets the customer pick an available booking slot (date + time) for a
/// bookable product. Pops with the selected [BookingSlot] on confirm.
class BookingSlotPickerScreen extends StatefulWidget {
  final Product product;

  const BookingSlotPickerScreen({super.key, required this.product});

  @override
  State<BookingSlotPickerScreen> createState() => _BookingSlotPickerScreenState();
}

class _BookingSlotPickerScreenState extends State<BookingSlotPickerScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  String? _error;
  List<BookingSlot> _slots = [];

  DateTime? _selectedDate;
  BookingSlot? _selectedSlot;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  // ── Booking meta window constants (Dokan form defaults) ─────────────
  // From bookingproductcreation.php lines 1939-1963:
  //   _wc_booking_min_date       = 0 (today allowed, default)
  //   _wc_booking_min_date_unit  = month/day
  //   _wc_booking_max_date       = 12 (default, NOT 9!)
  //   _wc_booking_max_date_unit  = month
  //   _wc_booking_default_date_availability = available|nonavailable
  //   _wc_booking_first_block_time = "HH:MM" (default empty = 09:00)
  //   _wc_booking_restricted_days[0..6] = checkbox: disabled (checked=non-bookable)
  // If the product has no meta or they're empty we default to Dokan's form defaults.
  int get _wcBookingMaxDays {
    final p = widget.product;
    final rawVal = p.bookingMaxDateVal;
    final unit  = (p.bookingMaxDateUnit ?? 'month').toLowerCase();
    final daysInUnit = <String, int>{
      'minute': 1, 'hour': 1, 'day': 1, 'week': 7, 'month': 30, 'year': 365,
    };
    if (rawVal == null) return 365;          // default: 12 months
    final d = daysInUnit[unit] ?? 30;
    return (rawVal * d).clamp(1, 365 * 2);
  }

  int get _wcBookingMinDays {
    final p = widget.product;
    final rawVal = p.bookingMinDateVal;
    if (rawVal == null) return 0;
    final unit = (p.bookingMinDateUnit ?? 'day').toLowerCase();
    final daysInUnit = <String, int>{
      'minute': 0, 'hour': 0, 'day': 1, 'week': 7, 'month': 30, 'year': 365,
    };
    final d = daysInUnit[unit] ?? 1;
    return (rawVal * d).clamp(0, 365 * 2);
  }

  List<int> get _wcBookingRestrictedWeekdays {
    final restricted = widget.product.bookingRestrictedDays;
    if (restricted == null || restricted.isEmpty) return const [];
    // Mapping: Dokan restricted_days uses 0=Sun..6=Sat (checkbox array index).
    // Dart DateTime.weekday uses ISO8601 1=Mon..7=Sun — convert when comparing.
    return restricted;
  }

  int _parseFirstBlockHour(String? val) {
    if (val == null || val.isEmpty) return 9;
    final parts = val.split(RegExp(r'[:\s]'));
    if (parts.isEmpty) return 9;
    final h = int.tryParse(parts.first) ?? 9;
    return h.clamp(6, 22);
  }
  int _parseLastBlockHour(String? val) {
    // Dokan sets last block from first_block + (duration * number of units).
    // For fallback: default first block was 09:00, duration=1 hour, count=9 slots →
    // last slot starts at 17:00.
    final p = widget.product;
    final firstH = _parseFirstBlockHour(p.bookingFirstBlockTime);
    final duration = p.bookingDuration ?? 1; // in units of bookingDurationUnit
    final unit = (p.bookingDurationUnit ?? 'hour').toLowerCase();
    final int hourSpan;
    switch (unit) {
      case 'minute': hourSpan = ((duration * 9) / 60).ceil().clamp(1, 14); break;
      case 'hour':   hourSpan = (duration * 9).clamp(1, 14); break;
      case 'day':
      case 'night':  hourSpan = 9; break;
      default:       hourSpan = 9;
    }
    return (firstH + hourSpan).clamp(firstH + 1, 23);
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slots = await _api.getBookingSlots(widget.product.id);
      debugPrint('[BookingPicker] server returned RAW slots count=${slots.length} (before avail filter)');
      final available = slots.where((s) => s.isAvailable).toList();
      available.sort((a, b) => a.date.compareTo(b.date));
      debugPrint('[BookingPicker] after isAvailable filter: available=${available.length} unavailable=${slots.length - available.length}');

      // ── CRITICAL FIX 2026-09-04: unique-date sparsity guard ─────────
      // WooCommerce Bookings REST /wc-bookings/v1/products/slots sometimes
      // returns only today's slots even when a from/to range is supplied
      // (caused by: missing availability rules, non-elevated auth, or plugin
      // conflicts). The old `slots.isEmpty` guard failed in this scenario —
      // the user reported "only today selectable".
      //
      // NEW BEHAVIOUR: if the returned slot set spans fewer than 7 unique
      // calendar days (i.e. effectively today-only or weekend-only) we treat
      // it as an untrustworthy sparse response and use the meta-aware
      // fallback INSTEAD.
      final uniqueServerDates = <String>{};
      for (final s in available) {
        uniqueServerDates.add('${s.date.year}-${s.date.month}-${s.date.day}');
      }
      final serverUniqueDays = uniqueServerDates.length;
      final serverDateSpan = available.isEmpty
          ? 0
          : available.last.date.difference(available.first.date).inDays + 1;
      debugPrint('[BookingPicker] server unique-days=$serverUniqueDays span-days=$serverDateSpan');

      final useMetaFallback = slots.isEmpty || serverUniqueDays < 7;

      List<BookingSlot> effective = available;
      if (useMetaFallback) {
        if (slots.isEmpty) {
          debugPrint('[BookingPicker] server returned 0 slots — using meta-aware default fallback');
        } else {
          debugPrint('[BookingPicker] server returned only $serverUniqueDays unique dates '
              '(<$serverUniqueDays < 7 threshold) — treating as sparse today-only '
              'response and using meta-aware fallback instead');
        }
        final defaults = <BookingSlot>[];
        final now = DateTime.now();
        final startDay = DateTime(now.year, now.month, now.day).add(Duration(days: _wcBookingMinDays));
        final totalDays = _wcBookingMaxDays;
        debugPrint('[BookingPicker] meta window: min=$_wcBookingMinDays max=$totalDays days '
            'restricted_weekdays=${_wcBookingRestrictedWeekdays.join(',')} '
            'first_block=${_parseFirstBlockHour(widget.product.bookingFirstBlockTime)}:00 '
            'last_block_start=${_parseLastBlockHour(null)}:00');
        final firstH = _parseFirstBlockHour(widget.product.bookingFirstBlockTime);
        final lastH  = _parseLastBlockHour(null);
        for (int d = 0; d < totalDays; d++) {
          final day = startDay.add(Duration(days: d));
          // Restricted weekday check (convert Dart ISO weekday → Dokan 0=Sun..6=Sat)
          final dokanDow = (day.weekday % 7); // Dart Sun=7 → 0 Dokan, Dart Mon=1 → 1 Dokan, ... Dart Sat=6 → 6 Dokan ✓
          if (_wcBookingRestrictedWeekdays.contains(dokanDow)) {
            continue; // skip — vendor disabled this weekday
          }
          for (int h = firstH; h < lastH; h++) {
            defaults.add(BookingSlot(
              productId: widget.product.id,
              date: DateTime(day.year, day.month, day.day, h, 0, 0),
              duration: 60,
              available: 1,
              booked: 0,
            ));
          }
        }
        effective = defaults;
        final uniqueGenDates = <String>{};
        for (final s in effective) {
          uniqueGenDates.add('${s.date.year}-${s.date.month}-${s.date.day}');
        }
        debugPrint('[BookingPicker] meta-aware fallback generated ${effective.length} slots '
            'across ${uniqueGenDates.length} unique calendar days / $totalDays possible days '
            '(restricted weekdays skipped)');
      }

      if (!mounted) return;
      setState(() {
        _slots = effective;
        if (_selectedDate != null) {
          final stillHasDate = effective.any((s) =>
              s.date.year == _selectedDate!.year &&
              s.date.month == _selectedDate!.month &&
              s.date.day == _selectedDate!.day);
          if (!stillHasDate) _selectedDate = null;
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('[BookingPicker] _loadSlots error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Unique dates (midnight-normalised) across all available slots.
  List<DateTime> get _dates {
    final seen = <String>{};
    final dates = <DateTime>[];
    for (final s in _slots) {
      final key = _dateKey(s.date);
      if (seen.add(key)) {
        dates.add(DateTime(s.date.year, s.date.month, s.date.day));
      }
    }
    dates.sort();
    return dates;
  }

  List<BookingSlot> get _slotsForSelectedDate {
    if (_selectedDate == null) return const [];
    final key = _dateKey(_selectedDate!);
    return _slots.where((s) => _dateKey(s.date) == key).toList();
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}';
  }

  String _formatTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.hour)}:${two(d.minute)}';
  }

  void _confirm() {
    if (_selectedSlot == null) return;
    Navigator.of(context).pop(_selectedSlot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.creamColor,
      appBar: AppBar(
        backgroundColor: AppColors.creamColor,
        elevation: 0,
        title: Text(
          'Choose a slot',
          style: GoogleFonts.inter(
            color: AppColors.inkColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        foregroundColor: AppColors.inkColor,
      ),
      body: _buildBody(),
      bottomNavigationBar: _selectedSlot != null
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: const BoxDecoration(
                  color: AppColors.whiteColor,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, -4),
                    ),
                  ],
                ),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.goldColor,
                      foregroundColor: AppColors.whiteColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Confirm ${_formatDate(_selectedSlot!.date)} · ${_formatTime(_selectedSlot!.date)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.goldColor),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy,
                  size: 48, color: AppColors.goldColor.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text(
                'Could not load available slots',
                style: TextStyle(color: AppColors.inkColor, fontSize: 15),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSlots,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.goldColor,
                  foregroundColor: AppColors.whiteColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_slots.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy,
                  size: 48, color: AppColors.goldColor.withOpacity(0.5)),
              const SizedBox(height: 16),
              const Text(
                'No slots currently available',
                style: TextStyle(color: AppColors.inkSoftColor, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    final dates = _dates;
    if (_selectedDate == null && dates.isNotEmpty) {
      _selectedDate = dates.first;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            'Date',
            style: TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          height: 72,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            scrollDirection: Axis.horizontal,
            itemCount: dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final d = dates[index];
              final selected = _selectedDate != null &&
                  _dateKey(_selectedDate!) == _dateKey(d);
              return _dateChip(d, selected);
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Available times',
            style: TextStyle(
              color: AppColors.inkSoftColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 120,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.6,
            ),
            itemCount: _slotsForSelectedDate.length,
            itemBuilder: (context, index) {
              final slot = _slotsForSelectedDate[index];
              return _timeChip(slot);
            },
          ),
        ),
      ],
    );
  }

  Widget _dateChip(DateTime d, bool selected) {
    return GestureDetector(
      onTap: () => setState(() {
        _selectedDate = DateTime(d.year, d.month, d.day);
        _selectedSlot = null;
      }),
      child: Container(
        width: 92,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.goldColor : AppColors.whiteColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.goldColor : AppColors.sandColor,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _dateKey(d).split('-').last,
              style: TextStyle(
                color: selected ? AppColors.whiteColor : AppColors.inkColor,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _formatDate(d).split(', ').last,
              style: TextStyle(
                color: selected
                    ? AppColors.whiteColor.withOpacity(0.9)
                    : AppColors.inkSoftColor,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeChip(BookingSlot slot) {
    final selected = _selectedSlot?.date == slot.date;
    return GestureDetector(
      onTap: () => setState(() => _selectedSlot = slot),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.goldColor : AppColors.whiteColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.goldColor : AppColors.sandColor,
          ),
        ),
        child: Text(
          _formatTime(slot.date),
          style: TextStyle(
            color: selected ? AppColors.whiteColor : AppColors.inkColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
