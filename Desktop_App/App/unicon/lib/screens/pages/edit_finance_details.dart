import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class EditFinanceDetailsPage extends StatefulWidget {
  const EditFinanceDetailsPage({super.key});

  @override
  State<EditFinanceDetailsPage> createState() => _EditFinanceDetailsPageState();
}

class _EditFinanceDetailsPageState extends State<EditFinanceDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();

  // Form controllers
  final TextEditingController _financeIdController = TextEditingController();
  final TextEditingController _customerIdController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _vehicleNumberController =
      TextEditingController();
  final TextEditingController _loanAmountController = TextEditingController();
  final TextEditingController _openingDateController = TextEditingController();
  final TextEditingController _timePeriodController = TextEditingController();
  final TextEditingController _interestRateController = TextEditingController();
  final TextEditingController _maturityDateController = TextEditingController();

  // Finance and customer data
  Map<String, dynamic>? _financeData;
  Map<String, dynamic>? _customerData;
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;
  final _formKey = GlobalKey<FormState>();

  // Store the actual document ID for the finance document
  String? _firestoreDocumentId;

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
    _financeIdController.dispose();
    _customerIdController.dispose();
    _accountNumberController.dispose();
    _vehicleNumberController.dispose();
    _loanAmountController.dispose();
    _openingDateController.dispose();
    _timePeriodController.dispose();
    _interestRateController.dispose();
    _maturityDateController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      // Only search if there's text
      if (_searchController.text.isNotEmpty) {
        _searchFinance(_searchController.text);
      } else {
        setState(() {
          _financeData = null;
          _customerData = null;
          _searchError = '';
          _clearFormFields();
          _firestoreDocumentId = null;
        });
      }
    });
  }

  Future<void> _searchFinance(String searchQuery) async {
    setState(() {
      _isLoading = true;
      _searchError = '';
    });

    try {
      // Convert the search query to uppercase for case-insensitive search
      final upperCaseQuery = searchQuery.toUpperCase();

      // First try to search by account number
      var financeSnapshot =
          await _firestore
              .collection('finances')
              .where('accountNumber', isEqualTo: upperCaseQuery)
              .limit(1)
              .get();

      // If not found by account number, try customer ID
      if (financeSnapshot.docs.isEmpty) {
        financeSnapshot =
            await _firestore
                .collection('finances')
                .where('customerId', isEqualTo: upperCaseQuery)
                .limit(1)
                .get();

        // If not found by customer ID, try vehicle number
        if (financeSnapshot.docs.isEmpty) {
          financeSnapshot =
              await _firestore
                  .collection('finances')
                  .where('vehicleNumber', isEqualTo: upperCaseQuery)
                  .limit(1)
                  .get();

          // If still not found, try to search by NIC
          if (financeSnapshot.docs.isEmpty) {
            // Search for customer by NIC
            final customerSnapshot =
                await _firestore
                    .collection('customers')
                    .where('nic', isEqualTo: upperCaseQuery)
                    .limit(1)
                    .get();

            if (customerSnapshot.docs.isNotEmpty) {
              // If customer found, get the customer ID
              final customerId =
                  customerSnapshot.docs.first.data()['customerId'];

              // Now search for finance data using that customer ID
              financeSnapshot =
                  await _firestore
                      .collection('finances')
                      .where('customerId', isEqualTo: customerId)
                      .limit(1)
                      .get();
            }
          }
        }
      }

      // If finance data found
      if (financeSnapshot.docs.isNotEmpty) {
        final financeDoc = financeSnapshot.docs.first;
        final financeData = financeDoc.data();

        // Store the Firestore document ID for later use
        _firestoreDocumentId = financeDoc.id;

        // Now fetch the customer data associated with this finance record
        final customerSnapshot =
            await _firestore
                .collection('customers')
                .doc(financeData['customerId'])
                .get();

        setState(() {
          _financeData = financeData;
          _customerData = customerSnapshot.data();
          _isLoading = false;
        });

        _populateFormFields();
      } else {
        setState(() {
          _financeData = null;
          _customerData = null;
          _searchError =
              'No finance record found with the given search criteria';
          _isLoading = false;
          _clearFormFields();
          _firestoreDocumentId = null;
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for finance record: ${e.toString()}';
        _isLoading = false;
        _clearFormFields();
        _firestoreDocumentId = null;
      });
      debugPrint('Error searching for finance record: $e');
    }
  }

  void _populateFormFields() {
    if (_financeData != null) {
      _financeIdController.text = _firestoreDocumentId ?? '';
      _customerIdController.text = _financeData!['customerId'] ?? '';
      _accountNumberController.text = _financeData!['accountNumber'] ?? '';
      _vehicleNumberController.text = _financeData!['vehicleNumber'] ?? '';

      // Format loan amount properly
      if (_financeData!.containsKey('loanAmount')) {
        final loanAmount = _financeData!['loanAmount'];
        if (loanAmount is num) {
          _loanAmountController.text = loanAmount.toString();
        } else {
          _loanAmountController.text = loanAmount.toString();
        }
      } else {
        _loanAmountController.text = '';
      }

      _openingDateController.text = _financeData!['openingDate'] ?? '';

      // Handle time period (could be string or number)
      if (_financeData!.containsKey('timePeriod')) {
        final timePeriod = _financeData!['timePeriod'];
        _timePeriodController.text = timePeriod.toString();
      } else {
        _timePeriodController.text = '';
      }

      // Handle interest rate (could be string or number)
      if (_financeData!.containsKey('interestRate')) {
        final interestRate = _financeData!['interestRate'];
        _interestRateController.text = interestRate.toString();
      } else {
        _interestRateController.text = '';
      }

      _maturityDateController.text = _financeData!['maturityDate'] ?? '';
    }
  }

  void _clearFormFields() {
    _financeIdController.clear();
    _customerIdController.clear();
    _accountNumberController.clear();
    _vehicleNumberController.clear();
    _loanAmountController.clear();
    _openingDateController.clear();
    _timePeriodController.clear();
    _interestRateController.clear();
    _maturityDateController.clear();
  }

  String _formatCurrency(String amount) {
    try {
      // Remove any commas first
      final sanitized = amount.replaceAll(',', '');

      // Remove any decimal part for integer formatting
      String integerPart = sanitized;
      if (sanitized.contains('.')) {
        integerPart = sanitized.split('.')[0];
      }

      // Convert to integer
      int value = int.parse(integerPart);

      // Format with commas
      final formatter = NumberFormat('#,##0');
      return formatter.format(value);
    } catch (e) {
      // Return original if there's an error
      return amount;
    }
  }

  Future<void> _updateFinance() async {
    if (_financeData == null ||
        !_formKey.currentState!.validate() ||
        _firestoreDocumentId == null) {
      if (_firestoreDocumentId == null) {
        setState(() {
          _searchError = 'Missing document ID. Please search again.';
        });
      }
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Sanitize loan amount (remove commas)
      final sanitizedLoanAmount = _loanAmountController.text.replaceAll(
        ',',
        '',
      );

      // Calculate monthly installment and total amount due
      double loanAmount = double.tryParse(sanitizedLoanAmount) ?? 0;
      double interestRate = double.tryParse(_interestRateController.text) ?? 0;
      int timePeriod = int.tryParse(_timePeriodController.text) ?? 0;

      double monthlyInstallment = _calculateMonthlyInstallment(
        loanAmount,
        interestRate,
        timePeriod,
      );

      double totalAmountDue = monthlyInstallment * timePeriod * 12;

      // Update finance document in Firestore
      final Map<String, dynamic> updatedData = {
        'customerId': _customerIdController.text,
        'accountNumber': _accountNumberController.text,
        'vehicleNumber': _vehicleNumberController.text,
        'loanAmount': num.tryParse(sanitizedLoanAmount) ?? 0,
        'openingDate': _openingDateController.text,
        'timePeriod': num.tryParse(_timePeriodController.text) ?? 0,
        'interestRate': num.tryParse(_interestRateController.text) ?? 0,
        'maturityDate': _maturityDateController.text,
        'monthlyInstallment': monthlyInstallment,
        'totalAmountDue': totalAmountDue,
      };

      // Use the stored document ID to update the document
      await _firestore
          .collection('finances')
          .doc(_firestoreDocumentId)
          .update(updatedData);

      setState(() {
        _isLoading = false;
        // Update local finance data
        _financeData = {..._financeData!, ...updatedData};
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: const Text(
                'Finance record updated successfully',
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
                'Error updating finance record: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      debugPrint('Error updating finance record: $e');
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

  // Helper for selecting dates
  Future<void> _selectDate(
    BuildContext context,
    TextEditingController controller,
  ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        controller.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  // Calculate maturity date based on opening date and time period
  void _calculateMaturityDate() {
    try {
      if (_openingDateController.text.isNotEmpty &&
          _timePeriodController.text.isNotEmpty) {
        final openingDate = DateFormat(
          'yyyy-MM-dd',
        ).parse(_openingDateController.text);
        final timePeriod = int.tryParse(_timePeriodController.text) ?? 0;

        if (timePeriod > 0) {
          final maturityDate = DateTime(
            openingDate.year + timePeriod,
            openingDate.month,
            openingDate.day,
          );

          _maturityDateController.text = DateFormat(
            'yyyy-MM-dd',
          ).format(maturityDate);
        }
      }
    } catch (e) {
      debugPrint('Error calculating maturity date: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel with Customer Image and Info
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Edit Finance Details',
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
                                'No finance record selected',
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

          // Right Panel with Finance Details Form
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
                    _buildFinanceForm()
                  else
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 100),
                        child: Text(
                          'Search for a finance record by Account Number, Customer ID, Vehicle Number, or NIC',
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
      textCapitalization: TextCapitalization.characters,
      decoration: InputDecoration(
        labelText: 'Search Finance Record...',
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        hintText: 'Enter Account Number, Customer ID, Vehicle Number, or NIC',
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
                      _clearFormFields();
                      _firestoreDocumentId = null;
                    });
                  },
                )
                : null,
      ),
      onChanged: (value) {
        // Auto-convert to uppercase
        if (value != value.toUpperCase()) {
          _searchController.value = TextEditingValue(
            text: value.toUpperCase(),
            selection: _searchController.selection,
          );
        }
      },
    );
  }

  Widget _buildFinanceForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Finance ID (hidden)
          Visibility(
            visible: false,
            child: TextFormField(
              controller: _financeIdController,
              readOnly: true,
            ),
          ),

          // Customer ID (read-only)
          _buildEditableField(
            label: 'Customer ID',
            controller: _customerIdController,
            icon: Icons.person,
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

          // Vehicle Number
          _buildEditableField(
            label: 'Vehicle Number',
            controller: _vehicleNumberController,
            icon: Icons.directions_car,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter vehicle number';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Loan Amount
          _buildEditableField(
            label: 'Loan Amount (Rs)',
            controller: _loanAmountController,
            icon: Icons.attach_money,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter loan amount';
              }
              // Basic validation for numeric input (allowing commas)
              final sanitized = value.replaceAll(',', '');
              if (double.tryParse(sanitized) == null) {
                return 'Please enter a valid amount';
              }
              return null;
            },
            onChanged: (value) {
              // Format with commas as they type
              if (value.isNotEmpty) {
                final sanitized = value.replaceAll(',', '');
                if (double.tryParse(sanitized) != null) {
                  final formatted = _formatCurrency(sanitized);
                  if (formatted != value) {
                    _loanAmountController.value = TextEditingValue(
                      text: formatted,
                      selection: TextSelection.collapsed(
                        offset: formatted.length,
                      ),
                    );
                  }
                }
              }
            },
          ),
          const SizedBox(height: 20),

          // Time Period
          _buildEditableField(
            label: 'Time Period (Years)',
            controller: _timePeriodController,
            icon: Icons.access_time,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter time period';
              }
              if (int.tryParse(value) == null) {
                return 'Please enter a valid number';
              }
              return null;
            },
            onChanged: (value) {
              // Recalculate maturity date when time period changes
              _calculateMaturityDate();
            },
          ),
          const SizedBox(height: 20),

          // Interest Rate
          _buildEditableField(
            label: 'Interest Rate (%)',
            controller: _interestRateController,
            icon: Icons.percent,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter interest rate';
              }
              if (double.tryParse(value) == null) {
                return 'Please enter a valid rate';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),

          // Opening Date
          _buildEditableField(
            label: 'Opening Date',
            controller: _openingDateController,
            icon: Icons.calendar_today,
            readOnly: true,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select opening date';
              }
              return null;
            },
            onTap: () async {
              await _selectDate(context, _openingDateController);
              _calculateMaturityDate(); // Recalculate maturity date when opening date changes
            },
          ),
          const SizedBox(height: 20),

          // Maturity Date (calculated and readonly)
          _buildEditableField(
            label: 'Maturity Date',
            controller: _maturityDateController,
            icon: Icons.date_range,
            readOnly: true, // Calculated based on opening date and time period
          ),
          const SizedBox(height: 30),

          // Update Button
          Center(
            child: _buildActionButton(
              'Update Finance Record',
              Colors.blue,
              _isLoading ? null : _updateFinance,
              padding: const EdgeInsets.symmetric(
                horizontal: 280,
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
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    void Function()? onTap,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      validator: validator,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onTap: onTap,
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
