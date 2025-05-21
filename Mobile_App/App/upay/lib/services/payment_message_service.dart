import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Streamlined service that monitors the installments collection for payment changes
/// and sends notification messages for Finance Completed, Monthly Installment, and Cash Deposit
class PaymentMessagesService {
  // Firestore instance
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Keep reference to listeners to prevent garbage collection
  final Map<String, StreamSubscription<dynamic>> _listeners = {};

  // Track previous amount payable values for each account and arrear index
  final Map<String, Map<int, int>> _previousAmountPayable = {};

  // Track previous status values for each arrear index
  final Map<String, Map<int, String>> _previousArrearStatuses = {};

  // Track previous balance values for each account
  final Map<String, int> _previousBalances = {};

  // Track processed monthly payments to avoid duplicates
  final Set<String> _processedMonthlyPayments = {};

  // Track the first update flag for accounts to avoid false notifications
  final Set<String> _firstUpdateAccounts = {};

  // Track recently sent payment messages to avoid duplicates in rapid updates
  final Map<String, int> _recentPaymentMessages = {};

  // Track pending monthly installments that need to be batched
  final Map<String, List<Map<String, dynamic>>> _pendingMonthlyInstallments =
      {};

  // Track last monthly installment message timestamp to prevent spam
  final Map<String, int> _lastMonthlyMessageTime = {};

  // Track accumulated payments for partial monthly installments
  final Map<String, Map<String, int>> _partialMonthlyPayments = {};

  // Track payments that are part of monthly installment completion
  // to avoid sending separate Cash Deposit messages for them
  final Set<String> _monthlyCompletionPayments = {};

  // Track multiple monthly installments paid in one transaction
  final Map<String, List<int>> _batchMonthlyInstallments = {};

  // Timer for periodic checks
  Timer? _periodicCheckTimer;

  // Timer to clean up old payment tracking
  Timer? _cleanupTimer;

  // Singleton pattern
  static final PaymentMessagesService _instance =
      PaymentMessagesService._internal();

  factory PaymentMessagesService() {
    return _instance;
  }

  PaymentMessagesService._internal();

  /// Start monitoring the installments collection
  Future<void> startMonitoring() async {
    debugPrint('🚀 Starting installments monitoring service...');

    try {
      // Clear existing state
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

      // Cancel existing listeners
      for (final subscription in _listeners.values) {
        await subscription.cancel();
      }
      _listeners.clear();

      // Cancel existing timers
      _periodicCheckTimer?.cancel();
      _cleanupTimer?.cancel();

      // Get all installment accounts to monitor
      final installmentDocs = await _firestore.collection('installments').get();

      debugPrint(
        '📋 Found ${installmentDocs.docs.length} installment accounts to monitor',
      );

      // Setup monitoring for each account
      for (final doc in installmentDocs.docs) {
        final accountNumber = doc.id;
        await _loadInitialValues(accountNumber);
        _setupAccountMonitoring(accountNumber);
      }

      // Monitor for new accounts being added
      _monitorNewAccounts();

      // Set up periodic checks for resilience
      _startPeriodicChecks();

      // Set up cleanup timer for recent payment tracking
      _startCleanupTimer();

      debugPrint('✅ Installment monitoring service started successfully');
    } catch (e) {
      debugPrint('❌ Error starting installment monitoring: $e');
      // Try again after delay
      Future.delayed(const Duration(minutes: 1), startMonitoring);
    }
  }

