import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mime/mime.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

class SelectedCustomersPage extends StatefulWidget {
  const SelectedCustomersPage({super.key});

  @override
  State<SelectedCustomersPage> createState() => _SelectedCustomersPageState();
}

class _SelectedCustomersPageState extends State<SelectedCustomersPage> {
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _headingController = TextEditingController();
  final TextEditingController _customerSearchController =
      TextEditingController();

  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();

  final List<PlatformFile> _selectedFiles = [];
  List<Map<String, dynamic>> _allCustomers = [];
  List<Map<String, dynamic>> _filteredCustomers = [];
  final List<Map<String, dynamic>> _selectedCustomers = [];

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = Uuid();

  bool _isLoading = false;
  bool _isLoadingCustomers = true;
  bool _isSendSuccess = false;
  String _errorMessage = '';

  // Main color to match other pages
  final Color primaryColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _fetchCustomers();
    _customerSearchController.addListener(_filterCustomers);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _headingController.dispose();
    _customerSearchController.dispose();
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchCustomers() async {
    setState(() {
      _isLoadingCustomers = true;
    });

    try {
      final customersSnapshot = await _firestore.collection('customers').get();

      final List<Map<String, dynamic>> customers = [];

      for (var doc in customersSnapshot.docs) {
        final data = doc.data();
        customers.add({
          'id': doc.id,
          'fullName': data['fullName'] ?? 'Unknown',
          'nic': data['nic'] ?? 'N/A',
          'accountNumber': data['accountNumber'] ?? 'N/A',
          'customerId': data['customerId'] ?? doc.id.substring(0, 6),
          'imageUrl': data['imageUrl'],
        });
      }

      setState(() {
        _allCustomers = customers;
        _filteredCustomers = List.from(customers);
        _isLoadingCustomers = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingCustomers = false;
        _errorMessage = 'Failed to load customers: ${e.toString()}';
      });
    }
  }

  void _filterCustomers() {
    final query = _customerSearchController.text.toLowerCase();

    setState(() {
      if (query.isEmpty) {
        _filteredCustomers = List.from(_allCustomers);
      } else {
        _filteredCustomers =
            _allCustomers
                .where(
                  (customer) =>
                      customer['fullName'].toString().toLowerCase().contains(
                        query,
                      ) ||
                      customer['nic'].toString().toLowerCase().contains(
                        query,
                      ) ||
                      customer['accountNumber']
                          .toString()
                          .toLowerCase()
                          .contains(query) ||
                      customer['customerId'].toString().toLowerCase().contains(
                        query,
                      ),
                )
                .toList();
      }
    });
  }

