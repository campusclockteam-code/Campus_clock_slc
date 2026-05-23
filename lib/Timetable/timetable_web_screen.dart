import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class TimetableWebScreen extends StatefulWidget {
  final String url;
  final String? className;
  final String? semester;
  final String? section;
  final String? teacher;
  final String? room;
  final String? day;
  final String? period;
  final String? presetName;

  const TimetableWebScreen({
    super.key,
    required this.url,
    this.className,
    this.semester,
    this.section,
    this.teacher,
    this.room,
    this.day,
    this.period,
    this.presetName,
  });

  @override
  State<TimetableWebScreen> createState() => _TimetableWebScreenState();
}

class _TimetableWebScreenState extends State<TimetableWebScreen> {
  late WebViewController _controller;
  int _loadingPercentage = 0;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _loadTimeoutTimer;
  bool _formSubmitted = false;
  bool _autoFillAttempted = false;
  bool _manualFillMode = false;
  String _currentUrl = '';
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _initializeWebView();
  }

  Future<void> _initializeWebView() async {
    try {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (url) {
              _currentUrl = url;
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _loadingPercentage = 0;
                  _hasError = false;
                });
              }

              _loadTimeoutTimer?.cancel();
              _loadTimeoutTimer = Timer(const Duration(seconds: 30), () {
                if (mounted && _isLoading) {
                  setState(() {
                    _hasError = true;
                    _errorMessage = 'Loading timeout. Please check your internet connection.';
                    _isLoading = false;
                  });
                }
              });
            },
            onProgress: (progress) {
              if (mounted) setState(() => _loadingPercentage = progress);
            },
            onPageFinished: (url) async {
              _loadTimeoutTimer?.cancel();
              _currentUrl = url;
              if (mounted) setState(() => _loadingPercentage = 100);

              // Wait a moment for dynamic content
              await Future.delayed(const Duration(seconds: 1));

              // If we haven't auto-filled yet and we have data, try to fill
              if (!_autoFillAttempted && _shouldAutoFill() && !_manualFillMode) {
                await _performSLCFormFill();
              } else {
                if (mounted) setState(() => _isLoading = false);
              }
            },
            onWebResourceError: (error) {
              _loadTimeoutTimer?.cancel();
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                  _errorMessage = 'Error loading page: ${error.description}';
                });
              }
            },
            onNavigationRequest: (navigation) {
              _currentUrl = navigation.url;
              return NavigationDecision.navigate;
            },
          ),
        )
        ..enableZoom(false)
        ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        );

      _isInitialized = true;
      await _controller.loadRequest(Uri.parse(widget.url));
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Failed to initialize WebView: $e';
          _isLoading = false;
        });
      }
    }
  }

  bool _shouldAutoFill() {
    return widget.className != null && widget.semester != null;
  }

  Future<void> _performSLCFormFill() async {
    _autoFillAttempted = true;
    final exactClassName = widget.className;

    String escapeJs(String? value) => value == null ? 'null' : jsonEncode(value);

    final js = '''
      (function() {
        function fillSelect(selectId, value) {
          try {
            const select = document.getElementById(selectId);
            if (!select || !value) return false;
            const searchText = value.toString().trim();
            for (let i = 0; i < select.options.length; i++) {
              if (select.options[i].text.trim() === searchText) {
                select.selectedIndex = i;
                ['change', 'input', 'blur'].forEach(eventType => {
                  select.dispatchEvent(new Event(eventType, { bubbles: true }));
                });
                return true;
              }
            }
            // Case-insensitive fallback
            for (let i = 0; i < select.options.length; i++) {
              if (select.options[i].text.trim().toLowerCase() === searchText.toLowerCase()) {
                select.selectedIndex = i;
                ['change', 'input', 'blur'].forEach(eventType => {
                  select.dispatchEvent(new Event(eventType, { bubbles: true }));
                });
                return true;
              }
            }
            return false;
          } catch(e) {
            return false;
          }
        }
        
        let filledCount = 0;
        ${widget.className != null ? "if (fillSelect('classid', ${escapeJs(widget.className)})) filledCount++;" : ""}
        ${widget.semester != null ? "if (fillSelect('semester', ${escapeJs(widget.semester)})) filledCount++;" : ""}
        ${widget.section != null ? "if (fillSelect('section', ${escapeJs(widget.section)})) filledCount++;" : ""}
        ${widget.teacher != null ? "if (fillSelect('teacher', ${escapeJs(widget.teacher)})) filledCount++;" : ""}
        ${widget.room != null ? "if (fillSelect('roomno', ${escapeJs(widget.room)})) filledCount++;" : ""}
        ${widget.day != null ? "if (fillSelect('day', ${escapeJs(widget.day)})) filledCount++;" : ""}
        ${widget.period != null ? "if (fillSelect('period', ${escapeJs(widget.period)})) filledCount++;" : ""}
        
        if (filledCount >= 2) {
          setTimeout(function() {
            const submitBtn = document.querySelector('input[type="submit"]');
            if (submitBtn) {
              submitBtn.click();
            } else if (document.forms.length > 0) {
              document.forms[0].submit();
            }
          }, 1500);
        }
        return filledCount;
      })();
    ''';

    try {
      final result = await _controller.runJavaScriptReturningResult(js);
      if (result is num && result < 2) {
        _manualFillMode = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Auto-fill could not find your course. Please select manually.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        _formSubmitted = true;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Form auto-filled. Submitting...'),
              backgroundColor: Colors.blue,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-fill error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshPage() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _hasError = false;
        _formSubmitted = false;
        _autoFillAttempted = false;
        _manualFillMode = false;
      });
    }
    await _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.presetName ?? 'SLC Timetable',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (widget.className != null || widget.semester != null)
              Text(
                '${widget.className ?? ''} ${widget.semester != null ? 'Sem ${widget.semester}' : ''}'.trim(),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshPage,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isInitialized ? _buildBody() : _buildLoading(),
    );
  }

  Widget _buildBody() {
    return Stack(
      children: [
        Column(
          children: [
            if (_isLoading && _loadingPercentage < 100)
              LinearProgressIndicator(
                value: _loadingPercentage / 100.0,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                minHeight: 3,
              ),
            if (_hasError)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        TextButton(onPressed: _refreshPage, child: const Text('Retry')),
                      ],
                    ),
                  ],
                ),
              ),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
        if (_isLoading && _loadingPercentage < 100)
          Container(
            color: Colors.white.withOpacity(0.8),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(value: _loadingPercentage / 100.0, strokeWidth: 4),
                  const SizedBox(height: 16),
                  Text(
                    _formSubmitted ? 'Submitting form...' : 'Loading timetable...',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_loadingPercentage%',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          const Text('Initializing WebView...'),
          if (_hasError)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_errorMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _loadTimeoutTimer?.cancel();
    super.dispose();
  }
}