import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';

class PlutoColumnFilter extends PlutoStatefulWidget {
  final PlutoGridStateManager stateManager;

  final PlutoColumn column;

  final bool? greaterLessThanWidget;

  /// [PlutoGridConfiguration] to call [PlutoGridPopup]
  final PlutoGridConfiguration? configuration;

  /// A callback function called when adding a new filter.
  final SetFilterPopupHandler? handleAddNewFilter;

  /// A callback function called when filter information changes.
  final SetFilterPopupHandler? handleApplyFilter;

  /// List of columns to be filtered.
  final List<PlutoColumn>? columns;

  /// List with filtering condition information
  final List<PlutoRow>? filterRows;

  PlutoColumnFilter({
    required this.stateManager,
    required this.column,
    this.greaterLessThanWidget = false,
    this.configuration,
    this.handleAddNewFilter,
    this.handleApplyFilter,
    this.columns,
    this.filterRows,
    Key? key,
  }) : super(key: ValueKey('column_filter_${column.key}'));

  @override
  PlutoColumnFilterState createState() => PlutoColumnFilterState();
}

class PlutoColumnFilterState extends PlutoStateWithChange<PlutoColumnFilter> {
  List<PlutoRow> _filterRows = [];

  String _text = '';

  bool _enabled = false;

  late final StreamSubscription _event;

  late final FocusNode _focusNode;

  late final TextEditingController _controller;

  String get _filterValue {
    return _filterRows.isEmpty
        ? ''
        : _filterRows.first.cells[FilterHelper.filterFieldValue]!.value
            .toString();
  }

  bool get _hasCompositeFilter {
    return _filterRows.length > 1 ||
        stateManager
            .filterRowsByField(FilterHelper.filterFieldAllColumns)
            .isNotEmpty;
  }

  InputBorder get _border => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration!.style.borderColor, width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  InputBorder get _enabledBorder => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration!.style.activatedBorderColor,
            width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  InputBorder get _disabledBorder => OutlineInputBorder(
        borderSide: BorderSide(
            color: stateManager.configuration!.style.inactivatedBorderColor,
            width: 0.0),
        borderRadius: BorderRadius.zero,
      );

  Color get _textFieldColor => _enabled
      ? stateManager.configuration!.style.cellColorInEditState
      : stateManager.configuration!.style.cellColorInReadOnlyState;

  EdgeInsets get _padding =>
      widget.column.filterPadding ??
      stateManager.configuration!.style.defaultColumnFilterPadding;

  @override
  PlutoGridStateManager get stateManager => widget.stateManager;

  @override
  initState() {
    super.initState();

    _focusNode = FocusNode(onKey: _handleOnKey);

    widget.column.setFilterFocusNode(_focusNode);

    _controller = TextEditingController(text: _filterValue);

    _event = stateManager.eventManager!.listener(_handleFocusFromRows);

    updateState();
  }

  @override
  dispose() {
    _event.cancel();

    _controller.dispose();

    _focusNode.dispose();

    super.dispose();
  }

  @override
  void updateState() {
    _filterRows = update<List<PlutoRow>>(
      _filterRows,
      stateManager.filterRowsByField(widget.column.field),
      compare: listEquals,
    );

    if (_focusNode.hasPrimaryFocus != true) {
      _text = update<String>(_text, _filterValue);

      if (changed) {
        _controller.text = _text;
      }
    }

    _enabled = update<bool>(
      _enabled,
      widget.column.enableFilterMenuItem && !_hasCompositeFilter,
    );
  }

  void _moveDown({required bool focusToPreviousCell}) {
    _focusNode.unfocus();

    if (!focusToPreviousCell || stateManager.currentCell == null) {
      stateManager.setCurrentCell(
        stateManager.refRows.first.cells[widget.column.field],
        0,
        notify: false,
      );

      stateManager.scrollByDirection(PlutoMoveDirection.down, 0);
    }

    stateManager.setKeepFocus(true, notify: false);

    stateManager.notifyListeners();
  }

  KeyEventResult _handleOnKey(FocusNode node, RawKeyEvent event) {
    var keyManager = PlutoKeyManagerEvent(
      focusNode: node,
      event: event,
    );

    if (keyManager.isKeyUpEvent) {
      return KeyEventResult.handled;
    }

    final handleMoveDown =
        (keyManager.isDown || keyManager.isEnter || keyManager.isEsc) &&
            stateManager.refRows.isNotEmpty;

    final handleMoveHorizontal = keyManager.isTab ||
        (_controller.text.isEmpty && keyManager.isHorizontal);

    final skip = !(handleMoveDown || handleMoveHorizontal || keyManager.isF3);

    if (skip) {
      if (keyManager.isUp) {
        return KeyEventResult.handled;
      }

      return stateManager.keyManager!.eventResult.skip(
        KeyEventResult.ignored,
      );
    }

    if (handleMoveDown) {
      _moveDown(focusToPreviousCell: keyManager.isEsc);
    } else if (handleMoveHorizontal) {
      stateManager.nextFocusOfColumnFilter(
        widget.column,
        reversed: keyManager.isLeft || keyManager.isShiftPressed,
      );
    } else if (keyManager.isF3) {
      stateManager.showFilterPopup(
        _focusNode.context!,
        calledColumn: widget.column,
      );
    }

    return KeyEventResult.handled;
  }

  void _handleFocusFromRows(PlutoGridEvent plutoEvent) {
    if (!_enabled) {
      return;
    }

    if (plutoEvent is PlutoGridCannotMoveCurrentCellEvent &&
        plutoEvent.direction.isUp) {
      var isCurrentColumn = widget
              .stateManager
              .refColumns[stateManager.columnIndexesByShowFrozen[
                  plutoEvent.cellPosition.columnIdx!]]
              .key ==
          widget.column.key;

      if (isCurrentColumn) {
        stateManager.clearCurrentCell(notify: false);
        stateManager.setKeepFocus(false);
        _focusNode.requestFocus();
      }
    }
  }

