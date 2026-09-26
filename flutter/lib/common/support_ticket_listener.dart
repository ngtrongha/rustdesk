import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;

class SupportTicket {
  final int id;
  final String deviceId;
  final String hostname;
  final String username;
  final String ipAddress;
  final String category;
  final String priority;
  final String description;
  final String contactName;
  final String contactPhone;
  final String status;
  final String createdAt;

  SupportTicket({
    required this.id,
    required this.deviceId,
    required this.hostname,
    required this.username,
    required this.ipAddress,
    required this.category,
    required this.priority,
    required this.description,
    required this.contactName,
    required this.contactPhone,
    required this.status,
    required this.createdAt,
  });

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: json['id'] is int
          ? json['id']
          : int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      deviceId: (json['device_id'] ?? '').toString(),
      hostname: (json['hostname'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      ipAddress: (json['ip_address'] ?? '').toString(),
      category: (json['category'] ?? 'Khác').toString(),
      priority: (json['priority'] ?? 'normal').toString(),
      description: (json['description'] ?? '').toString(),
      contactName: (json['contact_name'] ?? '').toString(),
      contactPhone: (json['contact_phone'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: (json['created_at'] ?? '').toString(),
    );
  }
}

class SupportTicketListener {
  static final SupportTicketListener instance =
      SupportTicketListener._internal();
  SupportTicketListener._internal();

  Timer? _pollingTimer;
  bool _isRunning = false;
  bool _isChecking = false;
  bool _initialized = false;
  int _lastSeenTicketId = 0;

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _initialized = false;
    _lastSeenTicketId = 0;
    debugPrint('[SupportTicketListener] Started for Admin user');

    // Run first check immediately
    _checkNewTickets();

    // Periodic check every 5 seconds
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkNewTickets();
    });
  }

  void stop() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _isRunning = false;
    _initialized = false;
    debugPrint('[SupportTicketListener] Stopped');
  }

  Future<void> _checkNewTickets() async {
    if (!_isRunning || _isChecking) return;
    _isChecking = true;

    try {
      final apiServer = await bind.mainGetApiServer();
      if (apiServer.isEmpty) {
        return;
      }

      final queryParam =
          _lastSeenTicketId > 0 ? '?since_id=$_lastSeenTicketId' : '';
      final url = Uri.parse('$apiServer/api/support/ticket/feed$queryParam');

      final token = bind.mainGetLocalOption(key: 'access_token');
      final headers = <String, String>{
        'Accept': 'application/json',
      };
      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 4));
      if (response.statusCode != 200) {
        return;
      }

      final body = json.decode(utf8.decode(response.bodyBytes));
      if (body['code'] != 200 || body['data'] == null) {
        return;
      }

      final List list = body['data'] as List;
      final tickets = list
          .map((e) => SupportTicket.fromJson(e as Map<String, dynamic>))
          .toList();

      if (!_initialized) {
        // Initial setup: note the highest current ID so we don't spam old historical tickets
        _initialized = true;
        if (tickets.isNotEmpty) {
          int maxId = 0;
          for (final t in tickets) {
            if (t.id > maxId) maxId = t.id;
          }
          _lastSeenTicketId = maxId;
        }
        return;
      }

      // We are initialized; any ticket with id > _lastSeenTicketId is new!
      final newTickets =
          tickets.where((t) => t.id > _lastSeenTicketId).toList();
      if (newTickets.isNotEmpty) {
        // Sort ascending by ID to notify in chronological order
        newTickets.sort((a, b) => a.id.compareTo(b.id));

        for (final ticket in newTickets) {
          if (ticket.id > _lastSeenTicketId) {
            _lastSeenTicketId = ticket.id;
          }
          _onNewTicketReceived(ticket);
        }
      }
    } catch (e) {
      debugPrint('[SupportTicketListener] Error fetching tickets: $e');
    } finally {
      _isChecking = false;
    }
  }

  void _onNewTicketReceived(SupportTicket ticket) {
    debugPrint(
        '[SupportTicketListener] New Ticket #${ticket.id} from ${ticket.hostname} (${ticket.deviceId})');

    // 1. Play audible chime
    _playChime();

    // 2. Native Windows Toast notification (pops up from notification center / taskbar)
    if (Platform.isWindows) {
      _showWindowsToast(ticket);
    }

    // 3. Bring window to front / restore from minimized or tray
    if (isDesktop) {
      try {
        windowOnTop(null);
      } catch (e) {
        debugPrint(
            '[SupportTicketListener] Failed to bring window to front: $e');
      }
    }

    // 4. Floating In-App Banner with 1-click connect button
    _showInAppBanner(ticket);
  }

  void _playChime() {
    try {
      SystemSound.play(SystemSoundType.alert);
      if (Platform.isWindows) {
        final user32 = DynamicLibrary.open('user32.dll');
        final messageBeep =
            user32.lookupFunction<Int32 Function(Uint32), int Function(int)>(
                'MessageBeep');
        messageBeep(0x00000030); // MB_ICONEXCLAMATION
      }
    } catch (e) {
      debugPrint('[SupportTicketListener] Error playing chime: $e');
    }
  }

  void _showWindowsToast(SupportTicket ticket) {
    try {
      final displayName =
          ticket.hostname.isNotEmpty ? ticket.hostname : ticket.deviceId;
      final title = '[BVĐKKH] Yêu cầu hỗ trợ IT: $displayName';
      final body =
          '${ticket.category}: ${ticket.description}\nID: ${ticket.deviceId}';

      final psScript = '''
\$ErrorActionPreference = 'Stop'
\$title = @'
$title
'@
\$body = @'
$body
'@
try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
    [Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] > \$null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > \$null
    \$appId = '{1AC14E77-02E7-4E5D-B744-22D60870027C}\\WindowsPowerShell\\v1.0\\powershell.exe'
    \$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
    \$toastXml = @"
<toast duration="long">
  <visual>
    <binding template="ToastGeneric">
      <text><![CDATA[\$title]]></text>
      <text><![CDATA[\$body]]></text>
    </binding>
  </visual>
  <audio src="ms-winsoundevent:Notification.Reminder"/>
</toast>
"@
    \$xml.LoadXml(\$toastXml)
    \$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$appId).Show(\$toast)
} catch {
    try {
        Add-Type -AssemblyName System.Windows.Forms
        \$notify = New-Object System.Windows.Forms.NotifyIcon
        \$notify.Icon = [System.Drawing.SystemIcons]::Information
        \$notify.BalloonTipTitle = \$title
        \$notify.BalloonTipText = \$body
        \$notify.BalloonTipIcon = [System.Windows.Forms.ToolTipIcon]::Info
        \$notify.Visible = \$true
        \$notify.ShowBalloonTip(10000)
        Start-Sleep -Seconds 5
        \$notify.Dispose()
    } catch {}
}
''';

      // PowerShell expects UTF-16LE for -EncodedCommand
      final utf16leBytes = <int>[];
      for (final char in psScript.codeUnits) {
        utf16leBytes.add(char & 0xFF);
        utf16leBytes.add((char >> 8) & 0xFF);
      }
      final encoded = base64.encode(utf16leBytes);

      Process.start('powershell.exe', [
        '-NoProfile',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        encoded,
      ]);
    } catch (e) {
      debugPrint('[SupportTicketListener] Failed to show Windows toast: $e');
    }
  }

  void _showInAppBanner(SupportTicket ticket) {
    final displayName =
        ticket.hostname.isNotEmpty ? ticket.hostname : ticket.deviceId;
    final contact = ticket.contactName.isNotEmpty
        ? '${ticket.contactName} (${ticket.contactPhone})'
        : (ticket.username.isNotEmpty ? ticket.username : '');

    BotToast.showCustomNotification(
      duration: const Duration(seconds: 30),
      toastBuilder: (cancelFunc) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 10,
          color: const Color(0xFF1E293B), // Dark slate blue
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(
                color: Color(0xFFE11D48), width: 2), // Rose/Red warning border
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 550),
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE11D48),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.support_agent,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'YÊU CẦU HỖ TRỢ IT MỚI',
                            style: TextStyle(
                              color: Color(0xFFFDA4AF),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Máy: $displayName',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          color: Colors.white70, size: 20),
                      onPressed: cancelFunc,
                      tooltip: 'Đóng',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (contact.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.person,
                                color: Colors.white60, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              contact,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ticket.category,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        ticket.description,
                        style:
                            const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'ID: ${ticket.deviceId}',
                      style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                    const Spacer(),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white30),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: cancelFunc,
                      child: const Text('Bỏ qua'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2563EB),
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        elevation: 4,
                      ),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text(
                        'KẾT NỐI NGAY',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        cancelFunc();
                        final ctx = Get.context;
                        if (ctx != null) {
                          connect(ctx, ticket.deviceId);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