  /// Start cleanup timer to remove old payment tracking entries
  void _startCleanupTimer() {
    // Clean up recent payment messages tracking every minute
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final keysToRemove = <String>[];

      // Find old entries (older than 30 seconds)
      for (final entry in _recentPaymentMessages.entries) {
        if (now - entry.value > 30000) {
          // 30 seconds
          keysToRemove.add(entry.key);
        }
      }

      // Remove old entries
      for (final key in keysToRemove) {
        _recentPaymentMessages.remove(key);
      }

      // Also clean up monthly completion payments that are older than 2 minutes
      final completionsToRemove = <String>[];
      for (final key in _monthlyCompletionPayments) {
        if (key.contains('_')) {
          final parts = key.split('_');
          if (parts.length > 1) {
            final timestamp = int.tryParse(parts[1]);
            if (timestamp != null && now - timestamp > 120000) {
              // 2 minutes
              completionsToRemove.add(key);
            }
          }
        }
      }

      for (final key in completionsToRemove) {
        _monthlyCompletionPayments.remove(key);
      }

      // Clean up batch monthly installments older than 2 minutes
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
          '🧹 Cleaned up ${keysToRemove.length} payment entries, ${completionsToRemove.length} completion markers, and ${accountsToClean.length} batch tracking',
        );
      }
    });
  }

  /// Load initial values for an account to establish baseline
  Future<void> _loadInitialValues(String accountNumber) async {
    try {
      final docSnapshot =
          await _firestore.collection('installments').doc(accountNumber).get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        debugPrint('⚠️ No document found for account: $accountNumber');
        _previousAmountPayable[accountNumber] = {};
        _previousArrearStatuses[accountNumber] = {};
        _previousBalances[accountNumber] = 0;
        return;
      }

      final data = docSnapshot.data()!;
      _previousAmountPayable[accountNumber] = {};
      _previousArrearStatuses[accountNumber] = {};

      // Store the initial balance value
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

            // Track the status of each arrear item if available
            if (arrear.containsKey('status')) {
              final String arrearStatus =
                  arrear['status']?.toString().toLowerCase() ?? '';
              _previousArrearStatuses[accountNumber]![i] = arrearStatus;
              debugPrint(
                '📊 Initial status for $accountNumber arrear[$i]: $arrearStatus',
              );
            }
          }
        }
      }

      // Mark this account as needing first update handling
      _firstUpdateAccounts.add(accountNumber);
    } catch (e) {
      debugPrint(
        '❌ Error loading initial values for account $accountNumber: $e',
      );
      // Initialize with empty map to avoid null errors
      _previousAmountPayable[accountNumber] = {};
      _previousArrearStatuses[accountNumber] = {};
      _previousBalances[accountNumber] = 0;
    }
  }

  /// Start periodic checks for missed updates
  void _startPeriodicChecks() {
    // Check every 2 hours for missed updates
    _periodicCheckTimer = Timer.periodic(const Duration(hours: 2), (
      timer,
    ) async {
      debugPrint('🔄 Running periodic check for missed updates');

      try {
        // Reload all accounts to ensure consistent state
        final installmentDocs =
            await _firestore.collection('installments').get();

        for (final doc in installmentDocs.docs) {
          final accountNumber = doc.id;
          if (!_previousAmountPayable.containsKey(accountNumber)) {
            // This is a new account that wasn't properly monitored
            await _loadInitialValues(accountNumber);
            _setupAccountMonitoring(accountNumber);
          } else {
            // Verify the current values against stored values
            _verifyAccountValues(accountNumber, doc.data());
          }
        }
      } catch (e) {
        debugPrint('❌ Error during periodic check: $e');
      }
    });
  }

  /// Monitor for new accounts being added to installments collection
  void _monitorNewAccounts() {
    try {
      final stream = _firestore.collection('installments').snapshots();

      final subscription = stream.listen(
        (snapshot) {
          for (final change in snapshot.docChanges) {
            if (change.type == DocumentChangeType.added) {
              final accountNumber = change.doc.id;
              debugPrint('🆕 New installment account detected: $accountNumber');
              _loadInitialValues(accountNumber).then((_) {
                _setupAccountMonitoring(accountNumber);
              });
            }
          }
        },
        onError: (error) {
          debugPrint('❌ Error monitoring new accounts: $error');
          // Try to reconnect after delay
          Future.delayed(const Duration(seconds: 30), _monitorNewAccounts);
        },
      );

      _listeners['new_accounts'] = subscription;
      debugPrint('👀 Now monitoring for new installment accounts');
    } catch (e) {
      debugPrint('❌ Error setting up new accounts listener: $e');
      // Try to reconnect after delay
      Future.delayed(const Duration(seconds: 30), _monitorNewAccounts);
    }
  }

  /// Setup monitoring for a specific account's installments
  void _setupAccountMonitoring(String accountNumber) {
    try {
      // Clear out any existing listeners for this account
      if (_listeners.containsKey('account_$accountNumber')) {
        _listeners['account_$accountNumber]']?.cancel();
        _listeners.remove('account_$accountNumber');
      }

      // Ensure we have tracking maps for this account
      if (!_previousAmountPayable.containsKey(accountNumber)) {
        _previousAmountPayable[accountNumber] = {};
      }

      if (!_previousArrearStatuses.containsKey(accountNumber)) {
        _previousArrearStatuses[accountNumber] = {};
      }

      if (!_previousBalances.containsKey(accountNumber)) {
        _previousBalances[accountNumber] = 0;
      }

      // Set up real-time listener
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
          debugPrint('❌ Error monitoring account $accountNumber: $error');
          // Try to reconnect after delay
          Future.delayed(
            const Duration(seconds: 30),
            () => _setupAccountMonitoring(accountNumber),
          );
        },
      );

      _listeners['account_$accountNumber'] = subscription;
      debugPrint('👂 Now monitoring account: $accountNumber');
    } catch (e) {
      debugPrint(
        '❌ Error setting up account monitoring for $accountNumber: $e',
      );
      Future.delayed(
        const Duration(seconds: 30),
        () => _setupAccountMonitoring(accountNumber),
      );
    }
  }

  /// Track monthly installment amounts for batching messages
  void _trackMonthlyInstallment(String accountNumber, int amount) {
    if (!_batchMonthlyInstallments.containsKey(accountNumber)) {
      _batchMonthlyInstallments[accountNumber] = [];
    }

    _batchMonthlyInstallments[accountNumber]!.add(amount);
    debugPrint(
      '💼 Tracked monthly installment amount: Rs. $amount for batch handling',
    );
  }

  /// Check if a payment was recently processed to avoid duplicates
  bool _wasPaymentRecentlyProcessed(String accountNumber, int amount) {
    final key = '${accountNumber}_$amount';
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if we have a recent payment with the same amount
    if (_recentPaymentMessages.containsKey(key)) {
      final lastProcessed = _recentPaymentMessages[key]!;

      // If processed in the last 5 seconds, consider it a duplicate
      if (now - lastProcessed < 5000) {
        // 5 seconds
        debugPrint(
          '⚠️ Skipping duplicate payment: Rs. $amount for account $accountNumber',
        );
        return true;
      }
    }

    // Not a duplicate or not recent enough, update timestamp
    _recentPaymentMessages[key] = now;
    return false;
  }

  /// Check if a payment is part of a monthly installment completion
  /// (to avoid sending Cash Deposit message for these)
  bool _isMonthlyCompletionPayment(String accountNumber, int amount) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${accountNumber}_${now}_$amount';

    // Check if this payment is marked as part of a monthly installment completion
    if (_monthlyCompletionPayments.contains(key) ||
        _monthlyCompletionPayments.contains('${accountNumber}_$amount')) {
      debugPrint(
        '🔍 Payment of Rs. $amount is flagged as monthly completion payment - skipping Cash Deposit',
      );
      return true;
    }

    return false;
  }

  /// Mark a payment as part of a monthly installment completion
  void _markAsMonthlyCompletionPayment(String accountNumber, int amount) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final key = '${accountNumber}_${now}_$amount';
    _monthlyCompletionPayments.add(key);

    // Also add simpler key for exact amount matching
    _monthlyCompletionPayments.add('${accountNumber}_$amount');

    debugPrint('✅ Marked payment of Rs. $amount as monthly completion payment');
  }

  /// Check if monthly installment message was sent recently (to avoid multiple in short succession)
  bool _shouldThrottleMonthlyMessage(String accountNumber) {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (_lastMonthlyMessageTime.containsKey(accountNumber)) {
      final lastSent = _lastMonthlyMessageTime[accountNumber]!;

      // If sent in the last 30 seconds, throttle and collect more months
      if (now - lastSent < 30000) {
        // 30 seconds
        debugPrint(
          '⏱️ Throttling monthly message for account $accountNumber - too soon',
        );
        return true;
      }
    }

    return false;
  }

  /// Update the monthly message timestamp tracker
  void _updateMonthlyMessageTimestamp(String accountNumber) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _lastMonthlyMessageTime[accountNumber] = now;
  }

  /// Create or update a partial payment for a monthly installment
  /// Returns true if the monthly payment is now complete
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
      '💵 Updated partial payment for $accountNumber, month $month: $currentAccumulated/$fullAmount',
    );

    // Return true if we've reached or exceeded the full amount
    if (currentAccumulated >= fullAmount) {
      debugPrint(
        '✅ Monthly payment completed for $accountNumber, month $month',
      );
      // Reset the counter after payment is complete
      _partialMonthlyPayments[accountNumber]!.remove(month);

      // For excess payments, don't send Monthly Installment message
      if (currentAccumulated > fullAmount) {
        debugPrint(
          '💰 Payment exceeds monthly amount - will only send Cash Deposit for total amount',
        );
        return false;
      }

      // For exact payment matches, mark it as monthly completion
      if (amount > 0 && amount == fullAmount) {
        _markAsMonthlyCompletionPayment(accountNumber, amount);
      }

      return true;
    }

    return false;
  }

  /// Process status changes (for Monthly Installment messages) with excess check
  List<Map<String, dynamic>> _processStatusChanges(
    String accountNumber,
    Map<String, dynamic> data,
    int decreaseAmount,
  ) {
    List<Map<String, dynamic>> newlyPaidMonths = [];
    int totalMonthlyAmount = 0;

    if (data.containsKey('arrears') && data['arrears'] is List) {
      final List<dynamic> arrears = data['arrears'] as List<dynamic>;

      // First collect all newly paid months
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

            // If status changed to "paid"
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

            // Update status tracking
            _previousArrearStatuses[accountNumber]![i] = currentArrearStatus;
          }
        }
      }
    }

    // Check for excess payment but KEEP monthly installment messages
    if (decreaseAmount > totalMonthlyAmount && totalMonthlyAmount > 0) {
      debugPrint(
        '💰 Excess payment detected: Rs. $decreaseAmount > Rs. $totalMonthlyAmount - sending both Cash Deposit and Monthly Installment',
      );

      // Mark amounts to prevent duplicate Cash Deposit messages
      for (final monthData in newlyPaidMonths) {
        _markAsMonthlyCompletionPayment(
          accountNumber,
          monthData['amount'] as int,
        );
      }

      // Don't clear the newlyPaidMonths list - allow monthly messages to be sent
    }

    return newlyPaidMonths;
  }

  /// Verify account values against stored values to catch missed updates
  /// Verify account values against stored values to catch missed updates
  void _verifyAccountValues(String accountNumber, Map<String, dynamic> data) {
    try {
      // Check balance changes
      final int currentBalance = _parseIntSafely(data['balance']);
      final int previousBalance =
          _previousBalances[accountNumber] ?? currentBalance;

      bool paymentProcessed = false;

      // Check if balance changed to zero (finance completed)
      if (previousBalance > 0 && currentBalance == 0) {
        // Calculate the final payment amount
        final int finalPayment =
            previousBalance; // This is the amount that was just paid

        // First send Cash Deposit message for the final payment (if substantial)
        if (finalPayment > 0) {
          _processPayment(accountNumber, data, finalPayment);
          debugPrint(
            '💰 Final payment Cash Deposit message sent: Rs. $finalPayment for account $accountNumber (before finance completion)',
          );
        }

        // Then send Finance Completed message
        _processFinanceCompleted(accountNumber, data);
        paymentProcessed = true;

        // Update the balance value and exit early
        _previousBalances[accountNumber] = currentBalance;
        return;
      }

      // Check if balance decreased (payment made)
      if (previousBalance > currentBalance) {
        final int decreaseAmount = previousBalance - currentBalance;

        // Process status changes with excess payment check
        List<Map<String, dynamic>> newlyPaidMonths = _processStatusChanges(
          accountNumber,
          data,
          decreaseAmount,
        );

        // If multiple monthly installments were paid at once, handle specially
        if (newlyPaidMonths.length > 1) {
          // Calculate total monthly amount
          int totalMonthlyAmount = 0;
          for (final month in newlyPaidMonths) {
            totalMonthlyAmount += (month['amount'] as int);
          }

          // Only send a single Cash Deposit for total amount if we haven't processed this payment amount yet
          if (!_wasPaymentRecentlyProcessed(accountNumber, decreaseAmount)) {
            // Send Cash Deposit message for the total amount
            _processPayment(accountNumber, data, decreaseAmount);

            // Mark all monthly amounts and the total to prevent duplicate messages
            for (final monthData in newlyPaidMonths) {
              _markAsMonthlyCompletionPayment(
                accountNumber,
                monthData['amount'] as int,
              );
            }
            _markAsMonthlyCompletionPayment(accountNumber, decreaseAmount);

            // Only send Monthly Installment message when payment equals total monthly amount
            if (decreaseAmount != totalMonthlyAmount) {
              // Clear newly paid months to prevent Monthly Installment message for excess payment
              newlyPaidMonths.clear();
            }
          }

          paymentProcessed = true;
        }
        // Handle normal case - single payment
        else if (!paymentProcessed &&
            !_isMonthlyCompletionPayment(accountNumber, decreaseAmount) &&
            !_wasPaymentRecentlyProcessed(accountNumber, decreaseAmount)) {
          // Send Cash Deposit message for single payment
          _processPayment(accountNumber, data, decreaseAmount);

          // Track potential partial monthly payment
          _checkForMonthlyInstallmentPayment(
            accountNumber,
            data,
            decreaseAmount,
          );

          paymentProcessed = true;
        }

        // Update balance tracking
        _previousBalances[accountNumber] = currentBalance;

        // Process any newly paid months (send Monthly Installment message)
        if (newlyPaidMonths.isNotEmpty) {
          // Only send if we're not throttling messages for this account
          if (!_shouldThrottleMonthlyMessage(accountNumber)) {
            _processMonthlyInstallmentNotifications(
              accountNumber,
              data,
              newlyPaidMonths,
            );
          } else {
            // Store for later processing when the throttle period passes
            if (!_pendingMonthlyInstallments.containsKey(accountNumber)) {
              _pendingMonthlyInstallments[accountNumber] = [];
            }
            _pendingMonthlyInstallments[accountNumber]!.addAll(newlyPaidMonths);
            debugPrint(
              '🗂️ Added ${newlyPaidMonths.length} month(s) to pending batch for account $accountNumber (throttled)',
            );
          }
        }
      }

      // Rest of the method remains unchanged...

      // Check for amount changes only if no payment processed yet
      if (!paymentProcessed &&
          data.containsKey('arrears') &&
          data['arrears'] is List) {
        // Existing code for amount changes...
      }

      // Process any pending monthly installments if we're not throttling
      if (!_shouldThrottleMonthlyMessage(accountNumber) &&
          _pendingMonthlyInstallments.containsKey(accountNumber) &&
          _pendingMonthlyInstallments[accountNumber]!.isNotEmpty) {
        // Existing code for processing pending installments...
      }
    } catch (e) {
      debugPrint('❌ Error verifying account values for $accountNumber: $e');
    }
  }

  /// Check if a payment is for a monthly installment and track it
  /// Check if a payment is for a monthly installment and track it
  void _checkForMonthlyInstallmentPayment(
    String accountNumber,
    Map<String, dynamic> data,
    int amount, {
    Map<String, dynamic>? monthInfo,
  }) {
    try {
      // If specific month info is provided, use it
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
            // If payment is greater than the installment amount, don't send monthly messages
            // A Cash Deposit message will be sent for the total amount
            if (amount > fullAmount) {
              debugPrint(
                '💰 Excess payment detected: Rs. $amount > Rs. $fullAmount - will only send Cash Deposit for total',
              );

              // Mark both amounts to prevent duplicate messages
              _markAsMonthlyCompletionPayment(accountNumber, amount);
              _markAsMonthlyCompletionPayment(accountNumber, fullAmount);

              // Create payment record but don't send a message for the installment
              _createPaymentRecord(
                accountNumber: accountNumber,
                customerId: data['customerId']?.toString() ?? '',
                customerName: data['customerName']?.toString() ?? '',
                amount: amount,
                paymentType: "excess_payment",
              );

              return;
            }

            // Normal flow for equal or partial payments
            bool isComplete = _updatePartialMonthlyPayment(
              accountNumber,
              month,
              amount,
              fullAmount,
            );

            // Record in payments collection
            _createPaymentRecord(
              accountNumber: accountNumber,
              customerId: data['customerId']?.toString() ?? '',
              customerName: data['customerName']?.toString() ?? '',
              amount: amount,
              paymentType: isComplete ? "monthly_completed" : "partial_monthly",
            );

            // If this completes the payment and equals the full amount, it's a full monthly payment
            if (isComplete && amount == fullAmount) {
              _markAsMonthlyCompletionPayment(accountNumber, amount);

              // Add to newly paid months for processing a Monthly Installment notification
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
                // Store for later processing
                if (!_pendingMonthlyInstallments.containsKey(accountNumber)) {
                  _pendingMonthlyInstallments[accountNumber] = [];
                }
                _pendingMonthlyInstallments[accountNumber]!.add(monthData);
              }
            }

            debugPrint(
              '🔄 Tracked payment of Rs. $amount for monthly installment (${isComplete ? "completed" : "partial"})',
            );
            return;
          }
        }
      }

      // If no specific month info, check all arrears
      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is Map &&
              arrear.containsKey('month') &&
              arrear.containsKey('status')) {
            final String status =
                arrear['status']?.toString().toLowerCase() ?? '';

            // Only check unpaid arrears
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
                  // If payment is greater than the installment amount, don't send monthly messages
                  // A Cash Deposit message will be sent for the total amount
                  if (amount > fullAmount) {
                    debugPrint(
                      '💰 Excess payment detected: Rs. $amount > Rs. $fullAmount - will only send Cash Deposit for total',
                    );

                    // Mark both amounts to prevent duplicate messages
                    _markAsMonthlyCompletionPayment(accountNumber, amount);
                    _markAsMonthlyCompletionPayment(accountNumber, fullAmount);

                    // Create payment record but don't send a message for the installment
                    _createPaymentRecord(
                      accountNumber: accountNumber,
                      customerId: data['customerId']?.toString() ?? '',
                      customerName: data['customerName']?.toString() ?? '',
                      amount: amount,
                      paymentType: "excess_payment",
                    );

                    return;
                  }

                  // Normal flow for equal or partial payments
                  bool isComplete = _updatePartialMonthlyPayment(
                    accountNumber,
                    month,
                    amount,
                    fullAmount,
                  );

                  // Record in payments collection
                  _createPaymentRecord(
                    accountNumber: accountNumber,
                    customerId: data['customerId']?.toString() ?? '',
                    customerName: data['customerName']?.toString() ?? '',
                    amount: amount,
                    paymentType:
                        isComplete ? "monthly_completed" : "partial_monthly",
                  );

                  // If this completes the payment exactly, it's a full monthly payment
                  if (isComplete && amount == fullAmount) {
                    _markAsMonthlyCompletionPayment(accountNumber, amount);

                    // Process Monthly Installment message
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
                      // Store for later processing
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
                    '🔄 Tracked payment of Rs. $amount for monthly installment (${isComplete ? "completed" : "partial"})',
                  );
                  return;
                }
              }
            }
          }
        }
      }

      // If no monthly installment identified, treat as regular payment
    } catch (e) {
      debugPrint('❌ Error checking for monthly installment payment: $e');
    }
  }

  /// Process updates to an installment document
  void _processInstallmentUpdate(
    String accountNumber,
    Map<String, dynamic> data,
  ) {
    try {
      // Check if this is the first update for this account
      bool isFirstUpdate = _firstUpdateAccounts.contains(accountNumber);

      // Get current balance
      final int currentBalance = _parseIntSafely(data['balance']);

      // If this is the first update, just record values without triggering messages
      if (isFirstUpdate) {
        debugPrint(
          '⚡ First update for account $accountNumber - recording values only',
        );
        _previousBalances[accountNumber] = currentBalance;

        // Record arrears values
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

        // Remove from first update set so future updates trigger messages
        _firstUpdateAccounts.remove(accountNumber);
        return;
      }

      // For subsequent updates, use the verification method
      _verifyAccountValues(accountNumber, data);
    } catch (e) {
      debugPrint(
        '❌ Error processing installment update for $accountNumber: $e',
      );
    }
  }

  /// Generate a unique key for tracking monthly payment processing
  String _getMonthlyPaymentKey(
    String accountNumber,
    Map<String, dynamic> data, {
    int? arrearIndex,
  }) {
    String month = '';

    // Try to get month from specific arrear if index provided
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

    // If no month found from specific arrear, try general methods
    if (month.isEmpty) {
      // Try to get month from any arrear
      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;
        for (final arrear in arrears) {
          if (arrear is Map && arrear.containsKey('month')) {
            month = arrear['month']?.toString() ?? '';
            if (month.isNotEmpty) break;
          }
        }
      }

      // Try direct 'month' field if not found in arrears
      if (month.isEmpty && data.containsKey('month')) {
        month = data['month']?.toString() ?? '';
      }

      // Use current month as fallback if still empty
      if (month.isEmpty) {
        final now = DateTime.now();
        month = '${now.year}-${_twoDigits(now.month)}';
      }
    }

    // Create key with arrear index if provided
    if (arrearIndex != null) {
      return '$accountNumber-$month-$arrearIndex';
    } else {
      return '$accountNumber-$month';
    }
  }

  /// Process completed monthly installments (send notification without mentioning payment amount)
  Future<void> _processMonthlyInstallmentNotifications(
    String accountNumber,
    Map<String, dynamic> data,
    List<Map<String, dynamic>> monthsData,
  ) async {
    try {
      debugPrint(
        '📢 Processing monthly installment notifications for account $accountNumber',
      );

      // Skip if finance is completed (balance is 0)
      if (_parseIntSafely(data['balance']) == 0) {
        debugPrint(
          '⚠️ Skip monthly installment message - finance is completed',
        );
        return;
      }

      // Skip if no months data
      if (monthsData.isEmpty) {
        debugPrint('⚠️ Skip monthly installment message - no months data');
        return;
      }

      // Update timestamp to prevent multiple messages in short succession
      _updateMonthlyMessageTimestamp(accountNumber);

      // Extract customer data
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      // Extract month names and record payments
      List<String> months = [];

      // For each month that's been paid, mark its payment as monthly completion
      for (final monthData in monthsData) {
        months.add(monthData['month'] as String);

        final int monthlyAmount = monthData['amount'] as int;

        // Mark this payment amount so we don't send a Cash Deposit message for it
        _markAsMonthlyCompletionPayment(accountNumber, monthlyAmount);

        // Record each month's payment with "monthly_completed" type
        await _createPaymentRecord(
          accountNumber: accountNumber,
          customerId: customerId,
          customerName: await _getCustomerName(customerId, customerName),
          amount: monthlyAmount,
          paymentType: "monthly_completed",
        );
      }

      // Sort months chronologically
      months.sort();

      // Get final customer name
      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      // Create unique message ID with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'monthly_${accountNumber}_$timestamp';

      // Create monthly installment message - showing all months vertically
      String heading = "Monthly Installment";
      String message;

      if (months.length == 1) {
        // Single month format
        message =
            "You have successfully paid the relevant installment for ${months.first}. \n\nThank you for your prompt payment. Your account has been updated accordingly. - Unicon Finance.";
      } else {
        // Multiple months format - vertical listing
        message =
            "You have successfully paid the relevant installments for the following months:\n";

        // Add each month on a new line
        for (final month in months) {
          message += "\n• $month";
        }
        message +=
            "\n\nThank you for your prompt payment. Your account has been updated accordingly. - Unicon Finance.";
      }

      debugPrint('💌 Creating monthly installment message: $heading');

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: heading,
        message: message,
        messageId: messageId,
      );

      debugPrint(
        '📅 Monthly installment notification sent for account $accountNumber: ${months.length} month(s)',
      );
    } catch (e) {
      debugPrint('❌ Error processing monthly installment notifications: $e');
    }
  }

  /// Process a regular payment and create a Cash Deposit message
  Future<void> _processPayment(
    String accountNumber,
    Map<String, dynamic> data,
    int paymentAmount,
  ) async {
    try {
      // Skip if payment amount is zero or negative
      if (paymentAmount <= 0) {
        return;
      }

      // Skip if this payment is marked as part of a monthly installment completion
      if (_isMonthlyCompletionPayment(accountNumber, paymentAmount)) {
        debugPrint(
          '⏭️ Skipping Cash Deposit message for monthly completion payment: Rs. $paymentAmount',
        );
        return;
      }

      // Extract customer data
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      // Get customer name
      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      // Format account number to show only last 4 digits
      String maskedAccountNumber = _maskAccountNumber(accountNumber);

      // Create unique message ID with timestamp
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'payment_${accountNumber}_${timestamp}_$paymentAmount';

      // Create a simple Cash Deposit message - just amount and account
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

      // Record in payments collection
      await _createPaymentRecord(
        accountNumber: accountNumber,
        customerId: customerId,
        customerName: finalCustomerName,
        amount: paymentAmount,
        paymentType: "regular",
      );

      debugPrint(
        '💰 Cash Deposit message sent: Rs. $paymentAmount for account $accountNumber',
      );
    } catch (e) {
      debugPrint('❌ Error processing payment: $e');
    }
  }

  /// Process a fully completed finance and create a message
  /// Process a fully completed finance and create a message
  /// Process a fully completed finance and create a message
  Future<void> _processFinanceCompleted(
    String accountNumber,
    Map<String, dynamic> data,
  ) async {
    try {
      // Extract customer data
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      // Get customer name
      String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      // Format account number to show only last 4 digits
      String maskedAccountNumber = _maskAccountNumber(accountNumber);

      // Calculate the final payment amount - critical for Cash Deposit message
      int finalPayment = 0;

      // First try to get from previous balance (most reliable method)
      if (_previousBalances.containsKey(accountNumber)) {
        finalPayment = _previousBalances[accountNumber] ?? 0;
      }

      // If that fails, try the finalPayment field or calculate from other data
      if (finalPayment == 0) {
        if (data.containsKey('finalPayment')) {
          finalPayment = _parseIntSafely(data['finalPayment']);
        } else if (data.containsKey('lastPaymentAmount')) {
          finalPayment = _parseIntSafely(data['lastPaymentAmount']);
        }
      }

      // Always send Cash Deposit message for the final payment first
      if (finalPayment > 0) {
        // Create unique message ID with timestamp for the payment
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        String paymentMessageId =
            'payment_${accountNumber}_${timestamp}_$finalPayment';

        // Create Cash Deposit message
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

        // Record the payment in the payments collection
        await _createPaymentRecord(
          accountNumber: accountNumber,
          customerId: customerId,
          customerName: finalCustomerName,
          amount: finalPayment,
          paymentType: "final",
        );

        debugPrint(
          '💰 Final payment Cash Deposit message sent: Rs. $finalPayment for account $accountNumber',
        );
      } else {
        debugPrint(
          '⚠️ Warning: Could not determine final payment amount for account $accountNumber',
        );
      }

      // Then send Finance Completed message
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      String messageId = 'completed_${accountNumber}_$timestamp';

      // Create finance completed message
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

      debugPrint(
        '🎉 Finance completed message sent for account $accountNumber',
      );
    } catch (e) {
      debugPrint('❌ Error processing finance completion: $e');
    }
  }

  /// Create a payment record in the payments collection
  Future<void> _createPaymentRecord({
    required String accountNumber,
    required String customerId,
    required String customerName,
    required int amount,
    required String paymentType,
  }) async {
    try {
      // Get current date in yyyy-MM-dd format
      final dateFormatted = _getCurrentFormattedDate();

      // Create payment record
      final paymentData = {
        'accountNumber': accountNumber,
        'customerId': customerId,
        'customerName': customerName,
        'paymentAmount': amount,
        'paymentDate': dateFormatted,
        'paymentType': paymentType,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Add to payments collection
      await _firestore.collection('payments').add(paymentData);
      debugPrint(
        '💵 Payment record created: Rs. $amount for account $accountNumber (type: $paymentType)',
      );
    } catch (e) {
      debugPrint('❌ Error creating payment record: $e');
    }
  }

  /// Format a month string like "2025-06" to "June 2025"
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
      debugPrint('⚠️ Error parsing month: $monthStr');
    }
    return monthStr; // Return original if can't parse
  }

  /// Get customer name from either document or customers collection
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
      debugPrint('⚠️ Error fetching customer details: $e');
    }

    return 'Customer';
  }

  /// Format account number to show only last 4 digits
  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length > 4) {
      return 'XXXXXX${accountNumber.substring(accountNumber.length - 4)}';
    }
    return accountNumber;
  }

  /// Create and send a message to Firestore with retry mechanism
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
        debugPrint('📩 Creating message: $heading (attempt ${retries + 1})');

        // Format current date and time
        final dateFormatted = _getCurrentFormattedDate();
        final timeFormatted = _getCurrentFormattedTime();

        // Create message in Firestore
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
        debugPrint('✉️ Message sent successfully: $heading');

        // Message sent, exit retry loop
        return;
      } catch (e) {
        retries++;
        debugPrint('❌ Error creating message (attempt $retries): $e');

        // Wait before retrying
        if (retries < maxRetries) {
          await Future.delayed(Duration(seconds: retries * 2));
        }
      }
    }

    // All retries failed
    debugPrint('❌ Failed to create message after $maxRetries attempts');
  }

  /// Get current formatted date (yyyy-MM-dd)
  String _getCurrentFormattedDate() {
    final now = DateTime.now();
    return "${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}";
  }

  /// Get current formatted time (hh:mm AM/PM)
  String _getCurrentFormattedTime() {
    final now = DateTime.now();
    final hour =
        now.hour > 12 ? now.hour - 12 : (now.hour == 0 ? 12 : now.hour);
    final amPm = now.hour >= 12 ? 'PM' : 'AM';
    return "${_twoDigits(hour)}:${_twoDigits(now.minute)} $amPm";
  }

  /// Get month name from month number (1-12)
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
    return monthNames[DateTime.now().month - 1]; // Fallback to current month
  }

  /// Helper for two-digit formatting
  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  /// Safely parse int values
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;

    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;

    return 0;
  }

  /// Reset the tracking of processed payments
  void resetProcessedPayments() {
    _processedMonthlyPayments.clear();
    _recentPaymentMessages.clear();
    _pendingMonthlyInstallments.clear();
    _lastMonthlyMessageTime.clear();
    _partialMonthlyPayments.clear();
    _monthlyCompletionPayments.clear();
    _batchMonthlyInstallments.clear();
    debugPrint('🔄 Payment tracking has been reset');
  }

  /// Cancel all listeners to prevent memory leaks
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

    debugPrint('🧹 Payment messages service disposed');
  }
}

