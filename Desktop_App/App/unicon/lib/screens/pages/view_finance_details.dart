import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class ViewFinanceDetailsPage extends StatefulWidget {
  const ViewFinanceDetailsPage({super.key});

  @override
  State<ViewFinanceDetailsPage> createState() => _ViewFinanceDetailsPageState();
}

class _ViewFinanceDetailsPageState extends State<ViewFinanceDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  // Finance and Customer data
  Map<String, dynamic>? _financeData;
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
        _searchFinanceDetails(_searchController.text.toUpperCase());
      } else {
        setState(() {
          _financeData = null;
          _customerData = null;
          _searchError = '';
        });
      }
    });
  }

  Future<void> _searchFinanceDetails(String searchQuery) async {
    setState(() {
      _isLoading = true;
      _searchError = '';
    });

    try {
      // Try to find finance details by multiple criteria
      QuerySnapshot? financeSnapshot;

      // First try to find by account number
      financeSnapshot =
          await _firestore
              .collection('finances')
              .where('accountNumber', isEqualTo: searchQuery)
              .limit(1)
              .get();

      // If not found, try vehicle number
      if (financeSnapshot.docs.isEmpty) {
        financeSnapshot =
            await _firestore
                .collection('finances')
                .where('vehicleNumber', isEqualTo: searchQuery)
                .limit(1)
                .get();
      }

      // If still not found, try to find by customer ID and then get finance details
      if (financeSnapshot.docs.isEmpty) {
        // Try finding customer by customer ID
        var customerDoc =
            await _firestore.collection('customers').doc(searchQuery).get();

        if (customerDoc.exists) {
          // If customer found, search for their finance details
          financeSnapshot =
              await _firestore
                  .collection('finances')
                  .where('customerId', isEqualTo: searchQuery)
                  .limit(1)
                  .get();
        } else {
          // Try finding customer by NIC
          final customerNicResults =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: searchQuery)
                  .limit(1)
                  .get();

          if (customerNicResults.docs.isNotEmpty) {
            final customerId =
                customerNicResults.docs.first.data()['customerId'];

            // Use the customerId to search for finance details
            financeSnapshot =
                await _firestore
                    .collection('finances')
                    .where('customerId', isEqualTo: customerId)
                    .limit(1)
                    .get();

            // Store customer data
            _customerData = customerNicResults.docs.first.data();
          }
        }
      }

      // If we found finance details, fetch the associated customer details if not already fetched
      if (financeSnapshot.docs.isNotEmpty) {
        final financeData =
            financeSnapshot.docs.first.data() as Map<String, dynamic>;
        // Ensure we have the document ID
        financeData['financeId'] = financeSnapshot.docs.first.id;
        _financeData = financeData;

        // If customer data not already fetched, get it using the customerId
        if (_customerData == null) {
          final customerDoc =
              await _firestore
                  .collection('customers')
                  .doc(financeData['customerId'])
                  .get();

          if (customerDoc.exists) {
            _customerData = customerDoc.data();
          }
        }

        // Calculate monthly installment and total amount due if not already in database
        if (!financeData.containsKey('monthlyInstallment') ||
            !financeData.containsKey('totalAmountDue')) {
          double loanAmount = (financeData['loanAmount'] ?? 0).toDouble();
          double interestRate = (financeData['interestRate'] ?? 0).toDouble();
          int timePeriod = (financeData['timePeriod'] ?? 0) as int;

          double monthlyInstallment = _calculateMonthlyInstallment(
            loanAmount,
            interestRate,
            timePeriod,
          );

          double totalAmountDue = monthlyInstallment * timePeriod * 12;

          // Add calculated values to finance data
          _financeData!['monthlyInstallment'] = monthlyInstallment;
          _financeData!['totalAmountDue'] = totalAmountDue;

          // Update the database with calculated values
          await _firestore
              .collection('finances')
              .doc(financeData['financeId'])
              .update({
                'monthlyInstallment': monthlyInstallment,
                'totalAmountDue': totalAmountDue,
              });
        }

        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _financeData = null;
          _customerData = null;
          _searchError =
              'No finance details found with the given search criteria';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for finance details: ${e.toString()}';
        _isLoading = false;
      });
      debugPrint('Error searching for finance details: $e');
    }
  }

  // Calculate monthly installment using simple interest formula
  double _calculateMonthlyInstallment(
    double loanAmount,
    double interestRate,
    int timePeriodYears,
  ) {
    // Simple interest calculation
    double totalInterest = loanAmount * interestRate * timePeriodYears / 100;
    double totalAmount = loanAmount + totalInterest;

    // Divide by total months
    return totalAmount / (timePeriodYears * 12);
  }

  Future<void> _removeFinanceDetails() async {
    if (_financeData == null) return;

    setState(() => _isLoading = true);

    try {
      // Check if the finance is active by looking for active installments
      final accountNumber = _financeData!['accountNumber'];
      final installmentDoc =
          await _firestore.collection('installments').doc(accountNumber).get();

      if (installmentDoc.exists) {
        // Get installment data
        final installmentData = installmentDoc.data();
        final remainingInstallments =
            installmentData?['remainingInstallments'] ?? 0;
        final balance = installmentData?['balance'] ?? 0.0;

        // If there are remaining installments or balance is not 0, show error
        if (remainingInstallments > 0 || balance > 0) {
          setState(() => _isLoading = false);

          // Show error message
          if (mounted) {
            await showDialog(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text(
                      'Cannot Remove Active Finance',
                      style: TextStyle(color: Colors.red),
                    ),
                    content: const Text(
                      'This finance record cannot be removed because it has an active loan. Only loan records that are fully paid can be removed.',
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

      // Show confirmation dialog
      bool? confirm;
      if (mounted) {
        confirm = await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text('Confirm Removal'),
                content: Text(
                  'Are you sure you want to remove finance details for vehicle ${_financeData!['vehicleNumber']}?',
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

      // Delete finance document from Firestore
      String financeId = _financeData!['financeId'];
      await _firestore.collection('finances').doc(financeId).delete();

      setState(() {
        _financeData = null;
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
                'Finance details removed successfully',
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
                'Error removing finance details: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error removing finance details: $e');
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
                  'View Finance Details',
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
                              _customerData!.containsKey('imageUrl') &&
                              _customerData!['imageUrl'] != null &&
                              _customerData!['imageUrl'].isNotEmpty
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
                              Icon(
                                Icons.directions_car,
                                size: 60,
                                color: Colors.blue,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'No finance details selected',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ],
                          ),
                ),
                if (_customerData != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: Text(
                      'Customer: ${_customerData!['fullName']}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                      textAlign: TextAlign.center,
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
                  else if (_financeData != null)
                    _buildFinanceDetails()
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 100),
                        child: Text(
                          'Search for finance details by Account Number, Vehicle Number, Customer ID, or NIC',
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
      onChanged: (value) {
        // Auto-capitalize input
        if (value != value.toUpperCase()) {
          _searchController.value = TextEditingValue(
            text: value.toUpperCase(),
            selection: TextSelection.collapsed(offset: value.length),
          );
        }
      },
      decoration: InputDecoration(
        labelText: 'Search Finance Details',
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        hintText: 'Enter Account Number, Vehicle Number, Customer ID, or NIC',
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
                      _financeData = null;
                      _customerData = null;
                      _searchError = '';
                    });
                  },
                )
                : null,
      ),
    );
  }

  Widget _buildFinanceDetails() {
    // Format loan amount with commas
    String formattedLoanAmount =
        'Rs. ${_formatNumber(_financeData!['loanAmount'].toString())}';

    // Format monthly installment with commas
    String formattedMonthlyInstallment =
        'Rs. ${_formatNumber(_financeData!['monthlyInstallment'].toString())}';

    // Format total amount with commas
    String formattedTotalAmount =
        'Rs. ${_formatNumber(_financeData!['totalAmountDue'].toString())}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildReadOnlyField(
          'Account Number',
          _financeData!['accountNumber'] ?? 'N/A',
          Icons.account_balance_wallet,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Vehicle Number',
          _financeData!['vehicleNumber'] ?? 'N/A',
          Icons.directions_car,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Loan Amount',
          formattedLoanAmount,
          Icons.attach_money,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Opening Date',
          _financeData!['openingDate'] ?? 'N/A',
          Icons.calendar_today,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Time Period (Years)',
          _financeData!['timePeriod'].toString(),
          Icons.access_time,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Interest Rate (%)',
          _financeData!['interestRate'].toString(),
          Icons.percent,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Maturity Date',
          _financeData!['maturityDate'] ?? 'N/A',
          Icons.date_range,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Monthly Installment',
          formattedMonthlyInstallment,
          Icons.payment,
        ),
        const SizedBox(height: 20),
        _buildReadOnlyField(
          'Total Amount Due',
          formattedTotalAmount,
          Icons.account_balance,
        ),
        const SizedBox(height: 30),

        // Remove Button
        Center(
          child: _buildActionButton(
            'Remove Finance Details',
            Colors.red,
            _isLoading ? null : _removeFinanceDetails,
            padding: const EdgeInsets.symmetric(horizontal: 278, vertical: 20),
          ),
        ),
      ],
    );
  }

  // Helper method to format numbers with commas
  String _formatNumber(String number) {
    if (number.isEmpty) return '0';

    // Remove any existing commas and decimal part
    String cleanNumber = number.replaceAll(',', '');

    // Split by decimal point if exists
    List<String> parts = cleanNumber.split('.');
    String integerPart = parts[0];

    // Format integer part with commas
    final result = StringBuffer();
    for (int i = 0; i < integerPart.length; i++) {
      if (i > 0 && (integerPart.length - i) % 3 == 0) {
        result.write(',');
      }
      result.write(integerPart[i]);
    }

    // Add decimal part back if it exists
    if (parts.length > 1) {
      result.write('.');
      result.write(parts[1]);
    }

    return result.toString();
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
