import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class AllCustomersPage extends StatefulWidget {
  const AllCustomersPage({super.key});

  @override
  State<AllCustomersPage> createState() => _AllCustomersPageState();
}

class _AllCustomersPageState extends State<AllCustomersPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _headingController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<PlatformFile> _selectedFiles = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = Uuid();

  bool _isLoading = false;
  bool _isSendSuccess = false;
  String _errorMessage = '';
  int _customerCount = 0;
  int _successfulSends = 0;

  // Main color to match other pages
  final Color primaryColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _fetchCustomerCount();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _headingController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Fixed customer count fetching to ensure it works correctly
  Future<void> _fetchCustomerCount() async {
    try {
      // First set loading state
      setState(() {
        _customerCount = 0;
      });

      // Get actual count from database with direct query
      final QuerySnapshot customersSnapshot =
          await _firestore.collection('customers').get();

      // Update count in UI
      if (mounted) {
        setState(() {
          _customerCount = customersSnapshot.docs.length;
        });
      }

      // Debug logging to verify count
      debugPrint('Customer count fetched: $_customerCount customers found');
    } catch (e) {
      debugPrint('Error getting customer count: $e');
      debugPrint('Stack trace: ${StackTrace.current}');
    }
  }

  // Retry count fetch if it fails
  void _retryFetchCount() {
    debugPrint('Retrying customer count fetch');
    _fetchCustomerCount();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'pdf', 'doc', 'docx', 'xls', 'xlsx'],
      withData: true, // Ensure we have the file data for upload
    );

    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles.addAll(result.files);
      });
    }
  }

  // New method to upload files to Firebase Storage
  Future<List<Map<String, dynamic>>> _uploadFiles() async {
    List<Map<String, dynamic>> uploadedFiles = [];

    for (var file in _selectedFiles) {
      try {
        // Generate unique filename to avoid conflicts
        String uniqueFileName = '${_uuid.v4()}_${file.name}';
        String fileExtension = path.extension(file.name).toLowerCase();

        // Determine the storage folder based on file type
        String folderPath = 'message_attachments';
        if (['.jpg', '.png', '.jpeg'].contains(fileExtension)) {
          folderPath = 'message_attachments/images';
        } else if (fileExtension == '.pdf') {
          folderPath = 'message_attachments/documents';
        } else if (['.doc', '.docx'].contains(fileExtension)) {
          folderPath = 'message_attachments/word';
        } else if (['.xls', '.xlsx'].contains(fileExtension)) {
          folderPath = 'message_attachments/excel';
        }

        // Create storage reference
        final storageRef = _storage.ref().child('$folderPath/$uniqueFileName');

        // Upload file
        UploadTask uploadTask;

        if (file.bytes != null) {
          // Web platform upload from bytes
          uploadTask = storageRef.putData(
            file.bytes!,
            SettableMetadata(contentType: lookupMimeType(file.name)),
          );
        } else if (file.path != null) {
          // Mobile/desktop platform upload from file path
          final fileObj = File(file.path!);
          uploadTask = storageRef.putFile(fileObj);
        } else {
          throw Exception('No valid file data available for upload');
        }

        // Wait for upload to complete
        final TaskSnapshot snapshot = await uploadTask;
        final downloadUrl = await snapshot.ref.getDownloadURL();

        uploadedFiles.add({
          'name': file.name,
          'originalName': file.name,
          'storagePath': storageRef.fullPath,
          'downloadUrl': downloadUrl,
          'fileType': fileExtension.replaceAll('.', ''),
          'size': file.size,
        });

        debugPrint('File uploaded: ${file.name} -> $downloadUrl');
      } catch (e) {
        debugPrint('Error uploading file ${file.name}: $e');
        // Continue with other files even if one fails
      }
    }

    return uploadedFiles;
  }

  void _clearAll() {
    setState(() {
      _messageController.clear();
      _headingController.clear();
      _selectedFiles.clear();
      _errorMessage = '';
      _isSendSuccess = false;
    });
  }

  Future<void> _sendMessage() async {
    // Validate inputs
    if (_headingController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a message heading';
      });
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a message';
      });
      return;
    }

    if (_customerCount <= 0) {
      setState(() {
        _errorMessage = 'No customers available to send messages to';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _isSendSuccess = false;
      _successfulSends = 0;
    });

    try {
      debugPrint('Starting to send messages to all customers...');

      // Get all customers from the database
      final customersSnapshot = await _firestore.collection('customers').get();

      if (customersSnapshot.docs.isEmpty) {
        setState(() {
          _errorMessage = 'No customers found in the database';
          _isLoading = false;
        });
        debugPrint('No customers found');
        return;
      }

      debugPrint('Found ${customersSnapshot.docs.length} customers to message');

      // Current date and time
      final now = DateTime.now();
      final dateFormatted = DateFormat('yyyy-MM-dd').format(now);
      final timeFormatted = DateFormat('hh:mm a').format(now);

      // Upload files first if any were selected
      List<Map<String, dynamic>> attachmentData = [];
      if (_selectedFiles.isNotEmpty) {
        debugPrint('Uploading ${_selectedFiles.length} attachments');
        attachmentData = await _uploadFiles();
        debugPrint('Successfully uploaded ${attachmentData.length} files');
      }

      // Individual writes with error handling for each customer
      int successCount = 0;
      List<String> failedCustomers = [];

      for (var customerDoc in customersSnapshot.docs) {
        try {
          final customerId = customerDoc.id;
          final customerName = customerDoc.data()['fullName'] ?? 'Unknown';

          debugPrint('Sending message to: $customerName (ID: $customerId)');

          // Create a new document in the messages collection
          final messageRef = _firestore.collection('messages').doc();

          // Message data
          final messageData = {
            'customerId': customerId,
            'customerName': customerName,
            'customerNic': customerDoc.data()['nic'] ?? 'Unknown',
            'heading': _headingController.text.trim(),
            'message': _messageController.text.trim(),
            'date': dateFormatted,
            'time': timeFormatted,
            'senderId': 'Unicon Finance',
            'isRead': false,
            'attachments': attachmentData.isEmpty ? [] : attachmentData,
            'sentToAll': true,
            'createdAt': FieldValue.serverTimestamp(),
          };

          // Set the document
          await messageRef.set(messageData);

          successCount++;
          debugPrint('Successfully sent message to $customerName');
        } catch (e) {
          failedCustomers.add(customerDoc.id);
          debugPrint('Error sending message to customer ${customerDoc.id}: $e');
        }
      }

      if (successCount > 0) {
        debugPrint('Successfully sent messages to $successCount customers');
        setState(() {
          _successfulSends = successCount;
          _isSendSuccess = true;
          _isLoading = false;
        });

        // Clear all data after successful send
        _clearAll();
      } else {
        throw Exception('Failed to send any messages');
      }
    } catch (e) {
      debugPrint('Error in _sendMessage: $e');
      setState(() {
        _errorMessage = 'Error sending messages: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Icon _getFileIcon(String fileName) {
    final mimeType = lookupMimeType(fileName) ?? '';
    if (mimeType.startsWith('image/')) {
      return Icon(Icons.image_outlined, size: 24, color: primaryColor);
    }
    if (mimeType.startsWith('video/')) {
      return Icon(Icons.videocam_outlined, size: 24, color: primaryColor);
    }
    if (mimeType == 'application/pdf') {
      return const Icon(
        Icons.picture_as_pdf_outlined,
        size: 24,
        color: Colors.red,
      );
    }
    if (mimeType.contains('word')) {
      return const Icon(
        Icons.description_outlined,
        size: 24,
        color: Colors.blue,
      );
    }
    if (mimeType.contains('excel')) {
      return const Icon(Icons.grid_on_outlined, size: 24, color: Colors.green);
    }
    return Icon(
      Icons.insert_drive_file_outlined,
      size: 24,
      color: Colors.grey.shade600,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 100,
          vertical: 32,
        ), // Added horizontal margin of 100
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: ScrollConfiguration(
          // Hide scrollbars but keep scrolling functionality
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: SingleChildScrollView(
            controller: _scrollController,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    64, // Account for padding
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: primaryColor.withAlpha((0.1 * 255).toInt()),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.campaign_outlined,
                          color: primaryColor,
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Message All Customers',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'Send a message to all registered customers',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withAlpha(
                                      (0.1 * 255).toInt(),
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.people_alt_outlined,
                                        size: 16,
                                        color: primaryColor,
                                      ),
                                      const SizedBox(width: 4),
                                      _customerCount > 0
                                          ? Text(
                                            '$_customerCount Customers',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: primaryColor,
                                            ),
                                          )
                                          : InkWell(
                                            onTap: _retryFetchCount,
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(primaryColor),
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  "Loading...",
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: primaryColor,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Help icon
                      IconButton(
                        icon: Icon(
                          Icons.help_outline,
                          size: 24,
                          color: primaryColor,
                        ),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Your message will be sent to all registered customers in the system.',
                              ),
                              backgroundColor: primaryColor,
                              duration: const Duration(seconds: 5),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 40),

                  // Message form - Card with beautiful shadow and rounded corners
                  Card(
                    elevation: 6,
                    shadowColor: Colors.black.withAlpha((0.1 * 255).toInt()),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Form header with icon
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primaryColor.withAlpha(
                                    (0.1 * 255).toInt(),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.edit_note_rounded,
                                  color: primaryColor,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Text(
                                "Compose Your Message",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 30),

                          // Success message with animation
                          if (_isSendSuccess)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withAlpha(
                                      (0.1 * 255).toInt(),
                                    ),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.check,
                                      color: Colors.green.shade700,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Messages Sent Successfully!',
                                              style: TextStyle(
                                                color: Colors.green.shade700,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                _successfulSends > 0
                                                    ? "$_successfulSends messages"
                                                    : "All messages",
                                                style: TextStyle(
                                                  color: Colors.green.shade900,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Your message has been sent to all registered customers.',
                                          style: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.green.shade700,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _isSendSuccess = false;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),

                          // Error message
                          if (_errorMessage.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.red.shade200),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.error_outline,
                                      color: Colors.red.shade700,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Error Sending Messages',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _errorMessage,
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.close,
                                      size: 20,
                                      color: Colors.red.shade700,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _errorMessage = '';
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),

                          // Form section - with increased spacing and better visual hierarchy
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Section label
                                Text(
                                  "MESSAGE DETAILS",
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade600,
                                    letterSpacing: 1.2,
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // Message heading
                                TextField(
                                  controller: _headingController,
                                  decoration: InputDecoration(
                                    labelText: "Message Heading",
                                    labelStyle: TextStyle(
                                      color: primaryColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    hintText: "Enter a clear, concise heading",
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(
                                        color: primaryColor,
                                        width: 2,
                                      ),
                                    ),
                                    prefixIcon: Icon(
                                      Icons.title,
                                      color: primaryColor,
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 16,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // Message body with attachments integrated
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      // Message body header
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: const BorderRadius.only(
                                            topLeft: Radius.circular(11),
                                            topRight: Radius.circular(11),
                                          ),
                                          border: Border(
                                            bottom: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.message_outlined,
                                              size: 18,
                                              color: primaryColor,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              "Message Content",
                                              style: TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade700,
                                              ),
                                            ),
                                            const Spacer(),
                                            if (_selectedFiles.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: primaryColor.withAlpha(
                                                    (0.1 * 255).toInt(),
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.attach_file,
                                                      size: 14,
                                                      color: primaryColor,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      "${_selectedFiles.length}",
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        color: primaryColor,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),

                                      // Message body content
                                      SizedBox(
                                        height:
                                            220, // Smaller height to make room for attachments
                                        child: ScrollConfiguration(
                                          // Hide scrollbars for TextField
                                          behavior: ScrollConfiguration.of(
                                            context,
                                          ).copyWith(scrollbars: false),
                                          child: TextField(
                                            controller: _messageController,
                                            maxLines: null,
                                            expands: true,
                                            decoration: InputDecoration(
                                              hintText:
                                                  "Type your message here...",
                                              hintStyle: TextStyle(
                                                color: Colors.grey.shade400,
                                                fontSize: 15,
                                              ),
                                              border: InputBorder.none,
                                              contentPadding:
                                                  const EdgeInsets.all(16),
                                            ),
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey.shade800,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // Attachments section integrated in message box
                                      if (_selectedFiles.isNotEmpty)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade50,
                                            border: Border(
                                              top: BorderSide(
                                                color: Colors.grey.shade200,
                                              ),
                                            ),
                                          ),
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 8.0,
                                                  left: 4.0,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.attachment,
                                                      size: 16,
                                                      color:
                                                          Colors.grey.shade700,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      "Attachments",
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade700,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    TextButton.icon(
                                                      onPressed: () {
                                                        setState(() {
                                                          _selectedFiles
                                                              .clear();
                                                        });
                                                      },
                                                      icon: Icon(
                                                        Icons.delete_outline,
                                                        size: 16,
                                                        color:
                                                            Colors.red.shade600,
                                                      ),
                                                      label: Text(
                                                        "Clear",
                                                        style: TextStyle(
                                                          color:
                                                              Colors
                                                                  .red
                                                                  .shade600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              SizedBox(
                                                height: 80,
                                                child: ScrollConfiguration(
                                                  // Hide scrollbars for horizontal attachment list
                                                  behavior:
                                                      ScrollConfiguration.of(
                                                        context,
                                                      ).copyWith(
                                                        scrollbars: false,
                                                      ),
                                                  child: ListView.builder(
                                                    scrollDirection:
                                                        Axis.horizontal,
                                                    itemCount:
                                                        _selectedFiles.length,
                                                    itemBuilder: (
                                                      context,
                                                      index,
                                                    ) {
                                                      final file =
                                                          _selectedFiles[index];
                                                      return Container(
                                                        width: 200,
                                                        margin:
                                                            const EdgeInsets.only(
                                                              right: 10,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                8,
                                                              ),
                                                          border: Border.all(
                                                            color:
                                                                Colors
                                                                    .grey
                                                                    .shade200,
                                                          ),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    8,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    Colors
                                                                        .grey
                                                                        .shade50,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      6,
                                                                    ),
                                                              ),
                                                              child:
                                                                  _getFileIcon(
                                                                    file.name,
                                                                  ),
                                                            ),
                                                            const SizedBox(
                                                              width: 8,
                                                            ),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Text(
                                                                    file.name,
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          12,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500,
                                                                      color:
                                                                          Colors
                                                                              .grey
                                                                              .shade800,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  const SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    '${(file.size / 1024).toStringAsFixed(1)} KB',
                                                                    style: TextStyle(
                                                                      fontSize:
                                                                          11,
                                                                      color:
                                                                          Colors
                                                                              .grey
                                                                              .shade600,
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                            IconButton(
                                                              icon: Icon(
                                                                Icons.close,
                                                                size: 16,
                                                                color:
                                                                    Colors
                                                                        .grey
                                                                        .shade600,
                                                              ),
                                                              onPressed: () {
                                                                setState(() {
                                                                  _selectedFiles
                                                                      .removeAt(
                                                                        index,
                                                                      );
                                                                });
                                                              },
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              constraints:
                                                                  const BoxConstraints(),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                      // Attachment button
                                      Container(
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade50,
                                          borderRadius: const BorderRadius.only(
                                            bottomLeft: Radius.circular(11),
                                            bottomRight: Radius.circular(11),
                                          ),
                                          border: Border(
                                            top: BorderSide(
                                              color: Colors.grey.shade200,
                                            ),
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            TextButton.icon(
                                              onPressed: _pickFiles,
                                              icon: Icon(
                                                Icons.attach_file,
                                                size: 18,
                                                color: primaryColor,
                                              ),
                                              label: Text(
                                                "Add Attachment",
                                                style: TextStyle(
                                                  color: primaryColor,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 8,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                backgroundColor: primaryColor
                                                    .withAlpha(
                                                      (0.1 * 255).toInt(),
                                                    ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              "Supported: JPG, PNG, PDF, DOC, DOCX, XLS, XLSX",
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600,
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Action buttons
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed:
                                      _isLoading || _customerCount <= 0
                                          ? null
                                          : _sendMessage,
                                  icon:
                                      _isLoading
                                          ? Container(
                                            width: 20,
                                            height: 20,
                                            padding: const EdgeInsets.all(2),
                                            child:
                                                const CircularProgressIndicator(
                                                  color: Colors.white,
                                                  strokeWidth: 2,
                                                ),
                                          )
                                          : const Icon(
                                            Icons.send_outlined,
                                            size: 20,
                                          ),
                                  label: Text(
                                    _isLoading
                                        ? "Sending..."
                                        : "Send to All $_customerCount Customers",
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: primaryColor,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor:
                                        Colors.grey.shade300,
                                    disabledForegroundColor:
                                        Colors.grey.shade600,
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 18,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              ElevatedButton.icon(
                                onPressed: _isLoading ? null : _clearAll,
                                icon: const Icon(Icons.clear_all, size: 20),
                                label: const Text(
                                  "Clear All",
                                  style: TextStyle(fontSize: 16),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade100,
                                  foregroundColor: Colors.grey.shade700,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 18,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