/// Initializer for the payment messages service
class PaymentMessagesInitializer {
  static bool _isInitialized = false;
  static PaymentMessagesService? _service;

  /// Initialize the payment messages service
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Payment messages service already initialized');
      return;
    }

    try {
      debugPrint('🚀 Initializing payment messages service');

      // Add short delay to ensure Firebase is fully initialized
      await Future.delayed(Duration(seconds: 2));

      // Test Firebase permissions
      try {
        final testRead =
            await FirebaseFirestore.instance
                .collection('installments')
                .limit(1)
                .get();
        debugPrint(
          '✅ Firebase read test successful: ${testRead.docs.length} documents',
        );

        // Verify messages collection access
        await FirebaseFirestore.instance.collection('messages').limit(1).get();
        debugPrint('✅ Firebase messages collection access verified');
      } catch (e) {
        debugPrint('⚠️ Firebase permission test failed: $e');
        // Continue anyway since we'll retry on failures
      }

      _service = PaymentMessagesService();
      await _service!.startMonitoring();
      _isInitialized = true;

      // Set up auto-restart for reliability
      _setupAutoRestart();

      debugPrint('✅ Payment messages service initialized successfully');
    } catch (e) {
      debugPrint('❌ Error initializing payment messages service: $e');
      // Try again after a delay
      Future.delayed(const Duration(seconds: 30), initialize);
    }
  }

  /// Set up auto-restart mechanism
  static void _setupAutoRestart() {
    // Check every 6 hours if the service is still running
    Timer.periodic(const Duration(hours: 6), (timer) {
      if (!_isInitialized || _service == null) {
        debugPrint('⚠️ Service not running, restarting...');
        initialize();
      }

      // Reset processed payments tracking periodically
      _service?.resetProcessedPayments();
    });
  }

  /// Force send a test payment message
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
        debugPrint('❌ Account $accountNumber not found');
        return false;
      }

      await _service!._processPayment(accountNumber, doc.data()!, 1000);
      debugPrint('✅ Test payment message sent for account $accountNumber');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending test payment message: $e');
      return false;
    }
  }

  /// Force send a test monthly installment message
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
        debugPrint('❌ Account $accountNumber not found');
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
        '✅ Test monthly installment message sent for account $accountNumber',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error sending test monthly installment message: $e');
      return false;
    }
  }

  /// Test partial monthly payments
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
        debugPrint('❌ Account $accountNumber not found');
        return false;
      }

      final String testMonth = '2025-05';
      final int fullAmount = 5000;

      // First payment - creates cash deposit message
      await _service!._processPayment(accountNumber, doc.data()!, 1000);

      // Record as partial monthly payment
      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        1000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      // Second payment - creates cash deposit message
      await _service!._processPayment(accountNumber, doc.data()!, 2000);

      // Record as partial monthly payment
      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        2000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      // Final payment - creates Monthly Installment message (no Cash Deposit)
      _service!._checkForMonthlyInstallmentPayment(
        accountNumber,
        doc.data()!,
        2000,
        monthInfo: {'month': testMonth, 'amount': fullAmount},
      );

      debugPrint(
        '✅ Test partial payments processed for account $accountNumber',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error testing partial payments: $e');
      return false;
    }
  }

  /// Test multiple monthly installments in one payment
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

      // Simulate multiple months paid at once (10000 total)
      final months = [
        {'month': '2025-01', 'amount': 5000},
        {'month': '2025-02', 'amount': 5000},
      ];

      // First mark both months as paid
      for (final month in months) {
        _service!._trackMonthlyInstallment(
          accountNumber,
          month['amount'] as int,
        );
        // Mark each monthly amount to prevent individual Cash Deposit messages
        _service!._markAsMonthlyCompletionPayment(
          accountNumber,
          month['amount'] as int,
        );
      }

      // Now send one Cash Deposit message for the total amount
      await _service!._processPayment(accountNumber, doc.data()!, 10000);

      // Then send the Monthly Installment message with both months
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
        '✅ Test multiple monthly installments processed for account $accountNumber',
      );
      return true;
    } catch (e) {
      debugPrint('❌ Error testing multiple monthly installments: $e');
      return false;
    }
  }

  /// Dispose of the service
  static void dispose() {
    _service?.dispose();
    _service = null;
    _isInitialized = false;
    debugPrint('🔄 Payment messages service disposed');
  }
}
