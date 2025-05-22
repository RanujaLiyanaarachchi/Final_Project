import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PaymentMessagesService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, StreamSubscription<dynamic>> _listeners = {};

  final Map<String, Map<int, int>> _previousAmountPayable = {};

  final Map<String, Map<int, String>> _previousArrearStatuses = {};

  final Map<String, int> _previousBalances = {};

  final Set<String> _processedMonthlyPayments = {};

  final Set<String> _firstUpdateAccounts = {};

  final Map<String, int> _recentPaymentMessages = {};

  final Map<String, List<Map<String, dynamic>>> _pendingMonthlyInstallments =
      {};

  final Map<String, int> _lastMonthlyMessageTime = {};

  final Map<String, Map<String, int>> _partialMonthlyPayments = {};

  final Set<String> _monthlyCompletionPayments = {};

  final Map<String, List<int>> _batchMonthlyInstallments = {};

  Timer? _periodicCheckTimer;

  Timer? _cleanupTimer;

  static final PaymentMessagesService _instance =
      PaymentMessagesService._internal();

  factory PaymentMessagesService() {
    return _instance;
  }

  PaymentMessagesService._internal();

  Future<void> startMonitoring() async {
    debugPrint('Starting installments monitoring service...');

    try {
      _previousAmountPayable.clear();
      _previousArrearStatuses.clear();
      _previousBalances.clear();
      _firstUpdateAccounts.clear();
      _processedMonthlyPayments.clear();
      _recentPaymentMessages.clear();
      _pendingMonthlyInstallments.clear();
      _lastMonthlyMessageTime.clear();
      _partialMonthlyPayments.clear();
      _monthlyCompletionPayments.clear();
      _batchMonthlyInstallments.clear();

      for (final subscription in _listeners.values) {
        await subscription.cancel();
      }
      _listeners.clear();

      _periodicCheckTimer?.cancel();
      _cleanupTimer?.cancel();

      final installmentDocs = await _firestore.collection('installments').get();

      debugPrint(
        '📋 Found ${installmentDocs.docs.length} installment accounts to monitor',
      );

      for (final doc in installmentDocs.docs) {
        final accountNumber = doc.id;
        await _loadInitialValues(accountNumber);
        _setupAccountMonitoring(accountNumber);
      }

      _monitorNewAccounts();

      _startPeriodicChecks();

      _startCleanupTimer();

      debugPrint('Installment monitoring service started successfully');
    } catch (e) {
      debugPrint('Error starting installment monitoring: $e');
      Future.delayed(const Duration(minutes: 1), startMonitoring);
    }
  }

  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final keysToRemove = <String>[];

      for (final entry in _recentPaymentMessages.entries) {
        if (now - entry.value > 30000) {
          keysToRemove.add(entry.key);
        }
      }

      for (final key in keysToRemove) {
        _recentPaymentMessages.remove(key);
      }

      final completionsToRemove = <String>[];
      for (final key in _monthlyCompletionPayments) {
        if (key.contains('_')) {
          final parts = key.split('_');
          if (parts.length > 1) {
            final timestamp = int.tryParse(parts[1]);
            if (timestamp != null && now - timestamp > 120000) {
              completionsToRemove.add(key);
            }
          }
        }
      }

      for (final key in completionsToRemove) {
        _monthlyCompletionPayments.remove(key);
      }

      final accountsToClean = <String>[];
      for (final entry in _batchMonthlyInstallments.entries) {
        if (_batchMonthlyInstallments[entry.key]!.isEmpty) {
          accountsToClean.add(entry.key);
        }
      }

      for (final key in accountsToClean) {
        _batchMonthlyInstallments.remove(key);
      }

      if (keysToRemove.isNotEmpty ||
          completionsToRemove.isNotEmpty ||
          accountsToClean.isNotEmpty) {
        debugPrint(
          'Cleaned up ${keysToRemove.length} payment entries, ${completionsToRemove.length} completion markers, and ${accountsToClean.length} batch tracking',
        );
      }
    });
  }

  Future<void> _loadInitialValues(String accountNumber) async {
    try {
      final docSnapshot =
          await _firestore.collection('installments').doc(accountNumber).get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        debugPrint('No document found for account: $accountNumber');
        _previousAmountPayable[accountNumber] = {};
        _previousArrearStatuses[accountNumber] = {};
        _previousBalances[accountNumber] = 0;
        return;
      }

      final data = docSnapshot.data()!;
      _previousAmountPayable[accountNumber] = {};
      _previousArrearStatuses[accountNumber] = {};

      final int balance = _parseIntSafely(data['balance']);
      _previousBalances[accountNumber] = balance;

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (int i = 0; i < arrears.length; i++) {
          final arrear = arrears[i];
          if (arrear is Map) {
            if (arrear.containsKey('amountPayable')) {
              final int amount = _parseIntSafely(arrear['amountPayable']);
              _previousAmountPayable[accountNumber]![i] = amount;
            }

            if (arrear.containsKey('status')) {
              final String arrearStatus =
                  arrear['status']?.toString().toLowerCase() ?? '';
              _previousArrearStatuses[accountNumber]![i] = arrearStatus;
              debugPrint(
                'Initial status for $accountNumber arrear[$i]: $arrearStatus',
              );
            }
          }
        }
      }

      _firstUpdateAccounts.add(accountNumber);
    } catch (e) {
      debugPrint(
        '❌ Error loading initial values for account $accountNumber: $e',
      );
      _previousAmountPayable[accountNumber] = {};
      _previousArrearStatuses[accountNumber] = {};
      _previousBalances[accountNumber] = 0;
    }
  }

  void _startPeriodicChecks() {
    _periodicCheckTimer = Timer.periodic(const Duration(hours: 2), (
      timer,
    ) async {
      debugPrint('Running periodic check for missed updates');

      try {
        final installmentDocs =
            await _firestore.collection('installments').get();

        for (final doc in installmentDocs.docs) {
          final accountNumber = doc.id;
          if (!_previousAmountPayable.containsKey(accountNumber)) {
            await _loadInitialValues(accountNumber);
            _setupAccountMonitoring(accountNumber);
          } else {
            _verifyAccountValues(accountNumber, doc.data());
          }
        }
      } catch (e) {
        debugPrint('Error during periodic check: $e');
      }
    });
  }

  void _monitorNewAccounts() {
    try {
      final stream = _firestore.collection('installments').snapshots();

      final subscription = stream.listen(
        (snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final accountNumber = change.doc.id;
              debugPrint('New installment account detected: $accountNumber');
              _loadInitialValues(accountNumber).then((_) {
                _setupAccountMonitoring(accountNumber);
              });
            }
          }
        },
        onError: (error) {
          debugPrint('Error monitoring new accounts: $error');
          Future.delayed(const Duration(seconds: 30), _monitorNewAccounts);
        },
      );

      _listeners['new_accounts'] = subscription;
      debugPrint('Now monitoring for new installment accounts');
    } catch (e) {
      debugPrint('Error setting up new accounts listener: $e');
      Future.delayed(const Duration(seconds: 30), _monitorNewAccounts);
    }
  }

  void _setupAccountMonitoring(String accountNumber) {
    try {
      if (_listeners.containsKey('account_$accountNumber')) {
        _listeners['account_$accountNumber]']?.cancel();
        _listeners.remove('account_$accountNumber');
      }

      if (!_previousAmountPayable.containsKey(accountNumber)) {
        _previousAmountPayable[accountNumber] = {};
      }

      if (!_previousArrearStatuses.containsKey(accountNumber)) {
        _previousArrearStatuses[accountNumber] = {};
      }

      if (!_previousBalances.containsKey(accountNumber)) {
        _previousBalances[accountNumber] = 0;
      }

      final stream =
          _firestore.collection('installments').doc(accountNumber).snapshots();

      final subscription = stream.listen(
        (docSnapshot) {
          if (docSnapshot.exists && docSnapshot.data() != null) {
            final data = docSnapshot.data()!;
            _processInstallmentUpdate(accountNumber, data);
          }
        },
        onError: (error) {
          debugPrint('Error monitoring account $accountNumber: $error');
          Future.delayed(
            const Duration(seconds: 30),
            () => _setupAccountMonitoring(accountNumber),
          );
        },
      );

      _listeners['account_$accountNumber'] = subscription;
      debugPrint('Now monitoring account: $accountNumber');
    } catch (e) {
      debugPrint('Error setting up account monitoring for $accountNumber: $e');
      Future.delayed(
        const Duration(seconds: 30),
        () => _setupAccountMonitoring(accountNumber),
      );
    }
  }

  void _trackMonthlyInstallment(String accountNumber, int amount) {
    if (!_batchMonthlyInstallments.containsKey(accountNumber)) {
      _batchMonthlyInstallments[accountNumber] = [];
    }

    _batchMonthlyInstallments[accountNumber]!.add(amount);
    debugPrint(
      'Tracked monthly installment amount: Rs. $amount for batch handling',
    );
  }

  bool _wasPaymentRecentlyProcessed(String accountNumber, int amount) {
    final key = '${accountNumber}_$amount';
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_recentPaymentMessages.containsKey(key)) {
      final lastProcessed = _recentPaymentMessages[key]!;

      if (now - lastProcessed < 5000) {
        debugPrint(
          'Skipping duplicate payment: Rs. $amount for account $accountNumber',
        );
        return true;
      }
    }

    _recentPaymentMessages[key] = now;
    return false;
  }

  bool _isMonthlyCompletionPayment(String accountNumber, int amount) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${accountNumber}_${now}_$amount';

    if (_monthlyCompletionPayments.contains(key) ||
        _monthlyCompletionPayments.contains('${accountNumber}_$amount')) {
      debugPrint(
        'Payment of Rs. $amount is flagged as monthly completion payment - skipping Cash Deposit',
      );
      return true;
    }

    return false;
  }

  void _markAsMonthlyCompletionPayment(String accountNumber, int amount) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${accountNumber}_${now}_$amount';
    _monthlyCompletionPayments.add(key);

    _monthlyCompletionPayments.add('${accountNumber}_$amount');

    debugPrint('Marked payment of Rs. $amount as monthly completion payment');
  }

  bool _shouldThrottleMonthlyMessage(String accountNumber) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_lastMonthlyMessageTime.containsKey(accountNumber)) {
      final lastSent = _lastMonthlyMessageTime[accountNumber]!;

      if (now - lastSent < 30000) {
        debugPrint(
          'Throttling monthly message for account $accountNumber - too soon',
        );
        return true;
      }
    }

    return false;
  }

  void _updateMonthlyMessageTimestamp(String accountNumber) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastMonthlyMessageTime[accountNumber] = now;
  }

  bool _updatePartialMonthlyPayment(
    String accountNumber,
    String month,
    int amount,
    int fullAmount,
  ) {
    if (!_partialMonthlyPayments.containsKey(accountNumber)) {
      _partialMonthlyPayments[accountNumber] = {};
    }

    int currentAccumulated =
        _partialMonthlyPayments[accountNumber]![month] ?? 0;
    currentAccumulated += amount;
    _partialMonthlyPayments[accountNumber]![month] = currentAccumulated;

    debugPrint(
      'Updated partial payment for $accountNumber, month $month: $currentAccumulated/$fullAmount',
    );

    if (currentAccumulated >= fullAmount) {
      debugPrint('Monthly payment completed for $accountNumber, month $month');
      _partialMonthlyPayments[accountNumber]!.remove(month);

      if (currentAccumulated > fullAmount) {
        debugPrint(
          'Payment exceeds monthly amount - will only send Cash Deposit for total amount',
        );
        return false;
      }

      if (amount > 0 && amount == fullAmount) {
        _markAsMonthlyCompletionPayment(accountNumber, amount);
      }

      return true;
    }

    return false;
  }

  List<Map<String, dynamic>> _processStatusChanges(
    String accountNumber,
    Map<String, dynamic> data,
    int decreaseAmount,
  ) {
    List<Map<String, dynamic>> newlyPaidMonths = [];
    int totalMonthlyAmount = 0;

    if (data.containsKey('arrears') && data['arrears'] is List) {
      final List<dynamic> arrears = data['arrears'] as List<dynamic>;

      for (int i = 0; i < arrears.length; i++) {
        if (arrears[i] is Map) {
          final Map<String, dynamic> arrear = Map<String, dynamic>.from(
            arrears[i],
          );

          if (arrear.containsKey('status')) {
            final String currentArrearStatus =
                arrear['status']?.toString().toLowerCase() ?? '';
            final String previousArrearStatus =
                _previousArrearStatuses[accountNumber]?[i] ?? '';

            if (currentArrearStatus == 'paid' &&
                previousArrearStatus != 'paid') {
              if (arrear.containsKey('month')) {
                String month = arrear['month']?.toString() ?? '';
                if (month.isNotEmpty) {
                  final key = _getMonthlyPaymentKey(
                    accountNumber,
                    data,
                    arrearIndex: i,
                  );

                  if (!_processedMonthlyPayments.contains(key)) {
                    String formattedMonth = _formatMonth(month);
                    int monthlyAmount = _parseIntSafely(
                      arrear['originalAmount'] ??
                          arrear['standardAmount'] ??
                          arrear['amountPayable'],
                    );

                    newlyPaidMonths.add({
                      'month': formattedMonth,
                      'amount': monthlyAmount,
                      'originalMonth': month,
                      'arrearIndex': i,
                    });

                    totalMonthlyAmount += monthlyAmount;
                    _processedMonthlyPayments.add(key);
                  }
                }
              }
            }

            _previousArrearStatuses[accountNumber]![i] = currentArrearStatus;
          }
        }
      }
    }

    if (decreaseAmount > totalMonthlyAmount && totalMonthlyAmount > 0) {
      debugPrint(
        'Excess payment detected: Rs. $decreaseAmount > Rs. $totalMonthlyAmount - sending both Cash Deposit and Monthly Installment',
      );

      for (final monthData in newlyPaidMonths) {
        _markAsMonthlyCompletionPayment(
          accountNumber,
          monthData['amount'] as int,
        );
      }
    }

    return newlyPaidMonths;
  }

  void _verifyAccountValues(String accountNumber, Map<String, dynamic> data) {
    try {
      final int currentBalance = _parseIntSafely(data['balance']);
      final int previousBalance =
          _previousBalances[accountNumber] ?? currentBalance;

      bool paymentProcessed = false;

      if (previousBalance > 0 && currentBalance == 0) {
        final int finalPayment = previousBalance;

        if (finalPayment > 0) {
          _processPayment(accountNumber, data, finalPayment);
          debugPrint(
            'Final payment Cash Deposit message sent: Rs. $finalPayment for account $accountNumber (before finance completion)',
          );
        }

        _processFinanceCompleted(accountNumber, data);
        paymentProcessed = true;

        _previousBalances[accountNumber] = currentBalance;
        return;
      }

      if (previousBalance > currentBalance) {
        final int decreaseAmount = previousBalance - currentBalance;

        List<Map<String, dynamic>> newlyPaidMonths = _processStatusChanges(
          accountNumber,
          data,
          decreaseAmount,
        );

        if (newlyPaidMonths.length > 1) {
          int totalMonthlyAmount = 0;
          for (final month in newlyPaidMonths) {
            totalMonthlyAmount += (month['amount'] as int);
          }

          if (!_wasPaymentRecentlyProcessed(accountNumber, decreaseAmount)) {
            _processPayment(accountNumber, data, decreaseAmount);

            for (final monthData in newlyPaidMonths) {
              _markAsMonthlyCompletionPayment(
                accountNumber,
                monthData['amount'] as int,
              );
            }
            _markAsMonthlyCompletionPayment(accountNumber, decreaseAmount);

            if (decreaseAmount != totalMonthlyAmount) {
              newlyPaidMonths.clear();
            }
          }

          paymentProcessed = true;
        } else if (!paymentProcessed &&
            !_isMonthlyCompletionPayment(accountNumber, decreaseAmount) &&
            !_wasPaymentRecentlyProcessed(accountNumber, decreaseAmount)) {
          _processPayment(accountNumber, data, decreaseAmount);

          _checkForMonthlyInstallmentPayment(
            accountNumber,
            data,
            decreaseAmount,
          );

          paymentProcessed = true;
        }

        _previousBalances[accountNumber] = currentBalance;

        if (newlyPaidMonths.isNotEmpty) {
          if (!_shouldThrottleMonthlyMessage(accountNumber)) {
            _processMonthlyInstallmentNotifications(
              accountNumber,
              data,
              newlyPaidMonths,
            );
          } else {
            if (!_pendingMonthlyInstallments.containsKey(accountNumber)) {
              _pendingMonthlyInstallments[accountNumber] = [];
            }
            _pendingMonthlyInstallments[accountNumber]!.addAll(newlyPaidMonths);
            debugPrint(
              'Added ${newlyPaidMonths.length} month(s) to pending batch for account $accountNumber (throttled)',
            );
          }
        }
      }

      if (!paymentProcessed &&
          data.containsKey('arrears') &&
          data['arrears'] is List) {}

      if (!_shouldThrottleMonthlyMessage(accountNumber) &&
          _pendingMonthlyInstallments.containsKey(accountNumber) &&
          _pendingMonthlyInstallments[accountNumber]!.isNotEmpty) {}
    } catch (e) {
      debugPrint('Error verifying account values for $accountNumber: $e');
    }
  }

  void _checkForMonthlyInstallmentPayment(
    String accountNumber,
    Map<String, dynamic> data,
    int amount, {
    Map<String, dynamic>? monthInfo,
  }) {
    try {
      if (monthInfo != null && monthInfo.containsKey('month')) {
        String month = monthInfo['month']?.toString() ?? '';
        if (month.isNotEmpty) {
          int fullAmount = _parseIntSafely(
            monthInfo['originalAmount'] ??
                monthInfo['standardAmount'] ??
                monthInfo['amount'] ??
                0,
          );

          if (fullAmount > 0) {
            if (amount > fullAmount) {
              debugPrint(
                'Excess payment detected: Rs. $amount > Rs. $fullAmount - will only send Cash Deposit for total',
              );

              _markAsMonthlyCompletionPayment(accountNumber, amount);
              _markAsMonthlyCompletionPayment(accountNumber, fullAmount);

              _createPaymentRecord(
                accountNumber: accountNumber,
                customerId: data['customerId']?.toString() ?? '',
                customerName: data['customerName']?.toString() ?? '',
                amount: amount,
                paymentType: "excess_payment",
              );

              return;
            }

            bool isComplete = _updatePartialMonthlyPayment(
              accountNumber,
              month,
              amount,
              fullAmount,
            );

            _createPaymentRecord(
              accountNumber: accountNumber,
              customerId: data['customerId']?.toString() ?? '',
              customerName: data['customerName']?.toString() ?? '',
              amount: amount,
              paymentType: isComplete ? "monthly_completed" : "partial_monthly",
            );

            if (isComplete && amount == fullAmount) {
              _markAsMonthlyCompletionPayment(accountNumber, amount);

              String formattedMonth = _formatMonth(month);
              Map<String, dynamic> monthData = {
                'month': formattedMonth,
                'amount': fullAmount,
                'originalMonth': month,
              };

              if (!_shouldThrottleMonthlyMessage(accountNumber)) {
                _processMonthlyInstallmentNotifications(accountNumber, data, [
                  monthData,
                ]);
              } else {
                if (!_pendingMonthlyInstallments.containsKey(accountNumber)) {
                  _pendingMonthlyInstallments[accountNumber] = [];
                }
                _pendingMonthlyInstallments[accountNumber]!.add(monthData);
              }
            }

            debugPrint(
              'Tracked payment of Rs. $amount for monthly installment (${isComplete ? "completed" : "partial"})',
            );
            return;
          }
        }
      }

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is Map &&
              arrear.containsKey('month') &&
              arrear.containsKey('status')) {
            final String status =
                arrear['status']?.toString().toLowerCase() ?? '';

            if (status != 'paid') {
              String month = arrear['month']?.toString() ?? '';
              if (month.isNotEmpty) {
                int fullAmount = _parseIntSafely(
                  arrear['originalAmount'] ??
                      arrear['standardAmount'] ??
                      arrear['amount'] ??
                      0,
                );

                if (fullAmount > 0) {
                  if (amount > fullAmount) {
                    debugPrint(
                      'Excess payment detected: Rs. $amount > Rs. $fullAmount - will only send Cash Deposit for total',
                    );

                    _markAsMonthlyCompletionPayment(accountNumber, amount);
                    _markAsMonthlyCompletionPayment(accountNumber, fullAmount);

                    _createPaymentRecord(
                      accountNumber: accountNumber,
                      customerId: data['customerId']?.toString() ?? '',
                      customerName: data['customerName']?.toString() ?? '',
                      amount: amount,
                      paymentType: "excess_payment",
                    );

                    return;
                  }

                  bool isComplete = _updatePartialMonthlyPayment(
                    accountNumber,
                    month,
                    amount,
                    fullAmount,
                  );

                  _createPaymentRecord(
                    accountNumber: accountNumber,
                    customerId: data['customerId']?.toString() ?? '',
                    customerName: data['customerName']?.toString() ?? '',
                    amount: amount,
                    paymentType:
                        isComplete ? "monthly_completed" : "partial_monthly",
                  );

                  if (isComplete && amount == fullAmount) {
                    _markAsMonthlyCompletionPayment(accountNumber, amount);

                    String formattedMonth = _formatMonth(month);
                    Map<String, dynamic> monthData = {
                      'month': formattedMonth,
                      'amount': fullAmount,
                      'originalMonth': month,
                    };

                    if (!_shouldThrottleMonthlyMessage(accountNumber)) {
                      _processMonthlyInstallmentNotifications(
                        accountNumber,
                        data,
                        [monthData],
                      );
                    } else {
                      if (!_pendingMonthlyInstallments.containsKey(
                        accountNumber,
                      )) {
                        _pendingMonthlyInstallments[accountNumber] = [];
                      }
                      _pendingMonthlyInstallments[accountNumber]!.add(
                        monthData,
                      );
                    }
                  }

                  debugPrint(
                    'Tracked payment of Rs. $amount for monthly installment (${isComplete ? "completed" : "partial"})',
                  );
                  return;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking for monthly installment payment: $e');
    }
  }

  void _processInstallmentUpdate(
    String accountNumber,
    Map<String, dynamic> data,
  ) {
    try {
      bool isFirstUpdate = _firstUpdateAccounts.contains(accountNumber);

      final int currentBalance = _parseIntSafely(data['balance']);

      if (isFirstUpdate) {
        debugPrint(
          'First update for account $accountNumber - recording values only',
        );
        _previousBalances[accountNumber] = currentBalance;

        if (data.containsKey('arrears') && data['arrears'] is List) {
          final List<dynamic> arrears = data['arrears'] as List<dynamic>;

          for (int i = 0; i < arrears.length; i++) {
            if (arrears[i] is Map) {
              final Map<String, dynamic> arrear = Map<String, dynamic>.from(
                arrears[i],
              );
              if (arrear.containsKey('amountPayable')) {
                _previousAmountPayable[accountNumber]![i] = _parseIntSafely(
                  arrear['amountPayable'],
                );
              }
              if (arrear.containsKey('status')) {
                _previousArrearStatuses[accountNumber]![i] =
                    arrear['status']?.toString().toLowerCase() ?? '';
              }
            }
          }
        }

        _firstUpdateAccounts.remove(accountNumber);
        return;
      }

      _verifyAccountValues(accountNumber, data);
    } catch (e) {
      debugPrint('Error processing installment update for $accountNumber: $e');
    }
  }

  String _getMonthlyPaymentKey(
    String accountNumber,
    Map<String, dynamic> data, {
    int? arrearIndex,
  }) {
    String month = '';

    if (arrearIndex != null &&
        data.containsKey('arrears') &&
        data['arrears'] is List) {
      final List<dynamic> arrears = data['arrears'] as List<dynamic>;
      if (arrearIndex < arrears.length && arrears[arrearIndex] is Map) {
        final arrear = arrears[arrearIndex] as Map<String, dynamic>;
        if (arrear.containsKey('month')) {
          month = arrear['month']?.toString() ?? '';
        }
      }
    }

    if (month.isEmpty) {
      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;
        for (final arrear in arrears) {
          if (arrear is Map && arrear.containsKey('month')) {
            month = arrear['month']?.toString() ?? '';
            if (month.isNotEmpty) break;
          }
        }
      }

      if (month.isEmpty && data.containsKey('month')) {
        month = data['month']?.toString() ?? '';
      }

      if (month.isEmpty) {
        final now = DateTime.now();
        month = '${now.year}-${_twoDigits(now.month)}';
      }
    }

    if (arrearIndex != null) {
      return '$accountNumber-$month-$arrearIndex';
    } else {
      return '$accountNumber-$month';
    }
  }

  Future<void> _processMonthlyInstallmentNotifications(
    String accountNumber,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> monthsData,
  ) async {
    try {
      debugPrint(
        'Processing monthly installment notifications for account $accountNumber',
      );

      if (_parseIntSafely(data['balance']) == 0) {
        debugPrint('Skip monthly installment message - finance is completed');
        return;
      }

      // Skip if no months data
      if (monthsData.isEmpty) {
        debugPrint('Skip monthly installment message - no months data');
        return;
      }

      _updateMonthlyMessageTimestamp(accountNumber);

      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      List<String> months = [];

      for (final monthData in monthsData) {
        months.add(monthData['month'] as String);

        final int monthlyAmount = monthData['amount'] as int;

        _markAsMonthlyCompletionPayment(accountNumber, monthlyAmount);

        await _createPaymentRecord(
          accountNumber: accountNumber,
          customerId: customerId,
          customerName: await _getCustomerName(customerId, customerName),
          amount: monthlyAmount,
          paymentType: "monthly_completed",
        );
      }

      months.sort();

      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'monthly_${accountNumber}_$timestamp';

      String heading = "Monthly Installment";
      String message;

      if (months.length == 1) {
        message =
            "You have successfully paid the relevant installment for ${months.first}. \n\nThank you for your prompt payment. Your account has been updated accordingly. - Unicon Finance.";
      } else {
        message =
            "You have successfully paid the relevant installments for the following months:\n";

        for (final month in months) {
          message += "\n• $month";
        }
        message +=
            "\n\nThank you for your prompt payment. Your account has been updated accordingly. - Unicon Finance.";
      }

      debugPrint('Creating monthly installment message: $heading');

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: heading,
        message: message,
        messageId: messageId,
      );

      debugPrint(
        'Monthly installment notification sent for account $accountNumber: ${months.length} month(s)',
      );
    } catch (e) {
      debugPrint('Error processing monthly installment notifications: $e');
    }
  }

  Future<void> _processPayment(
    String accountNumber,
    Map<String, dynamic> data,
    int paymentAmount,
  ) async {
    try {
      if (paymentAmount <= 0) {
        return;
      }

      if (_isMonthlyCompletionPayment(accountNumber, paymentAmount)) {
        debugPrint(
          'Skipping Cash Deposit message for monthly completion payment: Rs. $paymentAmount',
        );
        return;
      }

      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      String maskedAccountNumber = _maskAccountNumber(accountNumber);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'payment_${accountNumber}_${timestamp}_$paymentAmount';

      String heading = "Cash Deposit";
      String message =
          "Cash deposit of Rs. $paymentAmount has been credited to A/C No. $maskedAccountNumber. "
          "Your account has been successfully updated. "
          "Thank you for choosing Unicon Finance.";

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: heading,
        message: message,
        messageId: messageId,
      );

      await _createPaymentRecord(
        accountNumber: accountNumber,
        customerId: customerId,
        customerName: finalCustomerName,
        amount: paymentAmount,
        paymentType: "regular",
      );

      debugPrint(
        'Cash Deposit message sent: Rs. $paymentAmount for account $accountNumber',
      );
    } catch (e) {
      debugPrint('Error processing payment: $e');
    }
  }

  Future<void> _processFinanceCompleted(
    String accountNumber,
    Map<String, dynamic> data,
  ) async {
    try {
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      String maskedAccountNumber = _maskAccountNumber(accountNumber);

      int finalPayment = 0;

      if (_previousBalances.containsKey(accountNumber)) {
        finalPayment = _previousBalances[accountNumber] ?? 0;
      }

      if (finalPayment == 0) {
        if (data.containsKey('finalPayment')) {
          finalPayment = _parseIntSafely(data['finalPayment']);
        } else if (data.containsKey('lastPaymentAmount')) {
          finalPayment = _parseIntSafely(data['lastPaymentAmount']);
        }
      }

      if (finalPayment > 0) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String paymentMessageId =
            'payment_${accountNumber}_${timestamp}_$finalPayment';

        String paymentHeading = "Cash Deposit";
        String paymentMessage =
            "Cash deposit of Rs. $finalPayment has been credited to A/C No. $maskedAccountNumber. "
            "Your account has been successfully updated. "
            "Thank you for choosing Unicon Finance.";

        await _createMessage(
          customerId: customerId,
          customerName: finalCustomerName,
          customerNic: customerNic,
          heading: paymentHeading,
          message: paymentMessage,
          messageId: paymentMessageId,
        );

        await _createPaymentRecord(
          accountNumber: accountNumber,
          customerId: customerId,
          customerName: finalCustomerName,
          amount: finalPayment,
          paymentType: "final",
        );

        debugPrint(
          'Final payment Cash Deposit message sent: Rs. $finalPayment for account $accountNumber',
        );
      } else {
        debugPrint(
          'Warning: Could not determine final payment amount for account $accountNumber',
        );
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'completed_${accountNumber}_$timestamp';

      String heading = "Finance Fully Settled";
      String message =
          "We are pleased to inform you that your finance is complete. You have successfully paid all outstanding installments for A/C No. $maskedAccountNumber.\n\n"
          "Thank you for your timely payments and for choosing Unicon Finance.";

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: heading,
        message: message,
        messageId: messageId,
      );

      debugPrint('Finance completed message sent for account $accountNumber');
    } catch (e) {
      debugPrint('Error processing finance completion: $e');
    }
  }

  Future<void> _createPaymentRecord({
    required String accountNumber,
    required String customerId,
    required String customerName,
    required int amount,
    required String paymentType,
  }) async {
    try {
      final dateFormatted = _getCurrentFormattedDate();

      final paymentData = {
        'accountNumber': accountNumber,
        'customerId': customerId,
        'customerName': customerName,
        'paymentAmount': amount,
        'paymentDate': dateFormatted,
        'paymentType': paymentType,
        'createdAt': FieldValue.serverTimestamp(),
      };

      await _firestore.collection('payments').add(paymentData);
      debugPrint(
        'Payment record created: Rs. $amount for account $accountNumber (type: $paymentType)',
      );
    } catch (e) {
      debugPrint('Error creating payment record: $e');
    }
  }

  String _formatMonth(String monthStr) {
    try {
      final parts = monthStr.split('-');
      if (parts.length == 2) {
        final year = parts[0];
        final monthNum = int.parse(parts[1]);
        final monthName = _getMonthName(monthNum);
        return "$monthName $year";
      }
    } catch (e) {
      debugPrint('Error parsing month: $monthStr');
    }
    return monthStr;
  }

  Future<String> _getCustomerName(
    String customerId,
    String customerName,
  ) async {
    if (!customerId.isNotEmpty || customerName.isNotEmpty) {
      return customerName.isEmpty ? 'Customer' : customerName;
    }

    try {
      final customerDoc =
          await _firestore.collection('customers').doc(customerId).get();
      if (customerDoc.exists && customerDoc.data() != null) {
        final customerData = customerDoc.data()!;
        return customerData['fullName']?.toString() ??
            customerData['customerName']?.toString() ??
            'Customer';
      }
    } catch (e) {
      debugPrint('Error fetching customer details: $e');
    }

    return 'Customer';
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length > 4) {
      return 'XXXXXX${accountNumber.substring(accountNumber.length - 4)}';
    }
    return accountNumber;
  }

  Future<void> _createMessage({
    required String customerId,
    required String customerName,
    required String customerNic,
    required String heading,
    required String message,
    required String messageId,
  }) async {
    int retries = 0;
    const maxRetries = 3;

    while (retries < maxRetries) {
      try {
        debugPrint('Creating message: $heading (attempt ${retries + 1})');

        final dateFormatted = _getCurrentFormattedDate();
        final timeFormatted = _getCurrentFormattedTime();

        final messageData = {
          'customerId': customerId,
          'customerName': customerName,
          'customerNic': customerNic,
          'heading': heading,
          'message': message,
          'date': dateFormatted,
          'time': timeFormatted,
          'senderId': 'Unicon Finance',
          'isRead': false,
          'sentToAll': false,
          'createdAt': FieldValue.serverTimestamp(),
          'delivered': true,
          'deliveredAt': FieldValue.serverTimestamp(),
          'deliveryMethod': 'background_service',
          'attachments': [],
          'messageId': messageId,
        };

        await _firestore.collection('messages').add(messageData);
        debugPrint('Message sent successfully: $heading');

        return;
      } catch (e) {
        retries++;
        debugPrint('Error creating message (attempt $retries): $e');

        if (retries < maxRetries) {
          await Future.delayed(Duration(seconds: retries * 2));
        }
      }
    }

    debugPrint('Failed to create message after $maxRetries attempts');
  }

  String _getCurrentFormattedDate() {
    final now = DateTime.now();
    return "${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}";
  }

  String _getCurrentFormattedTime() {
    final now = DateTime.now();
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    return "${_twoDigits(hour)}:${_twoDigits(now.minute)} $amPm";
  }

  String _getMonthName(int month) {
    final monthNames = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];

    if (month >= 1 && month <= 12) {
      return monthNames[month - 1];
    }
    return monthNames[DateTime.now().month - 1];
  }

  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }

  void resetProcessedPayments() {
    _processedMonthlyPayments.clear();
    _recentPaymentMessages.clear();
    _pendingMonthlyInstallments.clear();
    _lastMonthlyMessageTime.clear();
    _partialMonthlyPayments.clear();
    _monthlyCompletionPayments.clear();
    _batchMonthlyInstallments.clear();
    debugPrint('Payment tracking has been reset');
  }

  void dispose() {
    _periodicCheckTimer?.cancel();
    _cleanupTimer?.cancel();

    for (final subscription in _listeners.values) {
      subscription.cancel();
    }

    _listeners.clear();
    _previousAmountPayable.clear();
    _previousArrearStatuses.clear();
    _previousBalances.clear();
    _firstUpdateAccounts.clear();
    _processedMonthlyPayments.clear();
    _recentPaymentMessages.clear();
    _pendingMonthlyInstallments.clear();
    _lastMonthlyMessageTime.clear();
    _partialMonthlyPayments.clear();
    _monthlyCompletionPayments.clear();
    _batchMonthlyInstallments.clear();

    debugPrint('Payment messages service disposed');
  }
}

