import 'package:flutter/material.dart';

import '../app/app_colors.dart';
import '../core/utils.dart';
import 'record_card.dart';
import 'empty_card.dart';

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.items,
    required this.builder,
    this.searchHint,
    this.searchNotifier,
    this.accentColor,
  });

  final List<Map<String, dynamic>> items;
  final RecordView Function(Map<String, dynamic>) builder;
  final String? searchHint;
  final ValueNotifier<bool>? searchNotifier;
  final Color? accentColor;

  @override
  State<RecordsPage> createState() => RecordsPageState();
}

class RecordsPageState extends State<RecordsPage> {
  String _query = '';
  bool _showSearch = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.searchNotifier?.addListener(_onSearchToggle);
  }

  @override
  void dispose() {
    widget.searchNotifier?.removeListener(_onSearchToggle);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onSearchToggle() {
    if (widget.searchNotifier?.value ?? false) {
      setState(() {
        _showSearch = true;
      });
      _searchFocus.requestFocus();
    } else {
      setState(() {
        _showSearch = false;
        _searchController.clear();
        _query = '';
        _searchFocus.unfocus();
      });
    }
  }

  List<RecordView> get filteredViews {
    return widget.items.map(widget.builder).where((view) {
      if (_query.trim().isEmpty) return true;
      return view.searchText.toLowerCase().contains(_query.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final views = filteredViews;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search bar (toggleable)
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: _showSearch ? 48 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _showSearch ? 1.0 : 0.0,
            child: _showSearch ? _buildSearchField() : const SizedBox.shrink(),
          ),
        ),
        if (_showSearch) const SizedBox(height: 8),
        // Count label
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            '${views.length} registros',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Records list
        if (views.isEmpty)
          const EmptyCard()
        else
          ...views.map((view) => RecordCard(
                view: view,
                accentColor: widget.accentColor,
              )),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocus,
      autofocus: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.search,
          color: AppColors.textSecondary,
          size: 20,
        ),
        suffixIcon: _query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                color: AppColors.textSecondary,
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              )
            : null,
        hintText: widget.searchHint ?? 'Buscar...',
        hintStyle: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 14,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
      onChanged: (value) => setState(() => _query = value),
    );
  }
}
