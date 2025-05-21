import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;

class EditPersonalDetailsPage extends StatefulWidget {
  const EditPersonalDetailsPage({super.key});

  @override
  State<EditPersonalDetailsPage> createState() =>
      _EditPersonalDetailsPageState();
}

class _EditPersonalDetailsPageState extends State<EditPersonalDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final TextEditingController _searchController = TextEditingController();

  // Form controllers
  final TextEditingController _customerIdController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _nicController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  final TextEditingController _genderController = TextEditingController();
  final TextEditingController _landPhoneController = TextEditingController();
  final TextEditingController _mobileNumberController = TextEditingController();

  // For image handling
  String? _imageUrl;
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();
  bool _imageChanged = false;

  // Customer data
  Map<String, dynamic>? _customerData;
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Add listener to search field
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _customerIdController.dispose();
    _accountNumberController.dispose();
    _fullNameController.dispose();
    _nicController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _birthdayController.dispose();
    _genderController.dispose();
    _landPhoneController.dispose();
    _mobileNumberController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Only search if there's text
      if (_searchController.text.isNotEmpty) {
        _searchCustomer(_searchController.text);
      } else {
        setState(() {
          _customerData = null;
          _searchError = '';
          _clearFormFields();
        });
      }
    });
  }

  Future<void> _searchCustomer(String searchQuery) async {
    setState(() {
      _isLoading = true;
      _searchError = '';
    });

    try {
      // First try to search by Customer ID
      var snapshot =
          await _firestore.collection('customers').doc(searchQuery).get();

      // If not found by Customer ID, try other fields
      if (!snapshot.exists) {
        // Try to search by NIC
        final nicResults =
            await _firestore
                .collection('customers')
                .where('nic', isEqualTo: searchQuery)
                .limit(1)
                .get();

        if (nicResults.docs.isNotEmpty) {
          snapshot = nicResults.docs.first;
        } else {
          // Try to search by Account Number
          final accountResults =
              await _firestore
                  .collection('customers')
                  .where('accountNumber', isEqualTo: searchQuery)
                  .limit(1)
                  .get();

          if (accountResults.docs.isNotEmpty) {
            snapshot = accountResults.docs.first;
          } else {
            // Try to search by Full Name (case sensitive)
            final nameResults =
                await _firestore
                    .collection('customers')
                    .where('fullName', isEqualTo: searchQuery)
                    .limit(1)
                    .get();

            if (nameResults.docs.isNotEmpty) {
              snapshot = nameResults.docs.first;
            } else {
              setState(() {
                _customerData = null;
                _searchError =
                    'No customer found with the given search criteria';
                _isLoading = false;
                _clearFormFields();
              });
              return;
            }
          }
        }
      }

      _customerData = snapshot.data();
      _populateFormFields();
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for customer: ${e.toString()}';
        _isLoading = false;
        _clearFormFields();
      });
      debugPrint('Error searching for customer: $e');
    }
  }

  void _populateFormFields() {
    if (_customerData != null) {
      _customerIdController.text = _customerData!['customerId'] ?? '';
      _accountNumberController.text = _customerData!['accountNumber'] ?? '';
      _fullNameController.text = _customerData!['fullName'] ?? '';
      _nicController.text = _customerData!['nic'] ?? '';
      _addressController.text = _customerData!['address'] ?? '';
      _emailController.text = _customerData!['email'] ?? '';
      _birthdayController.text = _customerData!['birthday'] ?? '';
      _genderController.text = _customerData!['gender'] ?? '';
      _landPhoneController.text = _customerData!['landPhone'] ?? '';
      _mobileNumberController.text = _customerData!['mobileNumber'] ?? '';
      _imageUrl = _customerData!['imageUrl'];
      _imageFile = null;
      _imageChanged = false;
    }
  }

  void _clearFormFields() {
    _customerIdController.clear();
    _accountNumberController.clear();
    _fullNameController.clear();
    _nicController.clear();
    _addressController.clear();
    _emailController.clear();
    _birthdayController.clear();
    _genderController.clear();
    _landPhoneController.clear();
    _mobileNumberController.clear();
    _imageUrl = null;
    _imageFile = null;
    _imageChanged = false;
  }

  Future<void> _pickImage() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
          _imageChanged = true;
        });
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<String?> _uploadImage(String customerId) async {
    if (_imageFile == null) return _imageUrl;

    try {
      final String fileName =
          '${customerId}_${path.basename(_imageFile!.path)}';
      final Reference storageRef = _storage.ref().child(
        'customer_images/$fileName',
      );

      final UploadTask uploadTask = storageRef.putFile(_imageFile!);
      final TaskSnapshot taskSnapshot = await uploadTask;

      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return null;
    }
  }

  Future<void> _updateCustomer() async {
    if (_customerData == null || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Upload new image if changed
      String? imageUrl = _imageUrl;
      if (_imageChanged && _imageFile != null) {
        imageUrl = await _uploadImage(_customerIdController.text);

        // Delete old image if a new one was uploaded successfully
        if (imageUrl != null && _imageUrl != null && _imageUrl!.isNotEmpty) {
          try {
            final Reference oldImageRef = _storage.refFromURL(_imageUrl!);
            await oldImageRef.delete();
          } catch (e) {
            debugPrint('Error deleting old image: $e');
            // Continue with update even if old image deletion fails
          }
        }
      }

      // Update customer document in Firestore
      final Map<String, dynamic> updatedData = {
        'customerId': _customerIdController.text,
        'accountNumber':
            _accountNumberController.text, // Keep the original account number
        'fullName': _fullNameController.text,
        'nic': _nicController.text,
        'address': _addressController.text,
        'email': _emailController.text,
        'birthday': _birthdayController.text,
        'gender': _genderController.text,
        'landPhone': _landPhoneController.text,
        'mobileNumber': _mobileNumberController.text,
      };

      // Only add imageUrl if it's not null
      if (imageUrl != null) {
        updatedData['imageUrl'] = imageUrl;
      }

      await _firestore
          .collection('customers')
          .doc(_customerIdController.text)
          .update(updatedData);

      setState(() {
        _isLoading = false;
        _imageChanged = false;
        // Update local customer data
        _customerData = updatedData;
        _imageUrl = imageUrl;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: const Text(
                'Customer updated successfully',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: Text(
                'Error updating customer: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error updating customer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel with Image
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Edit Personal Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 32),
                InkWell(
                  onTap: _customerData != null ? _pickImage : null,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blueAccent, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 8,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                    child: _buildImageWidget(),
                  ),
                ),
                if (_customerData != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: const Text('Change Image'),
                      style: TextButton.styleFrom(foregroundColor: Colors.blue),
                    ),
                  ),
              ],
            ),
          ),

          // Right Panel with Details Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 100, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Search Field
                  _buildSearchField(),

                  if (_searchError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _searchError,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),

                  const SizedBox(height: 30),

                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_customerData != null)
                    _buildCustomerForm()
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 100),
                        child: Text(
                          'Search for a customer by ID, NIC, Account Number, or Full Name',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageWidget() {
    if (_imageFile != null) {
      // Display locally picked image
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(_imageFile!, fit: BoxFit.cover),
      );
    } else if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      // Display image from URL
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(
          _imageUrl!,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Center(
              child: CircularProgressIndicator(
                value:
                    loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded /
                            loadingProgress.expectedTotalBytes!
                        : null,
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.error_outline, size: 60, color: Colors.red),
                SizedBox(height: 10),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            );
          },
        ),
      );
    } else {
      // Display placeholder
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.person, size: 60, color: Colors.blue),
          SizedBox(height: 10),
          Text('No customer selected', style: TextStyle(color: Colors.black54)),
        ],
      );
    }
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Search Customer...',
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        hintText: 'Enter Customer ID, NIC, Account Number, or Full Name',
        prefixIcon: const Icon(Icons.search, color: Colors.blue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 15,
        ),
        suffixIcon:
            _searchController.text.isNotEmpty
                ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _customerData = null;
                      _searchError = '';
                      _clearFormFields();
                    });
                  },
                )
                : null,
      ),
    );
  }

  Widget _buildCustomerForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer ID (read-only)
          _buildEditableField(
            label: 'Customer ID',
            controller: _customerIdController,
            icon: Icons.account_box,
            readOnly: true, // Customer ID should not be editable
          ),
          const SizedBox(height: 20),

          // Account Number (read-only)
          _buildEditableField(
            label: 'Account Number',
            controller: _accountNumberController,
            icon: Icons.account_balance_wallet,
            readOnly: true, // Account number should not be editable
          ),
          const SizedBox(height: 20),

          // Full Name
          _buildEditableField(
            label: 'Full Name',
            controller: _fullNameController,
            icon: Icons.person,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter full name';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // NIC
          _buildEditableField(
            label: 'NIC',
            controller: _nicController,
            icon: Icons.credit_card,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter NIC';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Address
          _buildEditableField(
            label: 'Address',
            controller: _addressController,
            icon: Icons.home,
            maxLines: 3,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter address';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Email
          _buildEditableField(
            label: 'Email',
            controller: _emailController,
            icon: Icons.email,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return null; // Email can be optional
              }
              // Simple email validation
              if (!value.contains('@') || !value.contains('.')) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Birthday
          _buildEditableField(
            label: 'Birthday',
            controller: _birthdayController,
            icon: Icons.calendar_today,
          ),
          const SizedBox(height: 20),

          // Gender
          _buildEditableField(
            label: 'Gender',
            controller: _genderController,
            icon: Icons.transgender,
          ),
          const SizedBox(height: 20),

          // Land Phone Number
          _buildEditableField(
            label: 'Land Phone Number',
            controller: _landPhoneController,
            icon: Icons.phone,
          ),
          const SizedBox(height: 20),

          // Mobile Number
          _buildEditableField(
            label: 'Mobile Number',
            controller: _mobileNumberController,
            icon: Icons.phone_android,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter mobile number';
              }
              return null;
            },
          ),
          const SizedBox(height: 30),

          // Update Button
          Center(
            child: _buildActionButton(
              'Update Customer',
              Colors.blue,
              _isLoading ? null : _updateCustomer,
              padding: const EdgeInsets.symmetric(
                horizontal: 300,
                vertical: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    int maxLines = 1,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      validator: validator,
      style: TextStyle(color: readOnly ? Colors.grey : Colors.black),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        filled: readOnly,
        fillColor: readOnly ? Colors.grey[100] : null,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 15,
          horizontal: 15,
        ),
      ),
    );
  }

  Widget _buildActionButton(
    String label,
    Color color,
    VoidCallback? onPressed, {
    required EdgeInsetsGeometry padding,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.all(color),
          foregroundColor: WidgetStateProperty.all(Colors.white),
          elevation: WidgetStateProperty.all(4),
          padding: WidgetStateProperty.all(padding),
          minimumSize: WidgetStateProperty.all(const Size(300, 60)),
          textStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          shadowColor: WidgetStateProperty.all(
            color.withAlpha((0.4 * 255).toInt()),
          ),
          overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
            if (states.contains(WidgetState.pressed)) {
              return const Color(0x1F000000);
            }
            if (states.contains(WidgetState.hovered)) {
              return color.withAlpha((0.1 * 255).toInt());
            }
            return null;
          }),
        ),
        child:
            _isLoading
                ? _buildProgressButton(label)
                : AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  child: Text(label),
                ),
      ),
    );
  }

  Widget _buildProgressButton(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Text('Processing...'),
      ],
    );
  }
}
