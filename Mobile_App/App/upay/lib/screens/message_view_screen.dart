import 'package:flutter/material.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'package:http/http.dart' as http;

class MessageViewScreen extends StatefulWidget {
  final Map<String, dynamic> message;
  final String messageId;
  final VoidCallback onDelete;

  const MessageViewScreen({
    super.key,
    required this.message,
    required this.messageId,
    required this.onDelete,
  });

  @override
  State<MessageViewScreen> createState() => _MessageViewScreenState();
}

class _MessageViewScreenState extends State<MessageViewScreen> {
  bool isDownloading = false;
  double downloadProgress = 0.0;
  String downloadingFileName = '';
  List<Map<String, dynamic>> _attachments = [];
  bool _isLoading = false;
  File? downloadedFile;

  @override
  void initState() {
    super.initState();
    _loadAttachments();
  }

  Future<void> _loadAttachments() async {
    if (widget.message['attachments'] == null) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final attachments = widget.message['attachments'] as List;
      _attachments = List<Map<String, dynamic>>.from(attachments);
    } catch (e) {
      debugPrint('Error loading attachments: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = AppLocalizations.of(context);

    // Format date
    String formattedDate = '';
    if (widget.message['createdAt'] != null) {
      try {
        final timestamp = widget.message['createdAt'] as Timestamp;
        final dateTime = timestamp.toDate();
        formattedDate = DateFormat(
          'EEEE, MMM d, yyyy • h:mm a',
          appLocalizations?.localeName,
        ).format(dateTime);
      } catch (e) {
        formattedDate =
            appLocalizations?.date_not_available ?? 'Date not available';
      }
    }

    // Extract message title and content
    final String title =
        widget.message['heading'] ?? (appLocalizations?.message ?? 'Message');
    final String content =
        widget.message['message'] ??
        (appLocalizations?.no_content ?? 'No content');

    // Get icon based on message heading
    IconData icon;
    Color iconColor;
    Color iconBgColor;
    String lowerTitle = title.toLowerCase();

    // Determine icon and color based on message heading
    if (lowerTitle.contains('alert') || lowerTitle.contains('important')) {
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.red;
      iconBgColor = Colors.red.shade100;
    } else if (lowerTitle.contains('monthly payment') ||
        lowerTitle.contains('card')) {
      icon = Icons.credit_card;
      iconColor = Colors.blue;
      iconBgColor = Colors.blue.shade100;
    } else if (lowerTitle.contains('bill') || lowerTitle.contains('invoice')) {
      icon = Icons.receipt_long;
      iconColor = Colors.orange;
      iconBgColor = Colors.orange.shade100;
    } else if (lowerTitle.contains('offer') ||
        lowerTitle.contains('discount')) {
      icon = Icons.local_offer;
      iconColor = Colors.purple;
      iconBgColor = Colors.purple.shade100;
    } else if (lowerTitle.contains('arrears') ||
        lowerTitle.contains('location')) {
      icon = Icons.warning_rounded;
      iconColor = Colors.green;
      iconBgColor = Colors.green.shade100;
    } else if (lowerTitle.contains('pay')) {
      icon = Icons.payment;
      iconColor = Colors.green.shade700;
      iconBgColor = Colors.green.shade100;
    } else if (lowerTitle.contains('installment')) {
      icon = Icons.calendar_month;
      iconColor = Colors.indigo;
      iconBgColor = Colors.indigo.shade100;
    } else {
      icon = Icons.mail;
      iconColor = Colors.blue;
      iconBgColor = Colors.blue.shade100;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 50),
            // Custom AppBar with delete button - matching the notification screen layout
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  appLocalizations?.message_details ?? 'Message Details',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                // Delete icon on the right
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onDelete,
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(
                          Icons.delete_outline,
                          color: Color.fromARGB(255, 12, 24, 92),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 50),

            // Main content
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message header with icon
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(13),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: iconBgColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Icon(icon, size: 30, color: iconColor),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    formattedDate,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Message content
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(
                                (0.05 * 255).toInt(),
                              ),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appLocalizations?.message ?? 'Message',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              content,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Attachments section
                      if (_attachments.isNotEmpty || _isLoading) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(
                                  (0.05 * 255).toInt(),
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.attach_file,
                                    size: 20,
                                    color: Theme.of(context).primaryColor,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    appLocalizations?.attachments != null
                                        ? '${appLocalizations!.attachments} (${_attachments.length})'
                                        : 'Attachments (${_attachments.length})',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Loading indicator for attachments
                              if (_isLoading)
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20.0,
                                    ),
                                    child: CircularProgressIndicator(
                                      color: Theme.of(context).primaryColor,
                                    ),
                                  ),
                                )
                              else
                                ..._buildAttachmentsList(),
                            ],
                          ),
                        ),
                      ],

                      // Download progress indicator
                      if (isDownloading)
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 24),
                          padding: const EdgeInsets.all(16),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(
                                  (0.05 * 255).toInt(),
                                ),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                downloadingFileName.isNotEmpty
                                    ? '${appLocalizations?.downloading ?? 'Downloading'} $downloadingFileName'
                                    : (appLocalizations?.downloading ??
                                        'Downloading'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: downloadProgress,
                                  backgroundColor: Colors.grey.shade200,
                                  minHeight: 8,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).primaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${(downloadProgress * 100).toStringAsFixed(0)}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAttachmentsList() {
    final appLocalizations = AppLocalizations.of(context);

    return _attachments.map((attachment) {
      final String fileName = attachment['name'] ?? 'File';
      final String downloadUrl =
          attachment['url'] ?? attachment['downloadUrl'] ?? '';
      final String fileType =
          attachment['fileType'] ?? _getFileTypeFromName(fileName);
      final int fileSize = attachment['size'] ?? 0;

      // Format file size
      String formattedSize = '';
      if (fileSize > 0) {
        if (fileSize < 1024) {
          formattedSize = '$fileSize B';
        } else if (fileSize < 1024 * 1024) {
          formattedSize = '${(fileSize / 1024).toStringAsFixed(1)} KB';
        } else {
          formattedSize = '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
        }
      }

      // Check if it's an image (for icon selection only, no preview)
      final bool isImage =
          fileType.toLowerCase().contains('image') ||
          fileType.toLowerCase() == 'png' ||
          fileType.toLowerCase() == 'jpg' ||
          fileType.toLowerCase() == 'jpeg' ||
          fileName.toLowerCase().endsWith('.png') ||
          fileName.toLowerCase().endsWith('.jpg') ||
          fileName.toLowerCase().endsWith('.jpeg');

      // Get file icon - use image icon for images
      final IconData fileIcon = isImage ? Icons.image : _getFileIcon(fileName);
      final Color iconColor = isImage ? Colors.blue : _getIconColor(fileName);

      // Display all files in the same list item style
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withAlpha((0.1 * 255).toInt()),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(fileIcon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (formattedSize.isNotEmpty)
                    Text(
                      formattedSize,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                _buildIconButton(
                  icon: Icons.open_in_new,
                  onPressed: () => _openFile(downloadUrl, fileType, fileName),
                  tooltip: appLocalizations?.open ?? 'Open',
                ),
                _buildIconButton(
                  icon: Icons.file_download_outlined,
                  onPressed:
                      () => _downloadFile(downloadUrl, fileName, fileType),
                  tooltip: appLocalizations?.download ?? 'Download',
                ),
                _buildIconButton(
                  icon: Icons.share,
                  onPressed: () => _shareFile(downloadUrl, fileName, fileType),
                  tooltip: appLocalizations?.share ?? 'Share',
                ),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return IconButton(
      icon: Icon(icon, color: Theme.of(context).primaryColor),
      onPressed: onPressed,
      iconSize: 22,
      splashRadius: 24,
      tooltip: tooltip,
    );
  }

  String _getFileTypeFromName(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
      return 'image/$extension';
    } else if (extension == 'pdf') {
      return 'application/pdf';
    } else if (['doc', 'docx'].contains(extension)) {
      return 'application/msword';
    } else if (['xls', 'xlsx'].contains(extension)) {
      return 'application/excel';
    } else if (['ppt', 'pptx'].contains(extension)) {
      return 'application/powerpoint';
    } else if (['mp3', 'wav'].contains(extension)) {
      return 'audio/$extension';
    } else if (['mp4', 'mov', 'avi'].contains(extension)) {
      return 'video/$extension';
    } else {
      return 'application/octet-stream';
    }
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;

    if (['pdf'].contains(extension)) {
      return Icons.picture_as_pdf;
    } else if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
      return Icons.image;
    } else if (['doc', 'docx'].contains(extension)) {
      return Icons.description;
    } else if (['xls', 'xlsx'].contains(extension)) {
      return Icons.table_chart;
    } else if (['ppt', 'pptx'].contains(extension)) {
      return Icons.slideshow;
    } else if (['mp3', 'wav', 'ogg'].contains(extension)) {
      return Icons.audiotrack;
    } else if (['mp4', 'mov', 'avi'].contains(extension)) {
      return Icons.videocam;
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      return Icons.folder_zip;
    } else {
      return Icons.insert_drive_file;
    }
  }

  Color _getIconColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;

    if (['pdf'].contains(extension)) {
      return Colors.red;
    } else if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
      return Colors.blue;
    } else if (['doc', 'docx'].contains(extension)) {
      return Colors.blue.shade800;
    } else if (['xls', 'xlsx'].contains(extension)) {
      return Colors.green;
    } else if (['ppt', 'pptx'].contains(extension)) {
      return Colors.orange;
    } else if (['mp3', 'wav', 'ogg'].contains(extension)) {
      return Colors.purple;
    } else if (['mp4', 'mov', 'avi'].contains(extension)) {
      return Colors.red.shade800;
    } else if (['zip', 'rar', '7z'].contains(extension)) {
      return Colors.amber.shade800;
    } else {
      return Colors.blueGrey;
    }
  }

  // FIXED FILE OPENER - opens directly without asking for download
  Future<void> _openFile(String url, String fileType, String fileName) async {
    final appLocalizations = AppLocalizations.of(context);

    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.file_url_not_available ??
                'File URL is not available',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
      downloadingFileName =
          '${appLocalizations?.opening ?? 'Opening'} $fileName...';
    });

    try {
      // STRATEGY 1: Try direct URL launch first - fastest method
      setState(() {
        downloadProgress = 0.3;
        downloadingFileName =
            '${appLocalizations?.opening_remote_file ?? 'Opening remote file'}...';
      });

      final Uri directUri = Uri.parse(url);
      bool launched = false;

      try {
        launched = await launchUrl(
          directUri,
          mode: LaunchMode.externalApplication,
        );

        if (launched) {
          setState(() {
            isDownloading = false;
          });
          return;
        }
      } catch (e) {
        debugPrint('Direct URL launch failed: $e');
      }

      // STRATEGY 2: For PDF and documents on Android, try Google Docs viewer
      if (!launched &&
          Platform.isAndroid &&
          (fileType.contains('pdf') ||
              fileType.contains('doc') ||
              fileName.toLowerCase().endsWith('.pdf') ||
              fileName.toLowerCase().endsWith('.docx'))) {
        setState(() {
          downloadProgress = 0.4;
          downloadingFileName =
              '${appLocalizations?.opening_with_viewer ?? 'Opening with online viewer'}...';
        });

        try {
          final googleDocsUrl = Uri.parse(
            'https://docs.google.com/viewer?url=${Uri.encodeComponent(url)}',
          );
          launched = await launchUrl(
            googleDocsUrl,
            mode: LaunchMode.externalApplication,
          );

          if (launched) {
            setState(() {
              isDownloading = false;
            });
            return;
          }
        } catch (e) {
          debugPrint('Google Docs viewer failed: $e');
        }
      }

      // STRATEGY 3: Download and then launch the file
      setState(() {
        downloadProgress = 0.5;
        downloadingFileName =
            '${appLocalizations?.downloading_for_viewing ?? 'Downloading for viewing'}...';
      });

      // Download to app documents directory (more reliable than cache)
      final appDir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${appDir.path}/${timestamp}_$fileName';
      final file = File(filePath);

      // Download file
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception(
          '${appLocalizations?.download_failed ?? 'Failed to download file'}: HTTP ${response.statusCode}',
        );
      }

      await file.writeAsBytes(response.bodyBytes);

      setState(() {
        downloadProgress = 0.8;
        downloadingFileName =
            '${appLocalizations?.opening ?? 'Opening file'}...';
      });

      // For images and PDFs, try using the Share.shareXFiles method
      // which handles file permissions better than direct file:// URIs
      if (fileType.contains('image') ||
          fileType.contains('pdf') ||
          fileName.toLowerCase().endsWith('.jpg') ||
          fileName.toLowerCase().endsWith('.png') ||
          fileName.toLowerCase().endsWith('.pdf')) {
        try {
          final xFile = XFile(file.path);
          await Share.shareXFiles([
            xFile,
          ], text: '${appLocalizations?.open ?? 'Opening'} $fileName');

          setState(() {
            isDownloading = false;
          });
          return;
        } catch (e) {
          debugPrint('Share.shareXFiles failed: $e');
          // Continue to last resort
        }
      }

      // STRATEGY 4: Last resort - try different ways to launch the file
      if (Platform.isAndroid) {
        try {
          // Try the safest method first - launching the original URL again
          launched = await launchUrl(
            directUri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        } catch (e) {
          debugPrint('External app launch failed: $e');
        }

        if (!launched) {
          // Just inform the user the file is downloaded
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                appLocalizations?.file_ready_opening ??
                    'File ready. Opening with another app...',
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );

          // Try one more time after a short delay
          await Future.delayed(const Duration(seconds: 1));

          try {
            // This will trigger a system file selector
            final directLaunch = await launchUrl(Uri.parse(url));
            if (!directLaunch) {
              throw Exception(
                appLocalizations?.no_app_for_file ??
                    'No app available to open this file',
              );
            }
          } catch (e) {
            debugPrint('Final launch attempt failed: $e');
            throw Exception(
              appLocalizations?.no_app_for_file ??
                  'No app available to open this file type',
            );
          }
        }
      } else {
        // iOS should work better with file URIs
        final fileUri = Uri.file(file.path);
        launched = await launchUrl(fileUri, mode: LaunchMode.platformDefault);

        if (!launched) {
          throw Exception(
            appLocalizations?.no_app_for_file ??
                'No app available to open this file type',
          );
        }
      }

      setState(() {
        isDownloading = false;
      });
    } catch (e) {
      debugPrint('Error opening file: $e');
      setState(() {
        isDownloading = false;
      });

      if (!mounted) return;

      // Auto-download instead of asking
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.opening_failed_downloading ??
                'Opening file failed. Downloading instead...',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );

      // Auto-start download after a short delay
      await Future.delayed(const Duration(seconds: 1));
      _downloadFile(url, fileName, fileType);
    }
  }

  // FIXED DOWNLOAD METHOD
  Future<void> _downloadFile(
    String url,
    String fileName,
    String fileType,
  ) async {
    final appLocalizations = AppLocalizations.of(context);

    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.file_url_not_available ??
                'File URL is not available',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Request storage permission
    var storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      storageStatus = await Permission.storage.request();
    }

    if (!storageStatus.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.storage_permission_required ??
                'Storage permission required to download files',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
      downloadingFileName = fileName;
    });

    try {
      // Download file to memory first to avoid incomplete downloads
      setState(() {
        downloadProgress = 0.3;
      });

      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw Exception(
          '${appLocalizations?.download_failed ?? 'Failed to download'}: HTTP ${response.statusCode}',
        );
      }

      final bytes = response.bodyBytes;

      setState(() {
        downloadProgress = 0.6;
      });

      // Find a suitable download directory
      Directory? downloadDir;
      if (Platform.isAndroid) {
        // Try to get the Downloads directory
        try {
          downloadDir = Directory('/storage/emulated/0/Download');
          if (!await downloadDir.exists()) {
            downloadDir = await getExternalStorageDirectory();
          }
        } catch (e) {
          // Fallback to app-specific directory
          downloadDir = await getApplicationDocumentsDirectory();
        }
      } else {
        // iOS uses documents directory
        downloadDir = await getApplicationDocumentsDirectory();
      }

      // Create a unique filename to avoid overwriting
      String baseName = fileName;
      String extension = '';

      if (fileName.contains('.')) {
        final lastDotIndex = fileName.lastIndexOf('.');
        baseName = fileName.substring(0, lastDotIndex);
        extension = fileName.substring(lastDotIndex);
      }

      // Provide a fallback using null-aware assignment
      downloadDir ??= await getApplicationDocumentsDirectory();

      // Try to find a unique name
      int counter = 1;
      String uniqueFileName = fileName;
      File file = File('${downloadDir.path}/$uniqueFileName');

      while (await file.exists()) {
        uniqueFileName = '$baseName(${counter++})$extension';
        file = File('${downloadDir.path}/$uniqueFileName');
      }

      // Write file in a single operation
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        // Try to save in app's documents directory as fallback
        final appDir = await getApplicationDocumentsDirectory();
        file = File('${appDir.path}/$uniqueFileName');
        await file.writeAsBytes(bytes, flush: true);
      }

      setState(() {
        downloadProgress = 1.0;
        isDownloading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.file_downloaded ?? 'File downloaded successfully',
          ),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: appLocalizations?.view ?? 'VIEW',
            onPressed: () {
              // Use the direct URL to open the file, not a file:// URI
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
          ),
        ),
      );
    } catch (e) {
      debugPrint('Error downloading file: $e');
      setState(() {
        isDownloading = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${appLocalizations?.download_error ?? 'Error downloading file'}: ${e.toString().split(':').first}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // FIXED share file function
  Future<void> _shareFile(String url, String fileName, String fileType) async {
    final appLocalizations = AppLocalizations.of(context);

    if (url.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appLocalizations?.file_url_not_available ??
                'File URL is not available',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() {
      isDownloading = true;
      downloadProgress = 0.0;
      downloadingFileName =
          appLocalizations?.preparing_to_share ?? 'Preparing to share...';
    });

    try {
      // Download to cache first
      setState(() {
        downloadProgress = 0.3;
      });

      final response = await http.get(Uri.parse(url));

      setState(() {
        downloadProgress = 0.6;
      });

      // Use the app's cache directory
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${tempDir.path}/${timestamp}_$fileName';
      final file = File(filePath);

      await file.writeAsBytes(response.bodyBytes);

      setState(() {
        downloadProgress = 0.9;
      });

      // Share using XFile which handles Android 7+ file sharing properly
      final xFile = XFile(file.path);
      await Share.shareXFiles([
        xFile,
      ], text: '${appLocalizations?.sharing ?? 'Sharing'} $fileName');

      setState(() {
        isDownloading = false;
      });
    } catch (e) {
      setState(() {
        isDownloading = false;
      });

      debugPrint('Error sharing file: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${appLocalizations?.sharing_error ?? 'Error sharing file'}: ${e.toString().split(':').first}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
