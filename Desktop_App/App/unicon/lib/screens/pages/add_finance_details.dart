import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class AddFinanceDetailsPage extends StatefulWidget {
  const AddFinanceDetailsPage({super.key});

  @override
  State<AddFinanceDetailsPage> createState() => _AddFinanceDetailsPageState();
}

class _AddFinanceDetailsPageState extends State<AddFinanceDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;

  // Customer data
  Map<String, dynamic>? _customerData;

  // Flag to track if customer already has finance
  bool _customerHasFinance = false;

  final List<FocusNode> _focusNodes = List.generate(8, (_) => FocusNode());

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _accountNumberController =
      TextEditingController();
  final TextEditingController _vehicleNumberController =
      TextEditingController();
  final TextEditingController _loanAmountController = TextEditingController();
  final TextEditingController _openingDateController = TextEditingController();
  final TextEditingController _timePeriodController = TextEditingController();
  final TextEditingController _interestRateController = TextEditingController();
  final TextEditingController _monthlyInstallmentController =
      TextEditingController();
  final TextEditingController _maturityDateController = TextEditingController();
  final TextEditingController _totalAmountDueController =
      TextEditingController();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat('#,##0');

  @override
  void initState() {
    super.initState();

    // Set default opening date to today
    _openingDateController.text = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now());

    // Add listeners to focus nodes
    for (var node in _focusNodes) {
      node.addListener(() {
        if (node.hasFocus && _submitted) {
          setState(() => _submitted = false);
        }
      });
    }

    // Add listener to search field
    _searchController.addListener(_onSearchChanged);

    // Add listeners for calculation
    _loanAmountController.addListener(_updateCalculations);
    _timePeriodController.addListener(_updateCalculations);
    _interestRateController.addListener(_updateCalculations);

    // Add listener to loan amount field for formatting
    _loanAmountController.addListener(_formatLoanAmount);
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
          _searchError = '';
          _accountNumberController.clear();
          _customerHasFinance = false;
        });
      }
    });
  }

  void _formatLoanAmount() {
    String text = _loanAmountController.text;

    // Skip if empty
    if (text.isEmpty) {
      return;
    }

    // Only proceed if text doesn't already have proper formatting
    if (!text.contains(',')) {
      // Remove any non-digit characters
      String cleanText = text.replaceAll(RegExp(r'[^\d]'), '');

      if (cleanText.isNotEmpty) {
        // Convert to integer
        int value = int.parse(cleanText);

        // Format with commas
        String formattedText = _currencyFormatter.format(value);

        // Set the new value with proper formatting
        _loanAmountController.value = TextEditingValue(
          text: formattedText,
          selection: TextSelection.collapsed(offset: formattedText.length),
        );
      }
    }
  }

  Future<void> _searchCustomer(String searchQuery) async {
    setState(() {
      _isLoading = true;
      _searchError = '';
      _customerHasFinance = false;
    });

    try {
      // First try to search by Customer ID
      var snapshot =
          await _firestore.collection('customers').doc(searchQuery).get();

      // If not found by Customer ID, try NIC
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
          setState(() {
            _customerData = null;
            _searchError = 'No customer found with the given ID or NIC';
            _isLoading = false;
            _accountNumberController.clear();
          });
          return;
        }
      }

      // Get customer data
      Map<String, dynamic> customerData = snapshot.data()!;

      // Check if the customer already has an active finance
      final String customerId = customerData['customerId'] ?? '';
      final financeQuery =
          await _firestore
              .collection('finances')
              .where('customerId', isEqualTo: customerId)
              .get();

      if (financeQuery.docs.isNotEmpty) {
        // Customer already has finance, show dialog
        setState(() {
          _customerHasFinance = true;
          _customerData = customerData;
          _accountNumberController.text = customerData['accountNumber'] ?? '';

          // Pre-fill with existing finance data
          Map<String, dynamic> financeData = financeQuery.docs.first.data();
          _vehicleNumberController.text = financeData['vehicleNumber'] ?? '';
          _loanAmountController.text = _currencyFormatter.format(
            financeData['loanAmount'] ?? 0,
          );
          _openingDateController.text = financeData['openingDate'] ?? '';
          _timePeriodController.text =
              financeData['timePeriod']?.toString() ?? '';
          _interestRateController.text =
              financeData['interestRate']?.toString() ?? '';
          _maturityDateController.text = financeData['maturityDate'] ?? '';
          _monthlyInstallmentController.text =
              financeData['monthlyInstallment']?.toString() ?? '';
          _totalAmountDueController.text =
              financeData['totalAmountDue']?.toString() ?? '';
        });

        // Show dialog after state is updated
        if (mounted) {
          Future.microtask(() => _showCustomerHasFinanceDialog());
        }
      } else {
        setState(() {
          _customerData = customerData;
          _accountNumberController.text = customerData['accountNumber'] ?? '';
          _customerHasFinance = false;
        });
      }
    } catch (e) {
      setState(() {
        _searchError = 'Error searching for customer: ${e.toString()}';
        _isLoading = false;
      });
      debugPrint('Error searching for customer: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showCustomerHasFinanceDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Warning'),
          content: const Text(
            'This customer already has an active finance. You cannot add another one.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
                _resetPage();
              },
            ),
          ],
        );
      },
    );
  }

  void _resetPage() {
    _clearForm();
    setState(() {
      _customerHasFinance = false;
    });
    // This will fully reload the page if needed
    // If you have a parent widget with a key, you can use it to refresh the entire page
  }

  void _calculateMaturityDate() {
    if (_openingDateController.text.isEmpty ||
        _timePeriodController.text.isEmpty) {
      return;
    }

    try {
      final openingDate = DateFormat(
        'yyyy-MM-dd',
      ).parse(_openingDateController.text);
      final years = int.tryParse(_timePeriodController.text) ?? 0;

      if (years > 0) {
        final maturityDate = DateTime(
          openingDate.year + years,
          openingDate.month,
          openingDate.day,
        );

        _maturityDateController.text = DateFormat(
          'yyyy-MM-dd',
        ).format(maturityDate);
      } else {
        _maturityDateController.clear();
      }
    } catch (e) {
      debugPrint('Error calculating maturity date: $e');
      _maturityDateController.clear();
    }
  }

  void _updateCalculations() {
    _calculateMaturityDate();
    _calculateMonthlyInstallment();
    _calculateTotalAmountDue();
  }

  void _calculateMonthlyInstallment() {
    if (_loanAmountController.text.isEmpty ||
        _timePeriodController.text.isEmpty ||
        _interestRateController.text.isEmpty) {
      _monthlyInstallmentController.clear();
      return;
    }

    try {
      // Remove commas from loan amount
      final cleanLoanAmount = _loanAmountController.text.replaceAll(',', '');
      final principal = double.tryParse(cleanLoanAmount) ?? 0;
      final years = int.tryParse(_timePeriodController.text) ?? 0;
      final interestRate = double.tryParse(_interestRateController.text) ?? 0;

      if (principal <= 0 || years <= 0 || interestRate <= 0) {
        _monthlyInstallmentController.clear();
        return;
      }

      // Convert annual interest rate to monthly
      final monthlyInterestRate = interestRate / (12 * 100);

      // Total number of monthly payments
      final numberOfPayments = years * 12;

      // Monthly installment calculation using EMI formula
      final x = math.pow(1 + monthlyInterestRate, numberOfPayments);
      final monthlyPayment = principal * monthlyInterestRate * x / (x - 1);

      // Format and set the value
      _monthlyInstallmentController.text = _currencyFormatter.format(
        monthlyPayment.round(),
      );
    } catch (e) {
      debugPrint('Error calculating monthly installment: $e');
      _monthlyInstallmentController.clear();
    }
  }

  void _calculateTotalAmountDue() {
    if (_monthlyInstallmentController.text.isEmpty ||
        _timePeriodController.text.isEmpty) {
      _totalAmountDueController.clear();
      return;
    }

    try {
      // Remove commas from monthly installment
      final cleanMonthlyAmount = _monthlyInstallmentController.text.replaceAll(
        ',',
        '',
      );
      final monthlyPayment = double.tryParse(cleanMonthlyAmount) ?? 0;
      final years = int.tryParse(_timePeriodController.text) ?? 0;

      if (monthlyPayment <= 0 || years <= 0) {
        _totalAmountDueController.clear();
        return;
      }

      // Calculate total amount due
      final totalPayments = years * 12;
      final totalAmount = monthlyPayment * totalPayments;

      // Format and set the value
      _totalAmountDueController.text = _currencyFormatter.format(
        totalAmount.round(),
      );
    } catch (e) {
      debugPrint('Error calculating total amount due: $e');
      _totalAmountDueController.clear();
    }
  }

  Future<void> _submitData() async {
    setState(() {
      _submitted = true;
      _isLoading = true;
    });

    if (!_formKey.currentState!.validate() || _customerData == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Check if customer already has finance
    if (_customerHasFinance) {
      if (mounted) {
        _showCustomerHasFinanceDialog();
        setState(() => _isLoading = false);
      }
      return;
    }

    try {
      // Use account number as the document ID
      final accountNumber = _accountNumberController.text;

      // Parse the loan amount to remove commas for storage
      final cleanLoanAmount = _loanAmountController.text.replaceAll(',', '');
      final cleanMonthlyInstallment = _monthlyInstallmentController.text
          .replaceAll(',', '');
      final cleanTotalAmountDue = _totalAmountDueController.text.replaceAll(
        ',',
        '',
      );

      // Save finance data to Firestore
      await _firestore.collection('finances').doc(accountNumber).set({
        'customerId': _customerData!['customerId'],
        'accountNumber': accountNumber,
        'vehicleNumber': _vehicleNumberController.text.toUpperCase(),
        'loanAmount': double.parse(cleanLoanAmount),
        'openingDate': _openingDateController.text,
        'timePeriod': int.parse(_timePeriodController.text),
        'interestRate': double.parse(_interestRateController.text),
        'monthlyInstallment': double.parse(cleanMonthlyInstallment),
        'maturityDate': _maturityDateController.text,
        'totalAmountDue': double.parse(cleanTotalAmountDue),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Create installments collection entry
      await _createInstallmentsRecord(
        accountNumber,
        _customerData!['customerId'],
        _customerData!['nic'] ?? '',
        double.parse(cleanTotalAmountDue),
        double.parse(cleanMonthlyInstallment),
        int.parse(_timePeriodController.text) * 12, // Convert years to months
        _openingDateController.text,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: const Text(
                'Finance details updated successfully',
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
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Create installments record
  Future<void> _createInstallmentsRecord(
    String accountNumber,
    String customerId,
    String nic,
    double totalAmount,
    double monthlyInstallment,
    int totalMonths,
    String openingDate,
  ) async {
    // Parse opening date
    DateTime startDate = DateFormat('yyyy-MM-dd').parse(openingDate);

    // Set first billing date to 30 days after opening date
    DateTime firstBillingDate = startDate.add(const Duration(days: 30));

    // Generate installment schedule
    List<Map<String, dynamic>> arrears = [];
    List<Map<String, dynamic>> monthlyInstallments = [];

    for (int i = 0; i < totalMonths; i++) {
      // Calculate billing date by adding months properly
      DateTime billingDate;

      // First get the target month and year
      int targetMonth = firstBillingDate.month + i;
      int targetYear = firstBillingDate.year + (targetMonth - 1) ~/ 12;
      targetMonth =
          ((targetMonth - 1) % 12) + 1; // Adjust month to be 1-12 range

      // Try to create the date with the same day
      billingDate = DateTime(targetYear, targetMonth, firstBillingDate.day);

      // If the day is invalid for this month (e.g., Feb 30), use the last day of month
      int daysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;
      if (firstBillingDate.day > daysInMonth) {
        billingDate = DateTime(targetYear, targetMonth, daysInMonth);
      }

      String monthKey = DateFormat('yyyy-MM').format(billingDate);
      String formattedBillingDate = DateFormat(
        'yyyy-MM-dd',
      ).format(billingDate);

      // Add to arrears (initially all pending)
      arrears.add({
        'month': monthKey,
        'amountPayable': monthlyInstallment,
        'billingDate': formattedBillingDate,
        'status':
            i == 0 ? 'due' : 'pending', // First month is due, rest are pending
      });

      // Add to monthly installments (all pending initially)
      monthlyInstallments.add({
        'month': monthKey,
        'amountPaid': 0, // Initially no payment
        'billingDate': formattedBillingDate,
        'status': 'pending',
      });
    }

    // Calculate next due date (first billing date)
    String nextDueDate = DateFormat('yyyy-MM-dd').format(firstBillingDate);

    // Create the installments document
    await _firestore.collection('installments').doc(accountNumber).set({
      'customerId': customerId,
      'accountNumber': accountNumber,
      'nic': nic,
      'customerName': _customerData!['fullName'],
      'vehicleNumber': _vehicleNumberController.text.toUpperCase(),
      'totalAmount': totalAmount,
      'monthlyInstallment': monthlyInstallment,
      'totalMonths': totalMonths,
      'installmentsPaid': 0,
      'arrears': arrears,
      'balance': totalAmount,
      'remainingInstallments': totalMonths,
      'nextDueDate': nextDueDate,
      'monthlyInstallments': monthlyInstallments,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _searchController.clear();
    _accountNumberController.clear();
    _vehicleNumberController.clear();
    _loanAmountController.clear();
    _timePeriodController.clear();
    _interestRateController.clear();
    _monthlyInstallmentController.clear();
    _maturityDateController.clear();
    _totalAmountDueController.clear();
    _openingDateController.text = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now());

    setState(() {
      _submitted = false;
      _customerData = null;
      _searchError = '';
      _customerHasFinance = false;
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _loanAmountController.removeListener(_formatLoanAmount);
    _loanAmountController.removeListener(_updateCalculations);
    _timePeriodController.removeListener(_updateCalculations);
    _interestRateController.removeListener(_updateCalculations);

    _searchController.dispose();
    _accountNumberController.dispose();
    _vehicleNumberController.dispose();
    _loanAmountController.dispose();
    _openingDateController.dispose();
    _timePeriodController.dispose();
    _interestRateController.dispose();
    _monthlyInstallmentController.dispose();
    _maturityDateController.dispose();
    _totalAmountDueController.dispose();

    _debounce?.cancel();

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
                  'Add Finance Details',
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
                              Icon(
                                Icons.account_box_rounded,
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
              child: Form(
                key: _formKey,
                autovalidateMode:
                    _submitted
                        ? AutovalidateMode.always
                        : AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search Field
                    _buildSearchField(),

                    if (_searchError.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: Text(
                          _searchError,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),

                    const SizedBox(height: 20),

                    // Account Number (auto-filled from search)
                    _buildTextField(
                      _accountNumberController,
                      _focusNodes[0],
                      'Account Number',
                      Icons.account_balance_wallet,
                      keyboardType: TextInputType.number,
                      readOnly: true,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please search for a customer first'
                                  : null,
                    ),

                    const SizedBox(height: 20),

                    // Vehicle Number with auto-formatting
                    _buildTextField(
                      _vehicleNumberController,
                      _focusNodes[1],
                      'Vehicle Number',
                      Icons.directions_car,
                      inputFormatters: [VehicleNumberFormatter()],
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter vehicle number'
                                  : null,
                    ),

                    const SizedBox(height: 20),

                    // Loan Amount with comma formatting
                    _buildTextField(
                      _loanAmountController,
                      _focusNodes[2],
                      'Loan Amount (Rs)',
                      Icons.attach_money,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LoanAmountFormatter(),
                      ],
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter loan amount';
                        // Remove commas for validation
                        final cleanValue = value.replaceAll(',', '');
                        if (double.tryParse(cleanValue) == null) {
                          return 'Please enter a valid amount';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // Time Period
                    _buildTextField(
                      _timePeriodController,
                      _focusNodes[3],
                      'Time Period (Years)',
                      Icons.access_time,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter time period';
                        if (int.tryParse(value) == null ||
                            int.parse(value) <= 0) {
                          return 'Please enter a valid time period';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // Interest Rate
                    _buildTextField(
                      _interestRateController,
                      _focusNodes[4],
                      'Interest Rate (%)',
                      Icons.percent,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      validator: (value) {
                        if (value!.isEmpty) return 'Please enter interest rate';
                        if (double.tryParse(value) == null) {
                          return 'Please enter a valid rate';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // Opening Date (auto-filled with today's date)
                    _buildTextField(
                      _openingDateController,
                      _focusNodes[5],
                      'Opening Date',
                      Icons.calendar_today,
                      readOnly: true,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter opening date'
                                  : null,
                    ),

                    const SizedBox(height: 20),

                    // Monthly Installment (auto-calculated)
                    _buildTextField(
                      _monthlyInstallmentController,
                      _focusNodes[6],
                      'Monthly Installment (Rs)',
                      Icons.payments,
                      readOnly: true,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter loan amount, time period and interest rate to calculate monthly installment'
                                  : null,
                    ),

                    const SizedBox(height: 20),

                    // Total Amount Due (auto-calculated, hidden field)
                    SizedBox(
                      // This SizedBox makes the field invisible but still functional
                      height: 0,
                      child: Opacity(
                        opacity: 0,
                        child: _buildTextField(
                          _totalAmountDueController,
                          FocusNode(),
                          'Total Amount Due',
                          Icons.money,
                          readOnly: true,
                        ),
                      ),
                    ),

                    // Maturity Date (auto-calculated)
                    _buildTextField(
                      _maturityDateController,
                      _focusNodes[7],
                      'Maturity Date',
                      Icons.date_range,
                      readOnly: true,
                      validator:
                          (value) =>
                              value!.isEmpty
                                  ? 'Please enter time period to calculate maturity date'
                                  : null,
                    ),

                    const SizedBox(height: 30),

                    // Buttons: Submit & Clear
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildActionButton(
                          'Submit',
                          Colors.blue,
                          _isLoading || _customerHasFinance
                              ? null
                              : _submitData,
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

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      decoration: InputDecoration(
        labelText: 'Search Customer',
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.blue,
        ),
        hintText: 'Enter Customer ID or NIC',
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
                      _accountNumberController.clear();
                      _customerHasFinance = false;
                    });
                  },
                )
                : null,
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

// Completely rewritten vehicle number formatter
class VehicleNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Convert to uppercase
    String text = newValue.text.toUpperCase();

    // Determine cursor position
    int selectionIndex = newValue.selection.end;

    // Split the string into letters and numbers
    RegExp letterRegex = RegExp(r'[A-Z]');
    RegExp numberRegex = RegExp(r'[0-9]');

    String letters = '';
    String numbers = '';

    // Extract all letters and numbers
    for (int i = 0; i < text.length; i++) {
      if (letterRegex.hasMatch(text[i])) {
        letters += text[i];
      } else if (numberRegex.hasMatch(text[i])) {
        // Only take the first 4 digits
        if (numbers.length < 4) {
          numbers += text[i];
        }
      }
    }

    // Build formatted result
    String result = letters;

    // Add hyphen if we have both letters and numbers
    if (letters.isNotEmpty && numbers.isNotEmpty) {
      result += '-';
    }

    // Add the numbers
    result += numbers;

    // Determine new cursor position based on the changes
    if (result.length != oldValue.text.length) {
      // If the text length changed, place cursor at the end of the string
      selectionIndex = result.length;
    } else {
      // Otherwise maintain original position
      selectionIndex = newValue.selection.end;
    }

    // Make sure the selection index is within bounds
    selectionIndex = selectionIndex.clamp(0, result.length);

    return TextEditingValue(
      text: result,
      selection: TextSelection.collapsed(offset: selectionIndex),
    );
  }
}

// Dedicated formatter for loan amount
class LoanAmountFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat('#,##0');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If the new value is empty, return as is
    if (newValue.text.isEmpty) {
      return newValue;
    }

    // Remove all non-digit characters
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');

    // Parse the cleaned integer
    int value = int.tryParse(digitsOnly) ?? 0;

    // Format with commas
    String formatted = _formatter.format(value);

    // Always place cursor at the end for simplicity
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