  void _handleOnTap() {
    stateManager.setKeepFocus(false);
  }

  void _handleOnChanged(String changed) {
    stateManager.eventManager!.addEvent(
      PlutoGridChangeColumnFilterEvent(
        column: widget.column,
        filterType: _onSearch2(),
        filterValue: changed,
        debounceMilliseconds:
            stateManager.configuration!.columnFilter.debounceMilliseconds,
      ),
    );
  }

  void _handleOnEditingComplete() {
    // empty for ignore event of OnEditingComplete.
  }

  //  1 = greater than
  //  2 = less than
  //  3 = equal to
  int filterState = 3;

  void _onSearch() {
    if (widget.column.field == 'purPrice' ||
        widget.column.field == 'sellPrice' ||
        widget.column.field == 'quantity') {
      if (filterState == 1) {
        return widget.stateManager.setConfiguration(PlutoGridConfiguration(
          columnFilter: PlutoGridColumnFilterConfig(
            filters: [
              ...FilterHelper.defaultFilters,
            ],
            resolveDefaultColumnFilter: (column, resolver) {
              return resolver<PlutoFilterTypeGreaterThan>() as PlutoFilterType;
            },
          ),
        ));
      } else if (filterState == 2) {
        // return widget.stateManager
        //     .setConfiguration(const PlutoGridConfiguration(
        //   columnFilter: PlutoGridColumnFilterConfig(
        //     filters: [
        //       PlutoFilterTypeLessThan(),
        //     ],
        //   ),
        // ));

        return widget.stateManager.setConfiguration(PlutoGridConfiguration(
          columnFilter: PlutoGridColumnFilterConfig(
            filters: [
              ...FilterHelper.defaultFilters,
            ],
            resolveDefaultColumnFilter: (column, resolver) {
              return resolver<PlutoFilterTypeLessThan>() as PlutoFilterType;
            },
          ),
        ));
      } else if (filterState == 3) {
        // return widget.stateManager
        //     .setConfiguration(const PlutoGridConfiguration(
        //   columnFilter: PlutoGridColumnFilterConfig(
        //     filters: [
        //       PlutoFilterTypeContains(),
        //     ],
        //   ),
        // ));

        return widget.stateManager.setConfiguration(PlutoGridConfiguration(
          columnFilter: PlutoGridColumnFilterConfig(
            filters: [
              ...FilterHelper.defaultFilters,
            ],
            resolveDefaultColumnFilter: (column, resolver) {
              return resolver<PlutoFilterTypeContains>() as PlutoFilterType;
            },
          ),
        ));
      }
    }
  }

  _onSearch2() {
    if (widget.column.field == 'purPrice' ||
        widget.column.field == 'sellPrice' ||
        widget.column.field == 'quantity') {
      switch (filterState) {
        case 1:
          return const PlutoFilterTypeGreaterThan();
        case 2:
          return const PlutoFilterTypeLessThan();
        default:
          return const PlutoFilterTypeContains();
      }
    } else {
      setState(() {
        filterState = 3;
      });
      return const PlutoFilterTypeContains();
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = stateManager.style;

    return Container(
      height: stateManager.columnFilterHeight,
      padding: _padding,
      decoration: BoxDecoration(
        border: BorderDirectional(
          top: BorderSide(color: style.borderColor),
          end: style.enableColumnBorderVertical
              ? BorderSide(color: style.borderColor)
              : BorderSide.none,
        ),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Stack(
          children: [
            TextField(
              focusNode: _focusNode,
              controller: _controller,
              enabled: _enabled,
              style: style.cellTextStyle,
              onTap: _handleOnTap,
              onChanged: _handleOnChanged,
              onEditingComplete: _handleOnEditingComplete,
              decoration: InputDecoration(
                hintText: _hintTextHandler(),
                filled: true,
                fillColor: _textFieldColor,
                border: _border,
                enabledBorder: _border,
                disabledBorder: _disabledBorder,
                focusedBorder: _enabledBorder,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
                suffix: widget.column.defaultFilter.title == "Greater than" ||
                        widget.column.defaultFilter.title == "Less than"
                    ? const SizedBox(
                        width: 40,
                      )
                    : null,
              ),
            ),

            // if (widget.column.defaultFilter.title == "Greater than" ||
            //     widget.column.defaultFilter.title == "Less than")
            if (widget.greaterLessThanWidget!)
              if (widget.column.field == 'purPrice' ||
                  widget.column.field == 'sellPrice' ||
                  widget.column.field == 'quantity')
                Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        border: Border.all(
                            color: const Color(0xFF6B7280), width: .5),
                      ),
                      child: InkWell(
                          onTap: _onIconTap,
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 3.0, vertical: 2.0),
                              child: Text(
                                filterState == 1
                                    ? ">"
                                    : filterState == 2
                                        ? "<"
                                        : "=",
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ))),
                    )),
          ],
        ),
      ),
    );
  }

  _onIconTap() {
    if (widget.column.field == 'purPrice' ||
        widget.column.field == 'sellPrice' ||
        widget.column.field == 'quantity') {
      setState(() {
        if (filterState == 3) {
          filterState = 1;
        } else {
          filterState = filterState + 1;
        }
      });
    }
  }

  _hintTextHandler() {
    if (_enabled) {
      switch (filterState) {
        case 1:
          return "Greater than";
        case 2:
          return "Less than";
        case 3:
          return "Contains";
        default:
          return widget.column.defaultFilter.title;
      }
    } else {
      return "";
    }
  }
}