  // Updated to add file upload capabilities
  Future<void> _pickFiles() async {
    try {
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
    } catch (e) {
      debugPrint('Error picking files: $e');
      setState(() {
        _errorMessage = 'Failed to select files: ${e.toString()}';
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
      _selectedCustomers.clear();
      _errorMessage = '';
      _isSendSuccess = false;
    });
  }

  void _addCustomer(Map<String, dynamic> customer) {
    // Don't add if already selected
    if (_selectedCustomers.any((c) => c['id'] == customer['id'])) {
      return;
    }

    setState(() {
      _selectedCustomers.add(customer);
      _customerSearchController.clear();
      _filteredCustomers = List.from(_allCustomers);
    });
  }

  // Updated to handle file uploads
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

    if (_selectedCustomers.isEmpty) {
      setState(() {
        _errorMessage = 'Please select at least one customer';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
      _isSendSuccess = false;
    });

    try {
      // Current date and time
      final now = DateTime.now();
      final dateFormatted = DateFormat('yyyy-MM-dd').format(now);
      final timeFormatted = DateFormat('hh:mm a').format(now);

      debugPrint('Sending messages to ${_selectedCustomers.length} customers');

      // Upload files first if any were selected
      List<Map<String, dynamic>> attachmentData = [];
      if (_selectedFiles.isNotEmpty) {
        debugPrint('Uploading ${_selectedFiles.length} attachments');
        attachmentData = await _uploadFiles();
        debugPrint('Successfully uploaded ${attachmentData.length} files');
      }

      // Use individual writes instead of batch for better debugging
      List<String> sentCustomerIds = [];

      for (var customer in _selectedCustomers) {
        debugPrint(
          'Sending message to: ${customer['fullName']} (${customer['id']})',
        );

        try {
          // Create a new document in the messages collection
          DocumentReference messageRef =
              _firestore.collection('messages').doc();

          Map<String, dynamic> messageData = {
            'customerId': customer['id'],
            'customerName': customer['fullName'],
            'customerNic': customer['nic'],
            'heading': _headingController.text.trim(),
            'message': _messageController.text.trim(),
            'date': dateFormatted,
            'time': timeFormatted,
            'senderId': 'Unicon Finance',
            'isRead': false,
            'attachments': attachmentData.isEmpty ? [] : attachmentData,
            'sentToAll': false,
            'createdAt': FieldValue.serverTimestamp(),
          };

          debugPrint('Setting document with data: $messageData');

          // Set the document data
          await messageRef.set(messageData);

          sentCustomerIds.add(customer['id']);
          debugPrint('Successfully sent message to ${customer['fullName']}');
        } catch (innerError) {
          debugPrint(
            'Error sending message to ${customer['fullName']}: $innerError',
          );
        }
      }

      if (sentCustomerIds.isNotEmpty) {
        debugPrint(
          'Successfully sent messages to ${sentCustomerIds.length} customers',
        );
        setState(() {
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
      debugPrint('Stack trace: ${StackTrace.current}');

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

  Widget _buildCustomerSelector() {
    return Card(
      elevation: 6,
      shadowColor: Colors.black.withAlpha((0.1 * 255).toInt()),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          controller: _leftScrollController,
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selector header with icon - Fixed at top
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: primaryColor.withAlpha((0.1 * 255).toInt()),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.people_alt_outlined,
                        color: primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Select Customers",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Search Bar
                TextField(
                  controller: _customerSearchController,
                  decoration: InputDecoration(
                    labelText: "Search Customers",
                    labelStyle: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                    hintText: 'Search by name, NIC, account number, or ID...',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: primaryColor, width: 2),
                    ),
                    prefixIcon: Icon(Icons.search, color: primaryColor),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Selected customers section
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Section header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
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
                                      Icons.check_circle_outline,
                                      size: 16,
                                      color: primaryColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Selected: ${_selectedCustomers.length}",
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                          if (_selectedCustomers.isNotEmpty)
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedCustomers.clear();
                                });
                              },
                              icon: Icon(
                                Icons.clear_all,
                                size: 16,
                                color: Colors.red.shade700,
                              ),
                              label: Text(
                                "Clear All",
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 12,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                              ),
                            ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Selected customers list
                      SizedBox(
                        height: 130,
                        child:
                            _selectedCustomers.isEmpty
                                ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.people_outline,
                                        size: 40,
                                        color: Colors.grey.shade400,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "No customers selected",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Select from the list below",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                : ScrollConfiguration(
                                  behavior: ScrollConfiguration.of(
                                    context,
                                  ).copyWith(scrollbars: false),
                                  child: ListView.separated(
                                    shrinkWrap: true,
                                    itemCount: _selectedCustomers.length,
                                    separatorBuilder:
                                        (context, index) =>
                                            const SizedBox(height: 8),
                                    itemBuilder: (context, index) {
                                      final customer =
                                          _selectedCustomers[index];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: primaryColor.withAlpha(
                                              (0.3 * 255).toInt(),
                                            ),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: primaryColor.withAlpha(
                                                (0.05 * 255).toInt(),
                                              ),
                                              blurRadius: 5,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          children: [
                                            // Customer avatar
                                            CircleAvatar(
                                              radius: 18,
                                              backgroundColor: primaryColor
                                                  .withAlpha(
                                                    (0.2 * 255).toInt(),
                                                  ),
                                              backgroundImage:
                                                  customer['imageUrl'] != null
                                                      ? NetworkImage(
                                                        customer['imageUrl'],
                                                      )
                                                      : null,
                                              child:
                                                  customer['imageUrl'] == null
                                                      ? Text(
                                                        customer['fullName']
                                                            .substring(0, 1)
                                                            .toUpperCase(),
                                                        style: TextStyle(
                                                          color: primaryColor,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      )
                                                      : null,
                                            ),
                                            const SizedBox(width: 12),
                                            // Customer details
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    customer['fullName'],
                                                    style: TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 14,
                                                      color:
                                                          Colors.grey.shade800,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 3),
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors
                                                                    .grey
                                                                    .shade100,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            "ID: ${customer['customerId']}",
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  Colors
                                                                      .grey
                                                                      .shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Flexible(
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets.symmetric(
                                                                horizontal: 6,
                                                                vertical: 2,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors
                                                                    .grey
                                                                    .shade100,
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  4,
                                                                ),
                                                          ),
                                                          child: Text(
                                                            "NIC: ${customer['nic']}",
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color:
                                                                  Colors
                                                                      .grey
                                                                      .shade700,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w500,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            // Remove button
                                            IconButton(
                                              icon: Container(
                                                padding: const EdgeInsets.all(
                                                  4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red.shade50,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: Colors.red.shade600,
                                                ),
                                              ),
                                              onPressed: () {
                                                setState(() {
                                                  _selectedCustomers.remove(
                                                    customer,
                                                  );
                                                });
                                              },
                                              padding: EdgeInsets.zero,
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

                const SizedBox(height: 20),

                // Available customers section
                Text(
                  "AVAILABLE CUSTOMERS",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 12),

                // Available customers list
                SizedBox(
                  height: 300, // Fixed height for available customers list
                  child:
                      _isLoadingCustomers
                          ? Center(
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                primaryColor,
                              ),
                            ),
                          )
                          : _filteredCustomers.isEmpty
                          ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.search_off,
                                  size: 40,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  "No customers found",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          )
                          : ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: ListView.separated(
                              itemCount: _filteredCustomers.length,
                              separatorBuilder:
                                  (context, index) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final customer = _filteredCustomers[index];
                                final isSelected = _selectedCustomers.any(
                                  (c) => c['id'] == customer['id'],
                                );

                                return Container(
                                  decoration: BoxDecoration(
                                    color:
                                        isSelected
                                            ? primaryColor.withAlpha(
                                              (0.05 * 255).toInt(),
                                            )
                                            : Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color:
                                          isSelected
                                              ? primaryColor.withAlpha(
                                                (0.5 * 255).toInt(),
                                              )
                                              : Colors.grey.shade200,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(
                                          (0.02 * 255).toInt(),
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: primaryColor
                                              .withAlpha((0.1 * 255).toInt()),
                                          backgroundImage:
                                              customer['imageUrl'] != null
                                                  ? NetworkImage(
                                                    customer['imageUrl'],
                                                  )
                                                  : null,
                                          child:
                                              customer['imageUrl'] == null
                                                  ? Text(
                                                    customer['fullName']
                                                        .substring(0, 1)
                                                        .toUpperCase(),
                                                    style: TextStyle(
                                                      color: primaryColor,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                  )
                                                  : null,
                                        ),
                                        const SizedBox(width: 12),
                                        // Customer info
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                customer['fullName'],
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w500,
                                                  fontSize: 13,
                                                  color: Colors.grey.shade800,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 3),
                                              Row(
                                                children: [
                                                  Flexible(
                                                    child: Text(
                                                      "ID: ${customer['customerId']}",
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: Text(
                                                      "NIC: ${customer['nic']}",
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            Colors
                                                                .grey
                                                                .shade600,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        // Add/Added button
                                        ElevatedButton(
                                          onPressed:
                                              isSelected
                                                  ? null
                                                  : () =>
                                                      _addCustomer(customer),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                isSelected
                                                    ? Colors.grey.shade200
                                                    : primaryColor,
                                            foregroundColor:
                                                isSelected
                                                    ? Colors.grey.shade700
                                                    : Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                isSelected
                                                    ? Icons.check
                                                    : Icons.add,
                                                size: 14,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isSelected ? "Added" : "Add",
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                ),

                // Extra space at the bottom to allow scrolling
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageSection() {
    return Card(
      elevation: 6,
      shadowColor: Colors.black.withAlpha((0.1 * 255).toInt()),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          controller: _rightScrollController,
          physics: const ClampingScrollPhysics(),
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
                        color: primaryColor.withAlpha((0.1 * 255).toInt()),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.edit_note_rounded,
                        color: primaryColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        "Compose Your Message",
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // Success message
                if (_isSendSuccess)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.green.withAlpha(26),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Messages Sent Successfully!',
                                      style: TextStyle(
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade200,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      "${_selectedCustomers.length} messages",
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
                                'Your message has been sent to all selected customers.',
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
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                overflow: TextOverflow.visible,
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

                // Form section
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
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor,
                              width: 2,
                            ),
                          ),
                          prefixIcon: Icon(Icons.title, color: primaryColor),
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
                          border: Border.all(color: Colors.grey.shade300),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withAlpha(
                                          (0.1 * 255).toInt(),
                                        ),
                                        borderRadius: BorderRadius.circular(16),
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
                                              fontWeight: FontWeight.w500,
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
                                behavior: ScrollConfiguration.of(
                                  context,
                                ).copyWith(scrollbars: false),
                                child: TextField(
                                  controller: _messageController,
                                  maxLines: null,
                                  expands: true,
                                  decoration: InputDecoration(
                                    hintText: "Type your message here...",
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 15,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            color: Colors.grey.shade700,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            "Attachments",
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade700,
                                            ),
                                          ),
                                          const Spacer(),
                                          TextButton.icon(
                                            onPressed: () {
                                              setState(() {
                                                _selectedFiles.clear();
                                              });
                                            },
                                            icon: Icon(
                                              Icons.delete_outline,
                                              size: 16,
                                              color: Colors.red.shade600,
                                            ),
                                            label: Text(
                                              "Clear",
                                              style: TextStyle(
                                                color: Colors.red.shade600,
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
                                        behavior: ScrollConfiguration.of(
                                          context,
                                        ).copyWith(scrollbars: false),
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _selectedFiles.length,
                                          itemBuilder: (context, index) {
                                            final file = _selectedFiles[index];
                                            return Container(
                                              width: 200,
                                              margin: const EdgeInsets.only(
                                                right: 10,
                                              ),
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color:
                                                          Colors.grey.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: _getFileIcon(
                                                      file.name,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
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
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w500,
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
                                                            fontSize: 11,
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
                                                          Colors.grey.shade600,
                                                    ),
                                                    onPressed: () {
                                                      setState(() {
                                                        _selectedFiles.removeAt(
                                                          index,
                                                        );
                                                      });
                                                    },
                                                    padding: EdgeInsets.zero,
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
                                  top: BorderSide(color: Colors.grey.shade200),
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
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      backgroundColor: primaryColor.withAlpha(
                                        (0.1 * 255).toInt(),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Flexible(
                                    child: Text(
                                      "Supported: JPG, PNG, PDF, DOC, DOCX, XLS, XLSX",
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                        fontStyle: FontStyle.italic,
                                      ),
                                      overflow: TextOverflow.ellipsis,
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
                            _isLoading || _selectedCustomers.isEmpty
                                ? null
                                : _sendMessage,
                        icon:
                            _isLoading
                                ? Container(
                                  width: 20,
                                  height: 20,
                                  padding: const EdgeInsets.all(2),
                                  child: const CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Icon(Icons.send_outlined, size: 20),
                        label: Text(
                          _isLoading
                              ? "Sending..."
                              : "Send to Selected (${_selectedCustomers.length})",
                          style: const TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade300,
                          disabledForegroundColor: Colors.grey.shade600,
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 18),
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
                          side: BorderSide(color: Colors.grey.shade300),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                      ),
                    ),
                  ],
                ),

                // Extra space at the bottom to allow scrolling
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.symmetric(horizontal: 100, vertical: 32),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
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
                    Icons.mark_email_unread_outlined,
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
                        'Message Selected Customers',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Select specific customers to send a targeted message',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                // Help icon
                IconButton(
                  icon: Icon(Icons.help_outline, size: 24, color: primaryColor),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text(
                          'Select customers from the list and compose your message. Add attachments if needed.',
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

            // Main content - Responsive layout
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;

                  if (isWide) {
                    // Horizontal layout for wide screens
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 380, child: _buildCustomerSelector()),
                        const SizedBox(width: 24),
                        Expanded(child: _buildMessageSection()),
                      ],
                    );
                  } else {
                    // Vertical layout for narrow screens
                    return Column(
                      children: [
                        SizedBox(
                          height:
                              constraints.maxHeight *
                              0.45, // 45% of available height
                          child: _buildCustomerSelector(),
                        ),
                        const SizedBox(height: 24),
                        Expanded(child: _buildMessageSection()),
                      ],
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
