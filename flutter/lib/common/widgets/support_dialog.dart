// Copyright (c) 2026 Nguyễn Trọng Hà. All rights reserved.
// Project: BVĐKKH - Remoter
// Author: Nguyễn Trọng Hà

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bot_toast/bot_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../common.dart';
import '../../models/platform_model.dart';
import '../support_ticket_listener.dart';

Widget _buildDialogHeader(VoidCallback onClose) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(
      color: Color(0xFFE11D48), // Rose Red
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(8),
        topRight: Radius.circular(8),
      ),
    ),
    child: Row(
      children: [
        const Icon(Icons.support_agent_rounded, color: Colors.white, size: 24),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'BÁO SỰ CỐ KỸ THUẬT IT',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'BVĐK Tỉnh Khánh Hòa - Hỗ trợ kỹ thuật từ xa',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 20),
          onPressed: onClose,
          tooltip: 'Đóng',
        ),
      ],
    ),
  );
}

Future<bool?> showSupportRequestDialog(BuildContext context) async {
  return await gFFI.dialogManager.show<bool>((setState, close, context) {
    return CustomAlertDialog(
      contentBoxConstraints: const BoxConstraints(maxWidth: 580),
      titlePadding: EdgeInsets.zero,
      title: _buildDialogHeader(close),
      content: SupportDialogBody(onClose: close),
    );
  });
}

enum SupportCategory {
  hisLis('his_lis', 'Phần mềm Bệnh viện (HIS / LIS / PACS)'),
  printer('printer', 'Lỗi Máy In / Không in được phiếu'),
  network('network', 'Mất mạng / Không kết nối được Internet'),
  slowPc('slow_pc', 'Máy tính bị chậm / Treo máy'),
  softwareInstall('software_install', 'Cần cài đặt phần mềm mới'),
  hardwareOther('hardware_other', 'Sự cố phần cứng / Khác');

  final String key;
  final String label;
  const SupportCategory(this.key, this.label);

  static SupportCategory fromKey(String? key) {
    if (key == null || key.isEmpty) return SupportCategory.hardwareOther;
    return SupportCategory.values.firstWhere(
      (c) => c.key == key || c.label == key,
      orElse: () => SupportCategory.hardwareOther,
    );
  }
}

class SupportDialogBody extends StatefulWidget {
  final VoidCallback onClose;

  const SupportDialogBody({Key? key, required this.onClose}) : super(key: key);

  @override
  State<SupportDialogBody> createState() => _SupportDialogBodyState();
}

