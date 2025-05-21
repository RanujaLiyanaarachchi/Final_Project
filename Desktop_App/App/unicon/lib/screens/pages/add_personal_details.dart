import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AddPersonalDetailsPage extends StatefulWidget {
  const AddPersonalDetailsPage({super.key});

  @override
  State<AddPersonalDetailsPage> createState() => _AddPersonalDetailsPageState();
}

class _AddPersonalDetailsPageState extends State<AddPersonalDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _isLoading = false;

  final List<FocusNode> _focusNodes = List.generate(10, (_) => FocusNode());

  final TextEditingController _customerIdController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _nicController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _birthdayController = TextEditingController();
  final TextEditingController _landPhoneController = TextEditingController();
  final TextEditingController _mobileNumberController = TextEditingController();

  String _gender = 'Select';
  final List<String> _genderList = ['Select', 'Male', 'Female', 'Other'];
  String? _genderError;
  String? _imageError;
  String? _nicError;

  File? _selectedImage;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _generateUniqueIDs();

    for (var node in _focusNodes) {
      node.addListener(() {
        if (node.hasFocus && _submitted) {
          setState(() => _submitted = false);
        }
      });
    }

    // Add a listener to check NIC availability when focus changes
    _focusNodes[3].addListener(() {
      if (!_focusNodes[3].hasFocus) {
        _checkNicAvailability();
      }
    });
  }

  Future<void> _checkNicAvailability() async {
    final nic = _nicController.text.trim();
    if (nic.isEmpty) return;

    // Check if NIC format is valid before checking availability
    if ((nic.length == 10 && RegExp(r'^\d{9}[vV]$').hasMatch(nic)) ||
        (nic.length == 12 && RegExp(r'^\d{12}$').hasMatch(nic))) {
      setState(() {});

      try {
        final QuerySnapshot result =
            await _firestore
                .collection('customers')
                .where('nic', isEqualTo: nic)
                .limit(1)
                .get();

        setState(() {
          if (result.docs.isNotEmpty) {
            _nicError = 'This NIC is already registered in the system';
          } else {
            _nicError = null;
          }
        });
      } catch (e) {
        setState(() {
          _nicError = 'Error checking NIC availability';
        });
        debugPrint('Error checking NIC: $e');
      }
    }
  }

  Future<void> _generateUniqueIDs() async {
    setState(() => _isLoading = true);

    bool isUnique = false;
    String customerId = '';
    String accountNumber = '';

    // Keep generating until we find unique IDs
    while (!isUnique) {
      customerId = _generateRandomNumber(5);
      accountNumber = _generateRandomNumber(10);

      // Check if IDs exist in Firestore
      final customerIdExists = await _checkIfIDExists(
        'customers',
        'customerId',
        customerId,
      );
      final accountNumberExists = await _checkIfIDExists(
        'customers',
        'accountNumber',
        accountNumber,
      );

      if (!customerIdExists && !accountNumberExists) {
        isUnique = true;
      }
    }

    setState(() {
      _customerIdController.text = customerId;
      _accountNumberController.text = accountNumber;
      _isLoading = false;
    });
  }

  Future<bool> _checkIfIDExists(
    String collection,
    String field,
    String value,
  ) async {
    final QuerySnapshot result =
        await _firestore
            .collection(collection)
            .where(field, isEqualTo: value)
            .limit(1)
            .get();

    return result.docs.isNotEmpty;
  }

  String _generateRandomNumber(int length) {
    final random = Random();
    return List.generate(length, (_) => random.nextInt(10)).join();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      setState(() {
        _selectedImage = File(result.files.single.path!);
        _imageError = null;
      });
    }
  }

  Future<String?> _uploadImageToFirebase() async {
    if (_selectedImage == null) {
      setState(() {
        _imageError = 'Please select an image';
      });
      return null;
    }

    final customerId = _customerIdController.text;
    final fileName =
        'customer_$customerId.${_selectedImage!.path.split('.').last}';
    final storageRef = _storage.ref().child('customer_images/$fileName');

    try {
      final uploadTask = await storageRef.putFile(_selectedImage!);
      final downloadUrl = await uploadTask.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to upload image: ${e.toString()}',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<void> _submitData() async {
    // Final check of NIC availability before submission
    await _checkNicAvailability();

    setState(() {
      _submitted = true;
      _isLoading = true;
      _genderError = _gender == 'Select' ? 'Please select a gender' : null;
      _imageError = _selectedImage == null ? 'Please select an image' : null;
    });

    if (!_formKey.currentState!.validate() ||
        _gender == 'Select' ||
        _selectedImage == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Upload image and get URL
      final imageUrl = await _uploadImageToFirebase();

      if (imageUrl == null) {
        setState(() => _isLoading = false);
        return; // Error already shown in _uploadImageToFirebase
      }

      // Save customer data to Firestore
      await _firestore
          .collection('customers')
          .doc(_customerIdController.text)
          .set({
            'customerId': _customerIdController.text,
            'accountNumber': _accountNumberController.text,
            'fullName': _fullNameController.text,
            'nic': _nicController.text,
            'address': _addressController.text,
            'email': _emailController.text,
            'birthday': _birthdayController.text,
            'gender': _gender,
            'landPhone': _landPhoneController.text,
            'mobileNumber': _mobileNumberController.text,
            'imageUrl': imageUrl,
            'createdAt': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: Text(
                'Data updated successfully',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Clear form
      _clearForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: Text(
                'Error: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.deepPurple,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    for (final controller in [
      _fullNameController,
      _nicController,
      _addressController,
      _emailController,
      _birthdayController,
      _landPhoneController,
      _mobileNumberController,
    ]) {
      controller.clear();
    }
    setState(() {
      _submitted = false;
      _gender = 'Select';
      _selectedImage = null;
      _genderError = null;
      _imageError = null;
      _nicError = null;
    });

    // Generate new IDs
    _generateUniqueIDs();
  }

  @override
  void dispose() {
    // Dispose all controllers
    _customerIdController.dispose();
    _accountNumberController.dispose();
    _fullNameController.dispose();
    _nicController.dispose();
    _addressController.dispose();
    _emailController.dispose();
    _birthdayController.dispose();
    _landPhoneController.dispose();
    _mobileNumberController.dispose();

    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Add Personal Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 32),
                GestureDetector(
                  onTap: _pickImage,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 250,
                        height: 250,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color:
                                _submitted && _imageError != null
                                    ? Colors.red
                                    : Colors.blueAccent,
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 8,
                              offset: Offset(2, 2),
                            ),
                          ],
                        ),
                        child:
                            _selectedImage != null
                                ? ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.file(
                                    _selectedImage!,
                                    fit: BoxFit.cover,
                                  ),
                                )
                                : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.add_a_photo_rounded,
                                      size: 60,
                                      color: Colors.blue,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Click to upload image',
                                      style: TextStyle(color: Colors.black54),
                                    ),
                                  ],
                                ),
                      ),
                      if (_submitted && _imageError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _imageError!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Right Panel
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 100, 100, 20),
              child: Form(
                key: _formKey,
                autovalidateMode:
                    _submitted
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextField(
                      _customerIdController,
                      _focusNodes[0],
                      'Customer ID',
                      Icons.account_box,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _accountNumberController,
                      _focusNodes[1],
                      'Account Number',
                      Icons.account_balance_wallet,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _fullNameController,
                      _focusNodes[2],
                      'Full Name',
                      Icons.person,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter your full name'
                                  : null,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _nicController,
                      _focusNodes[3],
                      'NIC',
                      Icons.credit_card,
                      maxLength: 12,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your NIC';
                        }
                        final nic = value.trim();
                        if (nic.length < 12) {
                          final pattern = RegExp(r'^\d{9}[vV]$');
                          if (!pattern.hasMatch(nic)) {
                            return 'NIC must be 9 digits + V/v';
                          }
                        } else if (!RegExp(r'^\d{12}$').hasMatch(nic)) {
                          return 'NIC must be 12 digits';
                        }
                        return _nicError;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _addressController,
                      _focusNodes[4],
                      'Address',
                      Icons.home,
                      maxLines: 3,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter your address'
                                  : null,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _emailController,
                      _focusNodes[5],
                      'Email',
                      Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter your email';
                        final pattern = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                        return !pattern.hasMatch(value)
                            ? 'Invalid email'
                            : null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _birthdayController,
                      _focusNodes[6],
                      'Birthday',
                      Icons.calendar_today,
                      keyboardType: TextInputType.datetime,
                      inputFormatters: [BirthdayInputFormatter()],
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter your birthday'
                                  : null,
                    ),
                    const SizedBox(height: 20),
                    _buildDropdownField(
                      'Gender',
                      _gender,
                      _genderList,
                      onChanged:
                          (newValue) => setState(() {
                            _gender = newValue!;
                            if (_gender != 'Select') {
                              _genderError = null;
                            }
                          }),
                      errorText:
                          _submitted && _gender == 'Select'
                              ? _genderError
                              : null,
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _landPhoneController,
                      _focusNodes[7],
                      'Land Phone Number',
                      Icons.phone,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      validator: (value) {
                        if (value!.isEmpty) return 'Enter landline';
                        return !RegExp(r'^0\d{9}$').hasMatch(value)
                            ? 'Invalid landline'
                            : null;
                      },
                    ),
                    const SizedBox(height: 20),
                    _buildTextField(
                      _mobileNumberController,
                      _focusNodes[8],
                      'Mobile Number',
                      Icons.phone_android,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      validator: (value) {
                        if (value!.isEmpty) return 'Enter mobile';
                        return !RegExp(r'^0\d{9}$').hasMatch(value)
                            ? 'Invalid mobile'
                            : null;
                      },
                    ),
                    const SizedBox(height: 30),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          'Submit',
                          Colors.blue,
                          _isLoading ? null : _submitData,
                          isLoading: _isLoading && _submitted,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 130,
                            vertical: 20,
                          ),
                        ),
                        const SizedBox(width: 20),
                        _buildActionButton(
                          'Clear',
                          Colors.red,
                          _isLoading ? null : _clearForm,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 130,
                            vertical: 20,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    FocusNode focusNode,
    String label,
    IconData icon, {
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    bool readOnly = false,
    int maxLines = 1,
    int? maxLength,
    Color textColor = Colors.black,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      readOnly: readOnly,
      style: TextStyle(color: readOnly ? Colors.grey : textColor),
      maxLines: maxLines,
      maxLength: maxLength,
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
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
          horizontal: 15,
        ),
      ),
      onFieldSubmitted: (_) => _focusNext(focusNode),
      onEditingComplete: () => _focusNext(focusNode),
    );
  }

  void _focusNext(FocusNode current) {
    final index = _focusNodes.indexOf(current);
    if (index != -1 && index + 1 < _focusNodes.length) {
      FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
    }
  }

  Widget _buildDropdownField(
    String label,
    String value,
    List<String> items, {
    required ValueChanged<String?> onChanged,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
            prefixIcon: const Icon(Icons.transgender, color: Colors.blue),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: errorText != null ? Colors.red : Colors.blue,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(
                color: errorText != null ? Colors.red : Colors.blue,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: Colors.red),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: DropdownButton<String>(
            value: value,
            onChanged: onChanged,
            isExpanded: true,
            underline: const SizedBox(),
            items:
                items.map((gender) {
                  return DropdownMenuItem(
                    value: gender,
                    child: Text(
                      gender,
                      style: TextStyle(
                        color: gender == 'Select' ? Colors.blue : Colors.black,
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 8),
            child: Text(
              errorText,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton(
    String label,
    Color color,
    VoidCallback? onPressed, {
    bool isLoading = false,
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
          minimumSize: WidgetStateProperty.all(
            const Size(300, 60),
          ), // Fixed size for consistency
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
              return const Color(0x1F000000); // Approx. 12% black
            }
            if (states.contains(WidgetState.hovered)) {
              return color.withAlpha((0.1 * 255).toInt());
            }
            return null;
          }),
        ),
        child:
            isLoading
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

class BirthdayInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final buffer = StringBuffer();

    for (int i = 0; i < digitsOnly.length && i < 8; i++) {
      buffer.write(digitsOnly[i]);
      if (i == 3 || i == 5) buffer.write('-');
    }

    return TextEditingValue(
      text: buffer.toString(),
      selection: TextSelection.collapsed(offset: buffer.length),
    );
  }
}
