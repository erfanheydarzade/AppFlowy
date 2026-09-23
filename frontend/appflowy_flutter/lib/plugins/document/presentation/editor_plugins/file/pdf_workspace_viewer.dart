import 'dart:async';
import 'dart:convert';

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

enum PdfSourceType { local, network, cloud }

Future<void> showPdfViewer(
  BuildContext context, {
  required String source,
  required PdfSourceType sourceType,
  required String title,
  UserProfilePB? userProfile,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      child: PdfWorkspaceViewer(
        source: source,
        sourceType: sourceType,
        title: title,
        userProfile: userProfile,
      ),
    ),
  );
}

class PdfWorkspaceViewer extends StatefulWidget {
  const PdfWorkspaceViewer({
    super.key,
    required this.source,
    required this.sourceType,
    required this.title,
    this.userProfile,
  });

  final String source;
  final PdfSourceType sourceType;
  final String title;
  final UserProfilePB? userProfile;

  @override
  State<PdfWorkspaceViewer> createState() => _PdfWorkspaceViewerState();
}

class _PdfWorkspaceViewerState extends State<PdfWorkspaceViewer> {
  late final PdfViewerController _controller = PdfViewerController();
  late final PdfTextSearcher _searcher = PdfTextSearcher(_controller)
    ..addListener(_onSearchChanged);
  final TextEditingController _queryController = TextEditingController();

  Timer? _searchDebounce;
  int _pageNumber = 1;
  int _pageCount = 0;
  bool _searchVisible = false;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searcher
      ..removeListener(_onSearchChanged)
      ..dispose();
    _queryController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _startSearch(String query) {
    _searchDebounce?.cancel();
    final normalized = query.trim();
    if (normalized.isEmpty) {
      _searcher.resetTextSearch();
      return;
    }
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _searcher.startTextSearch(normalized),
    );
  }

  void _closeSearch() {
    _searchDebounce?.cancel();
    _queryController.clear();
    _searcher.resetTextSearch();
    setState(() => _searchVisible = false);
  }

  void _goToPage(int pageNumber, {PdfPageAnchor? anchor}) {
    if (!_controller.isReady || _pageCount == 0) return;
    final target = pageNumber.clamp(1, _pageCount).toInt();
    _controller.goToPage(pageNumber: target, anchor: anchor);
    setState(() => _pageNumber = target);
  }

  void _fitWidth() {
    if (!_controller.isReady || _pageCount == 0) return;
    final page = _controller.layout.pageLayouts[_pageNumber - 1];
    final viewSize = _controller.viewSize;
    final margin = _controller.params.margin;
    final zoom = ((viewSize.width - margin * 2) / page.width)
        .clamp(_controller.minScale, _controller.params.maxScale)
        .toDouble();
    final matrix = _controller.calcMatrixFor(
      page.topCenter,
      zoom: zoom,
      viewSize: viewSize,
    );
    _controller.goTo(matrix);
  }

  Map<String, String>? get _headers {
    final token = widget.userProfile?.token;
    if (widget.sourceType != PdfSourceType.cloud || token == null) {
      return null;
    }
    try {
      final accessToken = jsonDecode(token)['access_token'] as String?;
      if (accessToken == null) return null;
      return {'Authorization': 'Bearer $accessToken'};
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewer = _buildViewer();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => setState(() => _searchVisible = !_searchVisible),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: 'Open externally',
            onPressed: () => afLaunchUrlString(widget.source),
            icon: const Icon(Icons.open_in_new),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
        bottom: _searchVisible
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _queryController,
                          autofocus: true,
                          onChanged: _startSearch,
                          onSubmitted: _startSearch,
                          decoration: const InputDecoration(
                            hintText: 'Find in PDF',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${_searcher.matches.length}'),
                      IconButton(
                        tooltip: 'Previous match',
                        onPressed: _searcher.matches.isEmpty
                            ? null
                            : _searcher.goToPrevMatch,
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: 'Next match',
                        onPressed: _searcher.matches.isEmpty
                            ? null
                            : _searcher.goToNextMatch,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                      IconButton(
                        tooltip: 'Close search',
                        onPressed: _closeSearch,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          Expanded(child: viewer),
          _buildToolbar(context),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    final params = PdfViewerParams(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
      enableTextSelection: true,
      useAlternativeFitScaleAsMinScale: false,
      maxImageBytesCachedOnMemory: 64 * 1024 * 1024,
      verticalCacheExtent: 1.5,
      horizontalCacheExtent: 1.5,
      pagePaintCallbacks: [_searcher.pageTextMatchPaintCallback],
      onPageChanged: (pageNumber) {
        if (pageNumber != null && mounted) {
          setState(() => _pageNumber = pageNumber);
        }
      },
      onViewerReady: (document, controller) {
        if (!mounted) return;
        setState(() {
          _pageCount = document.pages.length;
          _pageNumber = controller.pageNumber ?? 1;
        });
      },
    );

    if (widget.sourceType == PdfSourceType.local) {
      return PdfViewer.file(
        widget.source,
        controller: _controller,
        params: params,
      );
    }
    return PdfViewer.uri(
      Uri.parse(widget.source),
      controller: _controller,
      params: params,
      preferRangeAccess: true,
      headers: _headers,
    );
  }

  Widget _buildToolbar(BuildContext context) {
    return Material(
      elevation: 2,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: _pageNumber > 1
                    ? () => _goToPage(_pageNumber - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              SizedBox(
                width: 92,
                child: Text(
                  '$_pageNumber / ${_pageCount == 0 ? '…' : _pageCount}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: _pageCount > 0 && _pageNumber < _pageCount
                    ? () => _goToPage(_pageNumber + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Zoom out',
                onPressed: _controller.isReady ? _controller.zoomDown : null,
                icon: const Icon(Icons.zoom_out),
              ),
              IconButton(
                tooltip: 'Zoom in',
                onPressed: _controller.isReady ? _controller.zoomUp : null,
                icon: const Icon(Icons.zoom_in),
              ),
              PopupMenuButton<String>(
                tooltip: 'Page fit',
                onSelected: (value) {
                  if (value == 'width') {
                    _fitWidth();
                  } else {
                    _goToPage(_pageNumber, anchor: PdfPageAnchor.all);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'width', child: Text('Fit width')),
                  PopupMenuItem(value: 'page', child: Text('Fit page')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