class _SupportDialogBodyState extends State<SupportDialogBody> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _descController = TextEditingController();
  final TextEditingController _contactNameController = TextEditingController();
  final TextEditingController _contactPhoneController = TextEditingController();

  String _deviceId = '';
  String _hostname = '';
  String _username = '';
  String _ipAddress = '';
  String _os = '';

  SupportCategory _selectedCategory = SupportCategory.hisLis;
  String _selectedPriority = 'normal';
  bool _includeLogs = true;
  bool _isSubmitting = false;
  String _errorMessage = '';

  final List<File> _attachedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  @override
  void dispose() {
    _descController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadSystemInfo() async {
    try {
      final id = await bind.mainGetMyId();
      _deviceId = id.replaceAll(' ', '');
    } catch (_) {}

    _hostname = Platform.localHostname;
    _username =
        Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? '';
    _os = Platform.operatingSystemVersion;

    _contactNameController.text = _username;

    // Get Local IP
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && !addr.address.startsWith('169.254.')) {
            _ipAddress = addr.address;
            break;
          }
        }
        if (_ipAddress.isNotEmpty) break;
      }
    } catch (_) {}

    if (mounted) setState(() {});
  }

  String _getRecentLogs() {
    if (!Platform.isWindows) return '';
    final appData = Platform.environment['APPDATA'] ?? '';
    final progData = Platform.environment['ProgramData'] ?? '';
    final dirs = [
      '$appData\\BVĐKKH - Remote\\log',
      '$appData\\RustDesk\\log',
      '$progData\\BVĐKKH - Remote\\log',
      '$progData\\RustDesk\\log',
    ];
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        try {
          final files = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.log'))
              .toList();
          if (files.isNotEmpty) {
            files.sort(
                (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
            final lines = files.first.readAsLinesSync();
            if (lines.length > 50) {
              return lines.sublist(lines.length - 50).join('\n');
            }
            return lines.join('\n');
          }
        } catch (_) {}
      }
    }
    return '';
  }

  Future<void> _pickAttachments() async {
    if (_attachedFiles.length >= 5) {
      _showToastWarning('Chỉ đính kèm tối đa 5 tệp tin!');
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'bmp',
          'pdf',
          'doc',
          'docx',
          'txt',
          'log'
        ],
      );

      if (result != null && result.paths.isNotEmpty) {
        for (final p in result.paths) {
          if (p != null) {
            final f = File(p);
            if (f.existsSync()) {
              if (f.lengthSync() > 10 * 1024 * 1024) {
                _showToastWarning(
                    'Tệp ${f.path.split(Platform.pathSeparator).last} vượt quá 10MB!');
                continue;
              }
              if (_attachedFiles.length < 5 &&
                  !_attachedFiles.any((existing) => existing.path == f.path)) {
                _attachedFiles.add(f);
              }
            }
          }
        }
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error picking attachments: $e');
    }
  }

  void _showToastWarning(String msg) {
    BotToast.showText(
      text: msg,
      contentColor: Colors.amber.shade900,
      textStyle:
          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
    );
  }

  Future<void> _submitTicket() async {
    if (_isSubmitting) return;

    final desc = _descController.text.trim();
    if (desc.length < 5) {
      setState(() {
        _errorMessage =
            'Vui lòng nhập mô tả sự cố cụ thể hơn (tối thiểu 5 ký tự).';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = '';
    });

    try {
      if (_deviceId.isEmpty) {
        try {
          final id = await bind.mainGetMyId();
          _deviceId = id.replaceAll(' ', '');
        } catch (_) {}
      }

      if (_deviceId.isEmpty) {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Chưa lấy được ID máy trạm RustDesk. Vui lòng thử lại sau vài giây!';
        });
        return;
      }

      var apiServer = await bind.mainGetApiServer();
      if (apiServer.isEmpty) {
        apiServer = 'http://172.16.3.28:21114';
      }
      if (!apiServer.startsWith('http://') &&
          !apiServer.startsWith('https://')) {
        apiServer = 'http://$apiServer';
      }

      final url = Uri.parse('$apiServer/api/support/ticket');
      final request = http.MultipartRequest('POST', url);

      final token = bind.mainGetLocalOption(key: 'access_token');
      if (token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['device_id'] = _deviceId;
      request.fields['hostname'] = _hostname;
      request.fields['username'] = _username;
      request.fields['ip_address'] = _ipAddress;
      request.fields['os'] = _os;
      request.fields['category'] = _selectedCategory.key;
      request.fields['priority'] = _selectedPriority;
      request.fields['description'] = desc;
      request.fields['contact_name'] = _contactNameController.text.trim();
      request.fields['contact_phone'] = _contactPhoneController.text.trim();

      if (_includeLogs) {
        final logs = _getRecentLogs();
        if (logs.isNotEmpty) {
          request.fields['logs'] = logs;
        }
      }

      for (final file in _attachedFiles) {
        if (file.existsSync()) {
          request.files.add(await http.MultipartFile.fromPath(
            'attachments',
            file.path,
          ));
        }
      }

      final streamedResponse =
          await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final body = json.decode(utf8.decode(response.bodyBytes));
        int createdId = 0;
        if (body['data'] != null && body['data']['id'] != null) {
          final idVal = body['data']['id'];
          createdId =
              idVal is int ? idVal : (int.tryParse(idVal.toString()) ?? 0);
        }

        // Bắt đầu kích hoạt Client Watcher để lắng nghe phản hồi của KTV IT
        if (createdId > 0) {
          SupportTicketListener.instance.trackTicket(createdId);
        }

        // Đóng dialog
        widget.onClose();

        // Hiển thị thông báo gửi thành công
        _showSuccessNotification(createdId);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage =
              'Máy chủ phản hồi lỗi (${response.statusCode}): ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage =
            'Không thể kết nối máy chủ IT ($e).\nVui lòng liên hệ trực tiếp phòng CNTT!';
      });
    }
  }

  void _showSuccessNotification(int ticketId) {
    BotToast.showCustomNotification(
      duration: const Duration(seconds: 10),
      toastBuilder: (cancelFunc) {
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: 8,
          color: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF10B981), width: 2),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ĐÃ GỬI YÊU CẦU HỖ TRỢ #${ticketId > 0 ? ticketId : ""}',
                        style: const TextStyle(
                          color: Color(0xFF6EE7B7),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Kỹ thuật viên IT đã nhận thông báo. Khi KTV tiếp nhận hoặc xử lý xong, hệ thống sẽ gửi thông báo góc phải màn hình cho bạn.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 18),
                  onPressed: cancelFunc,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top: 14),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // System Info Strip
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _buildInfoBadge('ID Máy', _deviceId, Icons.computer),
                    _buildInfoBadge('Máy tính', _hostname, Icons.desktop_mac),
                    _buildInfoBadge('Tài khoản', _username, Icons.person),
                    if (_ipAddress.isNotEmpty)
                      _buildInfoBadge('IP', _ipAddress, Icons.network_check),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Category & Priority
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Danh mục sự cố *',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<SupportCategory>(
                              isExpanded: true,
                              value: _selectedCategory,
                              items: SupportCategory.values.map((cat) {
                                return DropdownMenuItem<SupportCategory>(
                                  value: cat,
                                  child: Text(
                                    cat.label,
                                    style: const TextStyle(fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedCategory = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mức độ ưu tiên',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPriorityButton(
                                label: 'Bình thường',
                                value: 'normal',
                                color: const Color(0xFF2563EB),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildPriorityButton(
                                label: 'Khẩn cấp',
                                value: 'urgent',
                                color: const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Description
              const Text(
                'Mô tả chi tiết sự cố *',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _descController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText:
                      'Mô tả cụ thể sự cố đang gặp phải (ví dụ: máy in phòng khám không in được phiếu chỉ định, không kết nối được mạng HIS...)',
                  hintStyle:
                      TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
              const SizedBox(height: 14),

              // Contact Name & Phone
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Họ tên người gửi',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _contactNameController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.person_outline,
                                size: 18, color: Colors.grey),
                            hintText: 'Tên bác sĩ / điều dưỡng...',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Số điện thoại / Máy lẻ',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _contactPhoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.phone_outlined,
                                size: 18, color: Colors.grey),
                            hintText: 'Ví dụ: 102, 0905...',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide:
                                  BorderSide(color: Colors.grey.shade300),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Attachments & Logs
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF93C5FD)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: Text(
                      _attachedFiles.isEmpty
                          ? 'Đính kèm ảnh / tệp tin'
                          : 'Đã đính kèm (${_attachedFiles.length}/5)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: _pickAttachments,
                  ),
                  const Spacer(),
                  Checkbox(
                    value: _includeLogs,
                    onChanged: (val) =>
                        setState(() => _includeLogs = val ?? true),
                  ),
                  const Text('Gửi kèm log RustDesk',
                      style: TextStyle(fontSize: 12)),
                ],
              ),

              // Attached Files Chips
              if (_attachedFiles.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _attachedFiles.map((f) {
                    final fileName = f.path.split(Platform.pathSeparator).last;
                    return Chip(
                      label: Text(
                        fileName,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteIcon: const Icon(Icons.close, size: 14),
                      onDeleted: () {
                        setState(() => _attachedFiles.remove(f));
                      },
                      visualDensity: VisualDensity.compact,
                      backgroundColor: Colors.blue.shade50,
                    );
                  }).toList(),
                ),
              ],

              // Error banner
              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isSubmitting ? null : widget.onClose,
                    child: const Text('HỦY BỎ'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded, size: 16),
                    label: Text(
                      _isSubmitting ? 'ĐANG GỬI...' : 'GỬI YÊU CẦU HỖ TRỢ',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: _isSubmitting ? null : _submitTicket,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBadge(String label, String value, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text('$label: ',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
        Text(
          value.isNotEmpty ? value : 'N/A',
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              fontFamily: 'monospace'),
        ),
      ],
    );
  }

  Widget _buildPriorityButton({
    required String label,
    required String value,
    required Color color,
  }) {
    final isSelected = _selectedPriority == value;
    return InkWell(
      onTap: () => setState(() => _selectedPriority = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
