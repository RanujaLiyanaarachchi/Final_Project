import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class BillHistoryPage extends StatefulWidget {
  const BillHistoryPage({super.key});

  @override
  State<BillHistoryPage> createState() => _BillHistoryPageState();
}

class _BillHistoryPageState extends State<BillHistoryPage> {
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;

  // Finance data
  Map<String, dynamic>? _financeData;
  Map<String, dynamic>? _customerData;
  Map<String, dynamic>? _installmentData;

  final TextEditingController _searchController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Main color
  final Color primaryColor = Colors.blue;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      // Only search if there's text
      if (_searchController.text.isNotEmpty) {
        _searchCustomer(_searchController.text);
      } else {
        setState(() {
          _customerData = null;
          _financeData = null;
          _installmentData = null;
          _searchError = '';
        });
      }
    });
  }

  // Check if loan is fully paid
  bool _isLoanFullyPaid() {
    if (_installmentData == null) return false;
    return _installmentData!['balance'] <= 0 ||
        _installmentData!['remainingInstallments'] <= 0;
  }

  Future<void> _searchCustomer(String searchQuery) async {
    setState(() {
      _isLoading = true;
      _searchError = '';
    });

    try {
      debugPrint('Search query: $searchQuery');

      // First try to search by Account Number in finances collection
      var financeQuery =
          await _firestore
              .collection('finances')
              .where('accountNumber', isEqualTo: searchQuery)
              .limit(1)
              .get();

      debugPrint(
        'Finance by account number docs length: ${financeQuery.docs.length}',
      );

      // If not found by Account Number, try to search by Customer ID
      if (financeQuery.docs.isEmpty) {
        // Try Customer ID in finances collection
        financeQuery =
            await _firestore
                .collection('finances')
                .where('customerId', isEqualTo: searchQuery)
                .limit(1)
                .get();

        debugPrint(
          'Finance by customer ID docs length: ${financeQuery.docs.length}',
        );

        // Try Customer ID directly in customers collection
        var customerQuery =
            await _firestore.collection('customers').doc(searchQuery).get();

        if (customerQuery.exists) {
          // Customer found by ID, now get their finance records
          String customerId = customerQuery.id;
          financeQuery =
              await _firestore
                  .collection('finances')
                  .where('customerId', isEqualTo: customerId)
                  .limit(1)
                  .get();

          debugPrint(
            'Finance by customer lookup docs length: ${financeQuery.docs.length}',
          );
        }
      }

      // If still not found, try to search by Vehicle Number
      if (financeQuery.docs.isEmpty) {
        financeQuery =
            await _firestore
                .collection('finances')
                .where('vehicleNumber', isEqualTo: searchQuery.toUpperCase())
                .limit(1)
                .get();

        debugPrint(
          'Finance by vehicle number docs length: ${financeQuery.docs.length}',
        );
      }

      // If still not found, try to search by NIC in customers collection
      if (financeQuery.docs.isEmpty) {
        var customerQuery =
            await _firestore
                .collection('customers')
                .where('nic', isEqualTo: searchQuery)
                .limit(1)
                .get();

        if (customerQuery.docs.isNotEmpty) {
          // If found by NIC, get the finance data using customer ID
          String customerId = customerQuery.docs.first.id;
          financeQuery =
              await _firestore
                  .collection('finances')
                  .where('customerId', isEqualTo: customerId)
                  .limit(1)
                  .get();

          debugPrint(
            'Finance by NIC lookup docs length: ${financeQuery.docs.length}',
          );
        }
      }

      // If still not found, try to search by customer name
      if (financeQuery.docs.isEmpty) {
        // Use a more flexible search for names (contains)
        var customerQuery =
            await _firestore
                .collection('customers')
                .where('fullName', isGreaterThanOrEqualTo: searchQuery)
                .where('fullName', isLessThanOrEqualTo: '$searchQuery\uf8ff')
                .limit(5)
                .get();

        if (customerQuery.docs.isNotEmpty) {
          // If found by name, get the finance data using customer ID
          String customerId = customerQuery.docs.first.id;
          financeQuery =
              await _firestore
                  .collection('finances')
                  .where('customerId', isEqualTo: customerId)
                  .limit(1)
                  .get();

          debugPrint(
            'Finance by name lookup docs length: ${financeQuery.docs.length}',
          );
        }
      }

      // Handle search results
      if (financeQuery.docs.isNotEmpty) {
        // Get finance data
        final financeData = financeQuery.docs.first.data();
        final accountNumber = financeData['accountNumber'];

        debugPrint('Found finance data, account number: $accountNumber');

        // Get customer data
        final customerId = financeData['customerId'];
        final customerDoc =
            await _firestore.collection('customers').doc(customerId).get();

        if (!customerDoc.exists) {
          setState(() {
            _searchError = 'Customer data not found for this finance record';
            _customerData = null;
            _financeData = null;
            _installmentData = null;
          });
          return;
        }

        // Get installment data
        final installmentDoc =
            await _firestore
                .collection('installments')
                .doc(accountNumber)
                .get();

        if (installmentDoc.exists) {
          setState(() {
            _financeData = financeData;
            _customerData = customerDoc.data();
            _customerData!['customerId'] =
                customerId; // Add document ID as customerId
            _installmentData = installmentDoc.data();
            _searchError = '';
          });

          debugPrint('Successfully loaded all data');
        } else {
          setState(() {
            _searchError = 'Installment data not found for this account';
            _customerData = null;
            _financeData = null;
            _installmentData = null;
          });
        }
      } else {
        setState(() {
          _customerData = null;
          _financeData = null;
          _installmentData = null;
          _searchError = 'No customer found with the given search criteria';
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for customer: ${e.toString()}';
      });
      debugPrint('Error searching for customer: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Calculate ONLY CURRENT due amounts (not future payments)
  double _calculateCurrentDue() {
    if (_installmentData == null) return 0;

    double totalDue = 0;
    List<dynamic> arrears = _installmentData!['arrears'];
    DateTime now = DateTime.now();
    String today = DateFormat('yyyy-MM-dd').format(now);

    for (var arrear in arrears) {
      // Only include if status is due or overdue AND billing date is today or earlier
      if ((arrear['status'] == 'due' || arrear['status'] == 'overdue') &&
          arrear['billingDate'].compareTo(today) <= 0) {
        totalDue += arrear['amountPayable'];
      }
    }

    return totalDue;
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

  // Calculate total amount (loan + interest)
  double _calculateTotalAmount() {
    if (_financeData == null) return 0;

    double loanAmount = _financeData!['loanAmount'] ?? 0;
    double interestRate = _financeData!['interestRate'] ?? 0;
    int timePeriod = _financeData!['timePeriod'] ?? 0;

    // Calculate interest amount
    double interestAmount = (loanAmount * interestRate * timePeriod) / 100;

    // Return total amount
    return loanAmount + interestAmount;
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel - Customer details
          // Updated left panel section with SingleChildScrollView

          // Left Panel - Customer details
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: SingleChildScrollView(
              // Added SingleChildScrollView to fix overflow
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Bill History',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Customer image
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
                                Icon(
                                  Icons.account_circle,
                                  size: 60,
                                  color: Colors.blue,
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'No customer selected',
                                  style: TextStyle(color: Colors.black54),
                                ),
                              ],
                            ),
                  ),

                  // Customer information
                  if (_customerData != null) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                      decoration: BoxDecoration(
                        color: primaryColor.withAlpha((0.05 * 255).toInt()),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: primaryColor.withAlpha((0.3 * 255).toInt()),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          // Row containing customer name and loan fully paid badge
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _customerData!['fullName'] ?? 'Customer Name',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor,
                                  ),
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_installmentData != null &&
                                  _isLoanFullyPaid())
                                Container(
                                  margin: const EdgeInsets.only(left: 10),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.green.shade400,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green.shade800,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Fully Paid',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Divider(
                            color: primaryColor.withAlpha((0.2 * 255).toInt()),
                          ),
                          const SizedBox(height: 8),
                          _buildCustomerInfoItem(
                            'Account',
                            _financeData!['accountNumber'] ?? 'N/A',
                            Icons.account_balance,
                          ),
                          const SizedBox(height: 8),
                          _buildCustomerInfoItem(
                            'NIC',
                            _customerData!['nic'] ?? 'N/A',
                            Icons.badge,
                          ),
                          const SizedBox(height: 8),
                          _buildCustomerInfoItem(
                            'Phone',
                            _getPhoneNumber(),
                            Icons.phone,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(
                      height: 20,
                    ), // Added padding at bottom to improve spacing
                  ],
                ],
              ),
            ),
          ),

          // Right Panel - Search and Finance Status
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 150, 100, 20),
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

                  const SizedBox(height: 20),

                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else if (_installmentData != null)
                    _buildPaymentStatusSection()
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 100),
                        child: Text(
                          'Search for bill history by Account Number, Vehicle Number, Customer ID, or NIC',
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
        labelText: 'Search Bill History',
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        hintText: 'Enter Account No, Customer ID, NIC, Name or Vehicle No',
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
                      _financeData = null;
                      _installmentData = null;
                      _searchError = '';
                    });
                  },
                )
                : null,
      ),
    );
  }

  Widget _buildCustomerInfoItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: primaryColor.withAlpha((0.1 * 255).toInt()),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: primaryColor),
        ),
        SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // Helper method to get phone number from various fields in the database
  String _getPhoneNumber() {
    if (_customerData == null) return 'N/A';

    // Check different possible fields for phone number in the database
    if (_customerData!.containsKey('phoneNumber') &&
        _customerData!['phoneNumber'] != null) {
      return _customerData!['phoneNumber'];
    } else if (_customerData!.containsKey('phone') &&
        _customerData!['phone'] != null) {
      return _customerData!['phone'];
    } else if (_customerData!.containsKey('mobileNumber') &&
        _customerData!['mobileNumber'] != null) {
      return _customerData!['mobileNumber'];
    } else if (_customerData!.containsKey('mobile') &&
        _customerData!['mobile'] != null) {
      return _customerData!['mobile'];
    } else if (_customerData!.containsKey('contactNumber') &&
        _customerData!['contactNumber'] != null) {
      return _customerData!['contactNumber'];
    } else if (_customerData!.containsKey('contact') &&
        _customerData!['contact'] != null) {
      return _customerData!['contact'];
    }

    return 'N/A';
  }

  Widget _buildPaymentStatusSection() {
    // Check if loan is fully paid
    bool isLoanFullyPaid = _isLoanFullyPaid();

    // Format currency values
    String formattedLoanAmount =
        'Rs. ${_formatNumber(_financeData!['loanAmount'].toString())}';
    String formattedMonthlyInstallment =
        isLoanFullyPaid
            ? '-'
            : 'Rs. ${_formatNumber(_installmentData!['monthlyInstallment'].toString())}';
    String formattedBalance =
        'Rs. ${_formatNumber(_installmentData!['balance'].toString())}';
    String formattedCurrentDue =
        'Rs. ${_formatNumber(_calculateCurrentDue().toString())}';

    // Get interest rate
    String interestRate = '${_financeData!['interestRate']}%';

    // Get total amount directly from the installmentData
    String formattedTotalAmount =
        'Rs. ${_formatNumber(_installmentData!.containsKey('totalAmount') ? _installmentData!['totalAmount'].toString() : _calculateTotalAmount().toString())}';

    // Format maturity date
    String maturityDate =
        isLoanFullyPaid ? '-' : (_financeData!['maturityDate'] ?? 'N/A');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        const SizedBox(height: 60),
        Text(
          'Payment Status',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
        ),
        const SizedBox(height: 40),

        // Payment Status Cards - First Row (3 items)
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Monthly Installment',
                formattedMonthlyInstallment,
                Icons.payment,
                Colors.green.shade600,
                bgColor: Colors.green.shade50,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Next Due Date',
                isLoanFullyPaid
                    ? '-'
                    : DateFormat('yyyy-MM-dd').format(
                      DateFormat(
                        'yyyy-MM-dd',
                      ).parse(_installmentData!['nextDueDate']),
                    ),
                Icons.event,
                Colors.blue.shade600,
                bgColor: Colors.blue.shade50,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Current Arrears',
                formattedCurrentDue,
                Icons.warning_amber,
                _calculateCurrentDue() > 0
                    ? Colors.orange.shade700
                    : Colors.green.shade600,
                isHighlighted: _calculateCurrentDue() > 0,
                bgColor:
                    _calculateCurrentDue() > 0
                        ? Colors.orange.shade50
                        : Colors.green.shade50,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Payment Status Cards - Second Row (3 items)
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Remaining Balance',
                formattedBalance,
                Icons.account_balance_wallet,
                Colors.purple.shade600,
                bgColor: Colors.purple.shade50,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Installments Paid',
                '${_installmentData!['installmentsPaid']} of ${_installmentData!['installmentsPaid'] + _installmentData!['remainingInstallments']}',
                Icons.check_circle,
                Colors.indigo.shade600,
                bgColor: Colors.indigo.shade50,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Loan Amount',
                formattedLoanAmount,
                Icons.attach_money,
                Colors.teal.shade600,
                bgColor: Colors.teal.shade50,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Payment Status Cards - Third Row (NEW ROW with 3 items)
        Row(
          children: [
            Expanded(
              child: _buildStatusCard(
                'Interest Rate',
                interestRate,
                Icons.percent,
                Colors.amber.shade700,
                bgColor: Colors.yellow.shade100,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Total Amount',
                formattedTotalAmount,
                Icons.account_balance,
                Colors.deepPurple.shade600,
                bgColor: Colors.deepPurple.shade50,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: _buildStatusCard(
                'Maturity Date',
                maturityDate,
                Icons.calendar_today,
                Colors.red.shade600,
                bgColor: Colors.red.shade50,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildStatusCard(
    String title,
    String value,
    IconData icon,
    Color color, {
    bool isHighlighted = false,
    Color? bgColor,
  }) {
    return Card(
      elevation: isHighlighted ? 4 : 2,
      shadowColor:
          isHighlighted
              ? color.withAlpha((0.4 * 255).toInt())
              : Colors.black.withAlpha((0.1 * 255).toInt()),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side:
            isHighlighted
                ? BorderSide(color: color, width: 2)
                : BorderSide.none,
      ),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient:
              isHighlighted
                  ? LinearGradient(
                    colors: [
                      color.withAlpha((0.2 * 255).toInt()),
                      Colors.white,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                  : null,
          color: isHighlighted ? null : bgColor,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withAlpha((0.15 * 255).toInt()),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 24, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isHighlighted ? color : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
