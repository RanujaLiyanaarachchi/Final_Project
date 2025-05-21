import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';

class ViewPersonalDetailsPage extends StatefulWidget {
  const ViewPersonalDetailsPage({super.key});

  @override
  State<ViewPersonalDetailsPage> createState() =>
      _ViewPersonalDetailsPageState();
}

class _ViewPersonalDetailsPageState extends State<ViewPersonalDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final TextEditingController _searchController = TextEditingController();

  // Customer data
  Map<String, dynamic>? _customerData;
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;

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
              });
              return;
            }
          }
        }
      }

      setState(() {
        _customerData = snapshot.data();
        if (_customerData != null) {
          _customerData!['customerId'] = snapshot.id;
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for customer: ${e.toString()}';
        _isLoading = false;
      });
      debugPrint('Error searching for customer: $e');
    }
  }

  Future<void> _removeCustomer() async {
    if (_customerData == null) return;

    setState(() => _isLoading = true);

    try {
      // First check if customer has active finance records
      final String customerId = _customerData!['customerId'];

      // Query the finances collection for this customer
      final financeQuery =
          await _firestore
              .collection('finances')
              .where('customerId', isEqualTo: customerId)
              .get();

      // If we found finance records, check if any are active
      if (financeQuery.docs.isNotEmpty) {
        bool hasActiveFinance = false;

        // Check each finance record
        for (var financeDoc in financeQuery.docs) {
          final financeData = financeDoc.data();
          final accountNumber = financeData['accountNumber'];

          // Check installments to see if there are remaining payments
          final installmentDoc =
              await _firestore
                  .collection('installments')
                  .doc(accountNumber)
                  .get();

          if (installmentDoc.exists) {
            final installmentData = installmentDoc.data();
            final remainingInstallments =
                installmentData?['remainingInstallments'] ?? 0;
            final balance = installmentData?['balance'] ?? 0.0;

            // If there are remaining installments or balance is not 0, this is an active finance
            if (remainingInstallments > 0 || balance > 0) {
              hasActiveFinance = true;
              break;
            }
          }
        }

        // If customer has active finance, show error and don't allow removal
        if (hasActiveFinance) {
          setState(() => _isLoading = false);

          // Show error message
          if (mounted) {
            await showDialog(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text(
                      'Cannot Remove Customer',
                      style: TextStyle(color: Colors.red),
                    ),
                    content: const Text(
                      'This customer cannot be removed because they have an active loan. Please ensure all loans are fully paid before removing the customer.',
                      style: TextStyle(fontSize: 16),
                    ),
                    actions: [
                      TextButton(
                        child: const Text(
                          'OK',
                          style: TextStyle(color: Colors.blue),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                  ),
            );
          }
          return;
        }
      }

      // If no active finance or check passed, show confirmation dialog
      bool? confirm;
      if (mounted) {
        confirm = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Confirm Removal'),
                content: Text(
                  'Are you sure you want to remove ${_customerData!['fullName']}?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                elevation: 5,
              ),
        );
      }

      if (confirm != true) {
        setState(() => _isLoading = false);
        return;
      }

      // Delete image from Firebase Storage if it exists
      if (_customerData!.containsKey('imageUrl') &&
          _customerData!['imageUrl'] != null &&
          _customerData!['imageUrl'].isNotEmpty) {
        try {
          // Extract the image reference from the URL
          final imageRef = _storage.refFromURL(_customerData!['imageUrl']);
          await imageRef.delete();
          debugPrint('Customer image deleted successfully');
        } catch (imageError) {
          debugPrint('Error deleting customer image: $imageError');
          // Continue with customer deletion even if image deletion fails
        }
      }

      // Delete customer document from Firestore
      await _firestore
          .collection('customers')
          .doc(_customerData!['customerId'])
          .delete();

      setState(() {
        _customerData = null;
        _searchController.clear();
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: const Text(
                'Customer removed successfully',
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
                'Error removing customer: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error removing customer: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel - Similar to AddPersonalDetailsPage
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'View Personal Details',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
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
                  child:
                      _customerData != null &&
                              _customerData!.containsKey('imageUrl')
                          ? ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.network(
                              _customerData!['imageUrl'],
                              fit: BoxFit.cover,
                              loadingBuilder: (
                                context,
                                child,
                                loadingProgress,
                              ) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value:
                                        loadingProgress.expectedTotalBytes !=
                                                null
                                            ? loadingProgress
                                                    .cumulativeBytesLoaded /
                                                loadingProgress
                                                    .expectedTotalBytes!
                                            : null,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(
                                      Icons.error_outline,
                                      size: 60,
                                      color: Colors.red,
                                    ),
                                    SizedBox(height: 10),
                                    Text(
                                      'Failed to load image',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                );
                              },
                            ),
                          )
                          : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.person, size: 60, color: Colors.blue),
                              SizedBox(height: 10),
                              Text(
                                'No customer selected',
                                style: TextStyle(color: Colors.black54),
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
                    _buildCustomerDetails()
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
                    });
                  },
                )
                : null,
      ),
    );
  }

  Widget _buildCustomerDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReadOnlyField(
          'Customer ID',
          _customerData!['customerId'] ?? 'N/A',
          Icons.account_box,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Account Number',
          _customerData!['accountNumber'] ?? 'N/A',
          Icons.account_balance_wallet,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Full Name',
          _customerData!['fullName'] ?? 'N/A',
          Icons.person,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'NIC',
          _customerData!['nic'] ?? 'N/A',
          Icons.credit_card,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Address',
          _customerData!['address'] ?? 'N/A',
          Icons.home,
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Email',
          _customerData!['email'] ?? 'N/A',
          Icons.email,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Birthday',
          _customerData!['birthday'] ?? 'N/A',
          Icons.calendar_today,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Gender',
          _customerData!['gender'] ?? 'N/A',
          Icons.transgender,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Land Phone Number',
          _customerData!['landPhone'] ?? 'N/A',
          Icons.phone,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Mobile Number',
          _customerData!['mobileNumber'] ?? 'N/A',
          Icons.phone_android,
        ),
        const SizedBox(height: 30),

        // Remove Button
        Center(
          child: _buildActionButton(
            'Remove Customer',
            Colors.red,
            _isLoading ? null : _removeCustomer,
            padding: const EdgeInsets.symmetric(horizontal: 299, vertical: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildReadOnlyField(
    String label,
    String value,
    IconData icon, {
    int maxLines = 1,
  }) {
    return TextFormField(
      initialValue: value,
      readOnly: true,
      style: const TextStyle(color: Colors.black),
      maxLines: maxLines,
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.blue),
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: const EdgeInsets.symmetric(
          vertical: 10,
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
