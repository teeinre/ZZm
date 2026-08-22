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

  Future<void> _loadSlots() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slots = await _api.getBookingSlots(widget.product.id);
      final available = slots.where((s) => s.isAvailable).toList();
      available.sort((a, b) => a.date.compareTo(b.date));
      if (!mounted) return;
      setState(() {
        _slots = available;
        _loading = false;
      });
    } catch (e) {
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
