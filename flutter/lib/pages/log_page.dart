import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/logger.dart';

class LogPage extends StatefulWidget {
  const LogPage({super.key});

  @override
  State<LogPage> createState() => _LogPageState();
}

class _LogPageState extends State<LogPage> {
  final ScrollController _scrollController = ScrollController();
  List<String> _logs = [];
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
    _scrollToBottom();
  }

  void _loadLogs() {
    setState(() {
      _logs = AppLogger.getLogs();
    });
  }

  void _scrollToBottom() {
    if (_autoScroll && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _refreshLogs() {
    _loadLogs();
    _scrollToBottom();
  }

  void _clearLogs() {
    AppLogger.clearLogs();
    _loadLogs();
  }

  void _copyLogs() {
    final logsText = _logs.join('\n');
    Clipboard.setData(ClipboardData(text: logsText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Logs copied to clipboard')),
    );
  }

  Color _getLogColor(String logEntry) {
    if (logEntry.contains('[ERROR]')) return Colors.red;
    if (logEntry.contains('[WARNING]')) return Colors.orange;
    if (logEntry.contains('[DEBUG]')) return Colors.grey;
    if (logEntry.contains('[INFO]')) return Colors.blue;
    return Colors.black;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Logs'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.auto_fix_high : Icons.auto_fix_off),
            onPressed: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
              if (_autoScroll) _scrollToBottom();
            },
            tooltip: 'Auto-scroll',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLogs,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyLogs,
            tooltip: 'Copy all logs',
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: _clearLogs,
            tooltip: 'Clear logs',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[200],
            child: Row(
              children: [
                const Text('Logs: ',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_logs.length} entries'),
                const Spacer(),
                if (_autoScroll)
                  const Chip(
                    label: Text('Auto-scroll', style: TextStyle(fontSize: 12)),
                    backgroundColor: Colors.green,
                    labelStyle: TextStyle(color: Colors.white),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No logs yet',
                            style: TextStyle(color: Colors.grey)),
                        Text('Use the app to generate logs',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final log = _logs[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          border: Border(
                              left: BorderSide(
                            color: _getLogColor(log),
                            width: 3,
                          )),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: _getLogColor(log),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _refreshLogs,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh'),
      ),
    );
  }
}
