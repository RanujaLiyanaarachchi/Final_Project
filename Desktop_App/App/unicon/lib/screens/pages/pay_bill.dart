import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class PayBillPage extends StatefulWidget {
  const PayBillPage({super.key});

  @override
  State<PayBillPage> createState() => _PayBillPageState();
}

class _PayBillPageState extends State<PayBillPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String _searchError = '';
  Timer? _debounce;

  // Finance data
  Map<String, dynamic>? _financeData;
  Map<String, dynamic>? _customerData;
  Map<String, dynamic>? _installmentData;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _paymentAmountController =
      TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NumberFormat _currencyFormatter = NumberFormat('#,##0');

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
      if ((arrear['status'] == 'due' || arrear['status'] == 'overdue' || arrear['status'] == 'partial') &&
          arrear['billingDate'].compareTo(today) <= 0) {
        totalDue += arrear['amountPayable'];
      }
    }

    return totalDue;
  }

  // Check if loan is fully paid
  bool _isLoanFullyPaid() {
    if (_installmentData == null) return false;
    return _installmentData!['balance'] <= 0 ||
        _installmentData!['remainingInstallments'] <= 0;
  }

Future<void> _processPayment() async {
  if (_formKey.currentState!.validate() && _installmentData != null) {
    setState(() {
      _isLoading = true;
    });

    try {
      // Get payment amount
      final cleanPaymentAmount = _paymentAmountController.text.replaceAll(
        ',',
        '',
      );
      final paymentAmount = double.parse(cleanPaymentAmount);

      // Get account number
      final accountNumber = _installmentData!['accountNumber'];

      // Get current date
      final now = DateTime.now();
      final paymentDate = DateFormat('yyyy-MM-dd').format(now);

      debugPrint('Processing payment for account: $accountNumber');
      debugPrint('Customer ID: ${_customerData!['customerId']}');
      debugPrint('Payment amount: $paymentAmount');

      // Get installment data
      List<dynamic> arrears = List.from(_installmentData!['arrears']);
      List<dynamic> monthlyInstallments = List.from(
        _installmentData!['monthlyInstallments'],
      );
      int installmentsPaid = _installmentData!['installmentsPaid'];
      int remainingInstallments = _installmentData!['remainingInstallments'];
      int totalInstallments = installmentsPaid + remainingInstallments;
      double balance = _installmentData!['balance'];
      String nextDueDate = _installmentData!['nextDueDate'];
      
      // Track overpayment for notification
      double overpayment = 0;
      // Track how many installments were actually processed in this payment
      int installmentsProcessedInThisPayment = 0;

      debugPrint('Arrears count: ${arrears.length}');
      debugPrint('Original balance: $balance');

      // Check if this is a full payment (payment amount >= balance)
      if (paymentAmount >= balance) {
        debugPrint('FULL PAYMENT DETECTED - marking all as paid');

        // Count remaining unpaid installments
        int unpaidInstallments = 0;
        for (int i = 0; i < arrears.length; i++) {
          if (arrears[i]['status'] == 'pending' ||
              arrears[i]['status'] == 'due' ||
              arrears[i]['status'] == 'overdue' ||
              arrears[i]['status'] == 'partial') {
            unpaidInstallments++;
          }
        }
        
        // Mark all arrears as paid
        for (int i = 0; i < arrears.length; i++) {
          if (arrears[i]['status'] == 'pending' ||
              arrears[i]['status'] == 'due' ||
              arrears[i]['status'] == 'overdue' ||
              arrears[i]['status'] == 'partial') {
            String month = arrears[i]['month'];
            arrears[i]['status'] = 'paid';
            arrears[i]['amountPayable'] = 0;

            // Update the corresponding monthly installment
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                // Use the original amount if it exists, otherwise use standard amount
                double fullPaymentAmount = arrears[i].containsKey('originalAmount') 
                    ? arrears[i]['originalAmount'] 
                    : (arrears[i].containsKey('standardAmount') 
                        ? arrears[i]['standardAmount'] 
                        : 0);
                
                monthlyInstallments[j]['amountPaid'] = fullPaymentAmount;
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['status'] = 'paid';
                break;
              }
            }
          }
        }

        // Set the correct values for a fully paid loan
        installmentsPaid = totalInstallments;
        remainingInstallments = 0;
        balance = 0;
        installmentsProcessedInThisPayment = unpaidInstallments; // All remaining installments are processed

        debugPrint(
          'Loan fully paid off. New balance: $balance, Installments paid: $installmentsPaid, Remaining: $remainingInstallments',
        );
      } else {
        // Normal payment processing for partial payments
        double remainingPayment = paymentAmount;

        // First process due/overdue/partial installments in chronological order
        List<Map<String, dynamic>> dueArrears = [];
        for (int i = 0; i < arrears.length; i++) {
          if (arrears[i]['status'] == 'due' || 
              arrears[i]['status'] == 'overdue' || 
              arrears[i]['status'] == 'partial') {
            dueArrears.add({'index': i, 'arrear': arrears[i]});
          }
        }
        
        // Sort by billing date (earliest first)
        dueArrears.sort((a, b) => 
          a['arrear']['billingDate'].compareTo(b['arrear']['billingDate'])
        );
        
        // Process due/overdue/partial installments
        for (var item in dueArrears) {
          if (remainingPayment <= 0) break;
          
          int idx = item['index'];
          double amountPayable = arrears[idx]['amountPayable'];
          String month = arrears[idx]['month'];
          
          // Store the standard amount if not already present
          if (!arrears[idx].containsKey('standardAmount')) {
            // Use the original amount payable as the standard amount
            arrears[idx]['standardAmount'] = amountPayable;
          }
          
          // Store the original amount if not already present
          if (!arrears[idx].containsKey('originalAmount')) {
            arrears[idx]['originalAmount'] = arrears[idx]['standardAmount'];
          }
          
          double standardAmount = arrears[idx]['standardAmount'];
          double originalAmount = arrears[idx]['originalAmount'];

          debugPrint('Processing arrear for month: $month');
          debugPrint('Amount payable: $amountPayable');
          debugPrint('Standard amount: $standardAmount');
          debugPrint('Original amount: $originalAmount');

          if (remainingPayment >= amountPayable) {
            // Pay off this month's arrear fully
            arrears[idx]['status'] = 'paid';
            arrears[idx]['amountPayable'] = 0;

            // Update the corresponding monthly installment
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                monthlyInstallments[j]['amountPaid'] = originalAmount;
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['status'] = 'paid';
                break;
              }
            }

            remainingPayment -= amountPayable;
            installmentsPaid++;
            remainingInstallments--;
            balance -= amountPayable;
            installmentsProcessedInThisPayment++;

            debugPrint(
              'Fully paid month: $month, remaining payment: $remainingPayment',
            );
          } else {
            // Partial payment
            arrears[idx]['amountPayable'] = amountPayable - remainingPayment;
            arrears[idx]['status'] = 'partial';

            // Update the corresponding monthly installment
            for (int j = 0; j < monthlyInstallments.length; j++) {
              if (monthlyInstallments[j]['month'] == month) {
                monthlyInstallments[j]['amountPaid'] = 
                    (monthlyInstallments[j]['amountPaid'] ?? 0) + remainingPayment;
                monthlyInstallments[j]['paymentDate'] = paymentDate;
                monthlyInstallments[j]['status'] = 'partial';
                break;
              }
            }

            balance -= remainingPayment;
            remainingPayment = 0;
            // We don't increment installmentsPaid for partial payments

            debugPrint(
              'Partially paid month: $month, remaining due: ${arrears[idx]['amountPayable']}',
            );
          }
        }

        // If there's still payment amount remaining after paying due/overdue installments,
        // apply it to pending installments
        if (remainingPayment > 0) {
          debugPrint('Excess payment: $remainingPayment - applying to future payments');
          overpayment = remainingPayment;
          
          // Get pending arrears in chronological order
          List<Map<String, dynamic>> pendingArrears = [];
          for (int i = 0; i < arrears.length; i++) {
            if (arrears[i]['status'] == 'pending') {
              pendingArrears.add({'index': i, 'arrear': arrears[i]});
            }
          }
          
          pendingArrears.sort((a, b) => 
            a['arrear']['billingDate'].compareTo(b['arrear']['billingDate'])
          );
          
          // Apply remaining payment to pending arrears
          for (int pendingIndex = 0; pendingIndex < pendingArrears.length; pendingIndex++) {
            if (remainingPayment <= 0) break;
            
            int idx = pendingArrears[pendingIndex]['index'];
            String month = arrears[idx]['month'];
            
            // Store the standard amount if not already present
            if (!arrears[idx].containsKey('standardAmount')) {
              arrears[idx]['standardAmount'] = arrears[idx]['amountPayable'];
            }
            
            // Store the original amount if not already present
            if (!arrears[idx].containsKey('originalAmount')) {
              arrears[idx]['originalAmount'] = arrears[idx]['standardAmount'];
            }
            
            double amountPayable = arrears[idx]['amountPayable'];
            
            debugPrint('Processing pending month: $month, amount payable: $amountPayable');
            
            if (remainingPayment >= amountPayable) {
              // Fully pay this installment
              arrears[idx]['status'] = 'paid';
              arrears[idx]['amountPayable'] = 0;
              
              // Update monthly installment record
              for (int j = 0; j < monthlyInstallments.length; j++) {
                if (monthlyInstallments[j]['month'] == month) {
                  monthlyInstallments[j]['amountPaid'] = arrears[idx]['originalAmount'];
                  monthlyInstallments[j]['paymentDate'] = paymentDate;
                  monthlyInstallments[j]['status'] = 'paid';
                  break;
                }
              }
              
              balance -= amountPayable;
              remainingPayment -= amountPayable;
              installmentsPaid++;
              remainingInstallments--;
              installmentsProcessedInThisPayment++;
              
              debugPrint('Fully paid pending month: $month, remaining: $remainingPayment');
            } else {
              // Partial payment for this pending installment
              double newAmountPayable = amountPayable - remainingPayment;
              arrears[idx]['amountPayable'] = newAmountPayable;
              arrears[idx]['status'] = 'partial'; // Change from pending to partial
              
              // Update monthly installment record
              for (int j = 0; j < monthlyInstallments.length; j++) {
                if (monthlyInstallments[j]['month'] == month) {
                  monthlyInstallments[j]['amountPaid'] = 
                      (monthlyInstallments[j]['amountPaid'] ?? 0) + remainingPayment;
                  monthlyInstallments[j]['paymentDate'] = paymentDate;
                  monthlyInstallments[j]['status'] = 'partial';
                  break;
                }
              }
              
              balance -= remainingPayment;
              remainingPayment = 0;
              // No increment for installmentsPaid since this is a partial payment
              
              debugPrint('Partially paid pending month: $month, new amount due: $newAmountPayable');
            }
          }
          
          // If there's still remaining payment and no more pending installments
          if (remainingPayment > 0) {
            balance -= remainingPayment;
            debugPrint('Additional balance reduction: $remainingPayment');
            remainingPayment = 0;
          }
        }

        // If balance becomes zero or negative, mark everything as paid
        if (balance <= 0) {
          // Count remaining unpaid installments first
          int unpaidInstallments = 0;
          for (int i = 0; i < arrears.length; i++) {
            if (arrears[i]['status'] != 'paid') {
              unpaidInstallments++;
            }
          }
          
          balance = 0;
          remainingInstallments = 0;
          installmentsPaid = totalInstallments;
          installmentsProcessedInThisPayment += unpaidInstallments;

          // Mark all remaining arrears as paid
          for (int i = 0; i < arrears.length; i++) {
            if (arrears[i]['status'] != 'paid') {
              arrears[i]['status'] = 'paid';
              arrears[i]['amountPayable'] = 0;

              String month = arrears[i]['month'];
              for (int j = 0; j < monthlyInstallments.length; j++) {
                if (monthlyInstallments[j]['month'] == month) {
                  monthlyInstallments[j]['status'] = 'paid';
                  monthlyInstallments[j]['paymentDate'] = paymentDate;
                  
                  // Use the original amount for the payment amount
                  if (arrears[i].containsKey('originalAmount')) {
                    monthlyInstallments[j]['amountPaid'] = arrears[i]['originalAmount'];
                  }
                  break;
                }
              }
            }
          }

          debugPrint('Balance reduced to zero - loan fully paid off');
        }
      }

      // Update next due date (only if there are remaining installments)
      String newNextDueDate = nextDueDate;
      if (remainingInstallments > 0) {
        bool foundNextDue = false;

        // Sort arrears by billing date to find the next due date
        List<dynamic> sortedArrears = List.from(arrears);
        sortedArrears.sort(
          (a, b) => a['billingDate'].compareTo(b['billingDate']),
        );

        for (var arrear in sortedArrears) {
          if (arrear['status'] == 'due' ||
              arrear['status'] == 'overdue' ||
              arrear['status'] == 'pending' ||
              arrear['status'] == 'partial') {
            newNextDueDate = arrear['billingDate'];

            // Mark as due if it was pending and it's the next one
            if (arrear['status'] == 'pending' && !foundNextDue) {
              for (int i = 0; i < arrears.length; i++) {
                if (arrears[i]['month'] == arrear['month']) {
                  arrears[i]['status'] = 'due';
                  break;
                }
              }
            }

            foundNextDue = true;
            break;
          }
        }

        // If no next due date found (all paid), use the last billing date
        if (!foundNextDue && arrears.isNotEmpty) {
          sortedArrears.sort(
            (a, b) => b['billingDate'].compareTo(a['billingDate']),
          );
          newNextDueDate = sortedArrears.first['billingDate'];
        }
      }

      debugPrint('New balance after payment: $balance');
      debugPrint('Installments paid: $installmentsPaid of $totalInstallments');
      debugPrint('Installments processed in this payment: $installmentsProcessedInThisPayment');
      debugPrint('New next due date: $newNextDueDate');

      // Update Firestore
      await _firestore.collection('installments').doc(accountNumber).update({
        'arrears': arrears,
        'monthlyInstallments': monthlyInstallments,
        'installmentsPaid': installmentsPaid,
        'remainingInstallments': remainingInstallments,
        'balance': balance,
        'nextDueDate': newNextDueDate,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      // Add payment record to payments collection
      await _firestore.collection('payments').add({
        'accountNumber': accountNumber,
        'customerId': _customerData!['customerId'],
        'paymentAmount': paymentAmount,
        'paymentDate': paymentDate,
        'customerName': _customerData!['fullName'],
        'installmentsPaid': installmentsProcessedInThisPayment, // Add count of installments processed
        'paymentType':
            balance <= 0
                ? 'full'
                : (overpayment > 0
                    ? 'advance'
                    : 'regular'),
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Payment successfully recorded');

      // Refresh data
      _searchCustomer(accountNumber);

      // Clear payment amount
      _paymentAmountController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: Text(
                balance <= 0
                    ? 'Loan fully paid off successfully!'
                    : (overpayment > 0 
                        ? 'Payment processed successfully. Excess amount of Rs. ${_currencyFormatter.format(overpayment)} applied to future payments.' 
                        : 'Payment processed successfully'),
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error processing payment: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Container(
              height: 38,
              alignment: Alignment.centerLeft,
              child: Text(
                'Error processing payment: ${e.toString()}',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _paymentAmountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Left Panel - Customer details
          Container(
            width: 350,
            margin: const EdgeInsets.fromLTRB(50, 20, 10, 20),
            child: SingleChildScrollView(
              // Added ScrollView to fix overflow
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    'Pay Bill',
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

          // Right Panel - Payment Processing
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 160, 100, 20),
              child: Form(
                key: _formKey,
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

                    const SizedBox(height: 40),

                    if (_isLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_installmentData != null)
                      _buildPaymentProcessingSection()
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 100),
                          child: Text(
                            'Search for a customer by Account Number, Vehicle Number, Customer ID, or NIC',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        ),
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
        labelText: 'Search Customer',
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

  Widget _buildPaymentProcessingSection() {
    final bool hasOutstandingPayment = _calculateCurrentDue() > 0;
    final bool isLoanFullyPaid = _isLoanFullyPaid();
    final Color primaryColor = Colors.blue;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha((0.08 * 255).toInt()),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with icon
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withAlpha((0.1 * 255).toInt()),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.payments_rounded,
                  size: 28,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 15),
              Text(
                'Process Payment',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: primaryColor,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),

          const SizedBox(height: 30),

          // Main payment card
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white,
                  primaryColor.withAlpha((0.05 * 255).toInt()),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: primaryColor.withAlpha((0.2 * 255).toInt()),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withAlpha((0.1 * 255).toInt()),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                // Total amount section with gorgeous styling
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(25),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        primaryColor.withAlpha((0.7 * 255).toInt()),
                        primaryColor,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            hasOutstandingPayment
                                ? Icons.account_balance_wallet
                                : Icons.check_circle_rounded,
                            color: Colors.white.withAlpha((0.9 * 255).toInt()),
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Total Payable Amount',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withAlpha(
                                (0.9 * 255).toInt(),
                              ),
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'Rs. ${_currencyFormatter.format(_calculateCurrentDue())}',
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (hasOutstandingPayment)
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.15 * 255).toInt()),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Due Date: ${isLoanFullyPaid ? "N/A" : DateFormat('dd MMM yyyy').format(DateFormat('yyyy-MM-dd').parse(_installmentData!['nextDueDate']))}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha((0.2 * 255).toInt()),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                size: 16,
                                color: Colors.white,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'All payments are up to date!',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Payment form section
                Padding(
                  padding: const EdgeInsets.all(25),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Payment amount input with beautiful styling
                      Text(
                        'Enter Payment Amount',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _paymentAmountController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          PaymentAmountFormatter(),
                        ],
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                        decoration: InputDecoration(
                          hintText: 'Rs. 0',
                          prefixIcon: Container(
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: primaryColor.withAlpha(
                                (0.1 * 255).toInt(),
                              ),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(12),
                                bottomLeft: Radius.circular(12),
                              ),
                            ),
                            width: 60,
                            child: Icon(
                              Icons.payments_rounded,
                              color: primaryColor,
                              size: 24,
                            ),
                          ),
                          fillColor: Colors.grey[50],
                          filled: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.grey.withAlpha((0.2 * 255).toInt()),
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: primaryColor.withAlpha(
                                (0.5 * 255).toInt(),
                              ),
                              width: 1.5,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 20,
                            horizontal: 15,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter payment amount';
                          }
                          // Remove commas for validation
                          final cleanValue = value.replaceAll(',', '');
                          final amount = double.tryParse(cleanValue);
                          if (amount == null) {
                            return 'Please enter a valid amount';
                          }
                          if (amount <= 0) {
                            return 'Amount must be greater than zero';
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 30),

                      // Process Payment Button
                      Center(
                        child: SizedBox(
                          width: double.infinity,
                          height: 55,
                          child: ElevatedButton(
                            onPressed:
                                isLoanFullyPaid
                                    ? null
                                    : (_isLoading ? null : _processPayment),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  hasOutstandingPayment
                                      ? primaryColor
                                      : Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              elevation: 4,
                              shadowColor: primaryColor.withAlpha(
                                (0.4 * 255).toInt(),
                              ),
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade700,
                            ),
                            child:
                                _isLoading
                                    ? Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white.withAlpha(
                                                    (0.9 * 255).toInt(),
                                                  ),
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Processing...',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                      ],
                                    )
                                    : Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          isLoanFullyPaid
                                              ? Icons.check_circle
                                              : (hasOutstandingPayment
                                                  ? Icons.check_circle
                                                  : Icons.check_circle),
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          isLoanFullyPaid
                                              ? 'Loan Fully Paid'
                                              : 'Process Payment',
                                        ),
                                      ],
                                    ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Payment Information section
          const SizedBox(height: 30),

          // Payment details section
          Container(
            padding: const EdgeInsets.all(25),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.grey.withAlpha((0.2 * 255).toInt()),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha((0.05 * 255).toInt()),
                  blurRadius: 15,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with icon
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withAlpha((0.1 * 255).toInt()),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.grey[700],
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Payment Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Progress indicator for installments
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Installments Progress',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                        ),
                        Text(
                          '${_installmentData!['installmentsPaid']} of ${_installmentData!['installmentsPaid'] + _installmentData!['remainingInstallments']}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Linear progress indicator - fixed calculation
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value:
                            _installmentData!['installmentsPaid'] /
                            (_installmentData!['installmentsPaid'] +
                                        _installmentData!['remainingInstallments'] >
                                    0
                                ? _installmentData!['installmentsPaid'] +
                                    _installmentData!['remainingInstallments']
                                : 1),
                        minHeight: 10,
                        backgroundColor: Colors.grey.withAlpha(
                          (0.2 * 255).toInt(),
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                      ),
                    ),

                    // Additional payment information details
                    if (!isLoanFullyPaid) ...[
                      const SizedBox(height: 20),

                      // Details row with remaining balance, next due date, maturity date
                      Row(
                        children: [
                          Expanded(
                            child: _buildInfoTile(
                              'Remaining Balance',
                              'Rs. ${_currencyFormatter.format(_installmentData!['balance'])}',
                              Icons.account_balance_wallet,
                              Colors.purple,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _buildInfoTile(
                              'Next Installment Date',
                              DateFormat('dd MMM yyyy').format(
                                DateFormat(
                                  'yyyy-MM-dd',
                                ).parse(_installmentData!['nextDueDate']),
                              ),
                              Icons.calendar_today,
                              Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _buildInfoTile(
                              'Maturity Date',
                              (_financeData!.containsKey('maturityDate') &&
                                      _financeData!['maturityDate'] != null)
                                  ? _financeData!['maturityDate']
                                  : 'N/A',
                              Icons.event_available,
                              Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ],

                    if (isLoanFullyPaid)
                      Padding(
                        padding: const EdgeInsets.only(top: 15),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade400),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.blue.shade800,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Loan fully paid off!',
                                style: TextStyle(
                                  color: Colors.blue.shade800,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withAlpha((0.05 * 255).toInt()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha((0.2 * 255).toInt())),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withAlpha((0.1 * 255).toInt()),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
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
}

// Payment amount formatter
class PaymentAmountFormatter extends TextInputFormatter {
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