class PaymentMessagesInitializer {
  static bool _isInitialized = false;
  static PaymentMessagesService? _service;

  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('Payment messages service already initialized');
      return;
    }

    try {
      debugPrint('Initializing payment messages service');

      await Future.delayed(Duration(seconds: 2));

      try {
        final testRead =
            await FirebaseFirestore.instance
                .collection('installments')
                .limit(1)
                .get();
        debugPrint(
          'Firebase read test successful: ${testRead.docs.length} documents',
        );

        await FirebaseFirestore.instance.collection('messages').limit(1).get();
        debugPrint('Firebase messages collection access verified');
      } catch (e) {
        debugPrint('Firebase permission test failed: $e');
      }

      _service = PaymentMessagesService();
      await _service!.startMonitoring();
      _isInitialized = true;

      _setupAutoRestart();

      debugPrint('Payment messages service initialized successfully');
    } catch (e) {
      debugPrint('Error initializing payment messages service: $e');
      Future.delayed(const Duration(seconds: 30), initialize);
    }
  }

  static void _setupAutoRestart() {
    Timer.periodic(const Duration(hours: 6), (timer) {
      if (!_isInitialized || _service == null) {
        debugPrint('Service not running, restarting...');
        initialize();
      }

      _service?.resetProcessedPayments();
    });
  }

  static Future<bool> sendTestPaymentMessage(String accountNumber) async {
    try {
      if (_service == null) {
        await initialize();
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('installments')
              .doc(accountNumber)
              .get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountNumber not found');
        return false;
      }

      await _service!._processPayment(accountNumber, doc.data()!, 1000);
      debugPrint('Test payment message sent for account $accountNumber');
      return true;
    } catch (e) {
      debugPrint('Error sending test payment message: $e');
      return false;
    }
  }

  static Future<bool> sendTestMonthlyInstallmentMessage(
    String accountNumber,
  ) async {
    try {
      if (_service == null) {
        await initialize();
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('installments')
              .doc(accountNumber)
              .get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountNumber not found');
        return false;
      }

      final testMonths = [
        {'month': 'January 2025', 'amount': 5000, 'originalMonth': '2025-01'},
      ];

      await _service!._processMonthlyInstallmentNotifications(
        accountNumber,
        doc.data()!,
        testMonths.map((m) => Map<String, dynamic>.from(m)).toList(),
      );
      debugPrint(
        'Test monthly installment message sent for account $accountNumber',
      );
      return true;
    } catch (e) {
      debugPrint('Error sending test monthly installment message: $e');
      return false;
    }
  }

  static Future<bool> testPartialMonthlyPayments(String accountNumber) async {
    try {
      if (_service == null) {
        await initialize();
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('installments')
              .doc(accountNumber)
              .get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountNumber not found');
        return false;
      }

      final String testMonth = '2025-05';
      final int fullAmount = 5000;

      await _service!._processPayment(accountNumber, doc.data()!, 1000);

      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        1000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      await _service!._processPayment(accountNumber, doc.data()!, 2000);

      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        2000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        2000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      debugPrint('Test partial payments processed for account $accountNumber');
      return true;
    } catch (e) {
      debugPrint('Error testing partial payments: $e');
      return false;
    }
  }

  static Future<bool> testMultipleMonthlyInstallments(
    String accountNumber,
  ) async {
    try {
      if (_service == null) {
        await initialize();
      }

      final doc =
          await FirebaseFirestore.instance
              .collection('installments')
              .doc(accountNumber)
              .get();

      if (!doc.exists || doc.data() == null) {
        debugPrint('❌ Account $accountNumber not found');
        return false;
      }

      final months = [
        {'month': '2025-01', 'amount': 5000},
        {'month': '2025-02', 'amount': 5000},
      ];

      for (final month in months) {
        _service!._trackMonthlyInstallment(
          accountNumber,
          month['amount'] as int,
        );
        _service!._markAsMonthlyCompletionPayment(
          accountNumber,
          month['amount'] as int,
        );
      }

      await _service!._processPayment(accountNumber, doc.data()!, 10000);

      final monthsData =
          months
              .map(
                (m) => {
                  'month': _service!._formatMonth(m['month'] as String),
                  'amount': m['amount'] as int,
                  'originalMonth': m['month'] as String,
                },
              )
              .toList();

      await _service!._processMonthlyInstallmentNotifications(
        accountNumber,
        doc.data()!,
        monthsData,
      );

      debugPrint(
        'Test multiple monthly installments processed for account $accountNumber',
      );
      return true;
    } catch (e) {
      debugPrint('Error testing multiple monthly installments: $e');
      return false;
    }
  }

  static void dispose() {
    _service?.dispose();
    _service = null;
    _isInitialized = false;
    debugPrint('Payment messages service disposed');
  }
}
