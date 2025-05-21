import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Background service that monitors the installments collection for:
/// 1. Upcoming billing dates to send payment reminders
/// 2. Past due installments to send arrears reminders
class PaymentReminderService {
  // Firestore instance
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Real-time listener
  StreamSubscription? _installmentsListener;

  // Track accounts processed today to prevent duplicate messages
  final Map<String, Set<String>> _processedBillingDates = {};
  final Map<String, Map<String, Set<String>>> _processedArrearsReminders = {};

  // Keep track of accounts currently being processed to prevent duplicates
  final Set<String> _accountsBeingProcessed = {};

  // Timer for periodic check (backup)
  Timer? _periodicTimer;

  // Timer for daily arrears check
  Timer? _arrearsTimer;

  // Timer for midnight reset
  Timer? _midnightTimer;

  // Current date for comparison
  late String _todayFormatted;

  // Flag to prevent concurrent operations
  bool _isProcessing = false;
  bool _isProcessingArrears = false;

  // Singleton pattern
  static final PaymentReminderService _instance =
      PaymentReminderService._internal();

  factory PaymentReminderService() {
    return _instance;
  }

  PaymentReminderService._internal() {
    _updateTodayDate();
    debugPrint(
      '🔔 Initializing payment reminder service for date: $_todayFormatted',
    );
  }

  /// Update today's date for comparisons
  void _updateTodayDate() {
    final now = DateTime.now();
    _todayFormatted = _formatDateForComparison(now);
  }

  /// Start monitoring installment billing dates and arrears
  Future<void> startMonitoring() async {
    debugPrint('🚀 Starting payment reminder service...');

    // Update today's date
    _updateTodayDate();
    debugPrint('📅 Today is: $_todayFormatted');

    // Clean up any existing resources
    _cleanup();

    try {
      // Start real-time monitoring of installments collection
      _setupRealtimeMonitoring();

      // Set up periodic check (every 30 minutes)
      _setupPeriodicCheck();

      // Set up daily arrears check
      _setupArrearsCheck();

      // Set up midnight reset
      _setupMidnightReset();

      // Do an immediate check of all accounts
      await checkAllInstallments();

      // Do an immediate check for arrears
      await checkAllForArrears();

      debugPrint('✅ Payment reminder service running');
    } catch (e) {
      debugPrint('❌ Error starting payment reminder service: $e');
      // Try to restart after delay
      Future.delayed(const Duration(minutes: 1), startMonitoring);
    }
  }

  /// Clean up resources
  void _cleanup() {
    // Cancel listeners
    _installmentsListener?.cancel();
    _installmentsListener = null;

    // Cancel timers
    _periodicTimer?.cancel();
    _periodicTimer = null;

    _arrearsTimer?.cancel();
    _arrearsTimer = null;

    _midnightTimer?.cancel();
    _midnightTimer = null;

    // Clear processing sets
    _accountsBeingProcessed.clear();
  }

  /// Set up real-time monitoring of installments collection
  void _setupRealtimeMonitoring() {
    _installmentsListener = _db
        .collection('installments')
        .snapshots()
        .listen(
          (snapshot) {
            // Process all changes
            for (final change in snapshot.docChanges) {
              final doc = change.doc;
              final accountId = doc.id;

              // Process document if it was added or modified
              if (change.type == DocumentChangeType.added ||
                  change.type == DocumentChangeType.modified) {
                _processBillingDate(accountId, doc.data() ?? {});

                // Always check for arrears in real-time to catch newly added arrears
                _checkForArrears(accountId, doc.data() ?? {});
              }
            }
          },
          onError: (error) {
            debugPrint('❌ Error in real-time listener: $error');
            // Try to reconnect after delay
            Future.delayed(Duration(seconds: 30), () {
              _setupRealtimeMonitoring();
            });
          },
        );

    debugPrint('👂 Installments real-time monitoring established');
  }

  /// Set up periodic check as backup for billing reminders
  void _setupPeriodicCheck() {
    _periodicTimer = Timer.periodic(Duration(minutes: 30), (_) async {
      debugPrint('⏰ Running periodic installments check');
      await checkAllInstallments();
    });
  }

  /// Set up daily check for arrears
  void _setupArrearsCheck() {
    // Check for arrears once every morning in Sri Lanka time (UTC+5:30)
    final now = DateTime.now();
    // Convert to Sri Lanka time by adding the UTC offset if needed
    final sriLankaOffset = const Duration(hours: 5, minutes: 30);
    final sriLankaTime =
        now.timeZoneOffset == sriLankaOffset
            ? now
            : now.add(sriLankaOffset - now.timeZoneOffset);
    final morning = DateTime(
      sriLankaTime.year,
      sriLankaTime.month,
      sriLankaTime.day,
      9,
      0,
    ); // 9:00 AM Sri Lanka time

    // Calculate time until next check
    Duration timeUntilCheck;
    if (now.isAfter(morning)) {
      // Already past morning time today, schedule for tomorrow
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 9, 0);
      timeUntilCheck = tomorrow.difference(now);
    } else {
      // Still before morning time, schedule for today
      timeUntilCheck = morning.difference(now);
    }

    // Schedule first check
    Timer(timeUntilCheck, () {
      // Run check
      checkAllForArrears();

      // Then set up daily recurring check
      _arrearsTimer = Timer.periodic(Duration(hours: 24), (_) {
        checkAllForArrears();
      });
    });

    debugPrint(
      '⏰ Arrears check scheduled in ${timeUntilCheck.inHours}h ${timeUntilCheck.inMinutes % 60}m',
    );
  }

  /// Set up midnight reset to clear processed accounts
  void _setupMidnightReset() {
    // Calculate time until next midnight
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    _midnightTimer = Timer(timeUntilMidnight, () {
      // Clear processed accounts
      _processedBillingDates.clear();
      _processedArrearsReminders.clear();
      _accountsBeingProcessed.clear();

      // Update today's date
      _updateTodayDate();
      debugPrint('🔄 Midnight reset - new date: $_todayFormatted');

      // Do a full check right after midnight
      checkAllInstallments();
      checkAllForArrears();

      // Set up next midnight reset
      _setupMidnightReset();
    });

    debugPrint(
      '⏰ Midnight reset scheduled in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m',
    );
  }

  /// Check all installments for billing dates matching today
  Future<void> checkAllInstallments() async {
    // Prevent concurrent execution
    if (_isProcessing) {
      debugPrint('⚠️ Check already in progress, skipping');
      return;
    }

    _isProcessing = true;

    try {
      debugPrint(
        '🔍 Checking all installments for billing dates matching today: $_todayFormatted',
      );

      // Update date to ensure we have the current date
      _updateTodayDate();

      // Get all installment documents
      final snapshot = await _db.collection('installments').get();
      debugPrint('📊 Found ${snapshot.docs.length} installment accounts');

      int matchCount = 0;

      // Check each document
      for (final doc in snapshot.docs) {
        final accountId = doc.id;
        final data = doc.data();

        if (await _processBillingDate(accountId, data)) {
          matchCount++;
        }
      }

      debugPrint(
        '✅ Check completed - found $matchCount accounts with billing date matching today',
      );
    } catch (e) {
      debugPrint('❌ Error checking all installments: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// Check all accounts for arrears
  Future<void> checkAllForArrears() async {
    // Prevent concurrent execution
    if (_isProcessingArrears) {
      debugPrint('⚠️ Arrears check already in progress, skipping');
      return;
    }

    _isProcessingArrears = true;

    try {
      debugPrint('🔍 Checking all installments for arrears');

      // Get all installment documents
      final snapshot = await _db.collection('installments').get();

      int accountsWithArrears = 0;

      // Check each document
      for (final doc in snapshot.docs) {
        final accountId = doc.id;
        final data = doc.data();

        if (await _checkForArrears(accountId, data)) {
          accountsWithArrears++;
        }
      }

      debugPrint(
        '✅ Arrears check completed - found $accountsWithArrears accounts with arrears',
      );
    } catch (e) {
      debugPrint('❌ Error checking for arrears: $e');
    } finally {
      _isProcessingArrears = false;
    }
  }

  /// Process a document to check if billing date matches today
  Future<bool> _processBillingDate(
    String accountId,
    Map<String, dynamic> data,
  ) async {
    try {
      bool sentMessage = false;

      // Check if the account has arrears
      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        // Create a month tracking map for this account if not exists
        if (!_processedBillingDates.containsKey(accountId)) {
          _processedBillingDates[accountId] = {};
        }

        // Check each arrear
        for (int i = 0; i < arrears.length; i++) {
          final arrear = arrears[i];

          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          // Skip if paid
          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          // Skip if no amount to pay
          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          // Check for billing date
          if (!arrearMap.containsKey('billingDate')) continue;

          // Get billing date
          final billingDateValue = arrearMap['billingDate'];
          if (billingDateValue == null) continue;

          // Get month for message content
          final month = arrearMap['month']?.toString() ?? '';
          final formattedMonth = _formatMonth(month);

          // Normalize billing date for comparison
          final String? billingDateFormatted = _normalizeBillingDate(
            billingDateValue,
          );
          if (billingDateFormatted == null) continue;

          debugPrint(
            '🔍 Account $accountId arrear $i: billing date $billingDateFormatted vs today $_todayFormatted',
          );

          // Check if billing date is today
          if (billingDateFormatted == _todayFormatted) {
            // Create unique key for this billing date to prevent duplicates
            final billingKey = '$accountId-$i-$billingDateFormatted';

            // Skip if already processed this specific billing date
            if (_processedBillingDates[accountId]!.contains(billingKey)) {
              debugPrint(
                '⏭️ Already sent reminder for account $accountId arrear $i',
              );
              continue;
            }

            // Send reminder message
            if (await _sendReminderMessage(
              accountId,
              data,
              amountPayable,
              formattedMonth,
            )) {
              // Mark as processed
              _processedBillingDates[accountId]!.add(billingKey);
              sentMessage = true;

              // Only send one message per account to avoid spam
              break;
            }
          }
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('❌ Error processing billing date for account $accountId: $e');
      return false;
    }
  }

  /// Check for unpaid past installments (arrears)
  Future<bool> _checkForArrears(
    String accountId,
    Map<String, dynamic> data,
  ) async {
    try {
      // Use a lock mechanism to prevent concurrent processing of the same account
      if (_accountsBeingProcessed.contains(accountId)) {
        debugPrint(
          '⚠️ Account $accountId is already being processed for arrears',
        );
        return false;
      }

      _accountsBeingProcessed.add(accountId);

      try {
        // Skip if no arrears array
        if (!data.containsKey('arrears') || data['arrears'] is! List) {
          return false;
        }

        final List<dynamic> arrears = data['arrears'] as List<dynamic>;
        final List<String> unpaidMonths = [];
        final Set<String> unpaidMonthCodes = {};
        int totalArrearsAmount = 0;

        // Get current date for comparison
        final now = DateTime.now();

        // Check each arrear
        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          // Skip if already paid
          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          // Skip if no amount payable
          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          // Get month for arrears list
          final month = arrearMap['month']?.toString() ?? '';
          if (month.isEmpty) continue;

          // Check if it's a past due installment
          bool isPastDue = false;

          // If has billing date, check if it's in the past (and not today)
          if (arrearMap.containsKey('billingDate')) {
            final billingDateValue = arrearMap['billingDate'];
            if (billingDateValue != null) {
              final String? billingDateFormatted = _normalizeBillingDate(
                billingDateValue,
              );
              if (billingDateFormatted != null) {
                // Parse the normalized date
                final billingDate = _parseAnyDateFormat(billingDateFormatted);
                if (billingDate != null) {
                  // Compare with yesterday or earlier (not today)
                  final yesterday = DateTime(now.year, now.month, now.day - 1);
                  if (billingDate.isBefore(yesterday)) {
                    isPastDue = true;
                  }
                }
              }
            }
          } else {
            // If no billing date but month format is YYYY-MM, check if it's a past month
            try {
              if (month.contains('-')) {
                final parts = month.split('-');
                if (parts.length == 2) {
                  final year = int.parse(parts[0]);
                  final monthNum = int.parse(parts[1]);

                  // Check if this is a past month
                  if (year < now.year ||
                      (year == now.year && monthNum < now.month)) {
                    isPastDue = true;
                  }
                }
              }
            } catch (e) {
              debugPrint('⚠️ Error parsing month for arrears: $e');
            }
          }

          if (isPastDue) {
            final formattedMonth = _formatMonth(month);
            unpaidMonths.add(formattedMonth);

            // Store a normalized month code for tracking
            final monthCode = month.replaceAll(' ', '_').toLowerCase();
            unpaidMonthCodes.add(monthCode);

            totalArrearsAmount += amountPayable;
          }
        }

        // If we found arrears, check if there are any new ones
        if (unpaidMonths.isNotEmpty) {
          // Check if we've already processed some arrears for this account today
          bool shouldSendMessage = false;

          // Initialize tracking for this account if not exists
          if (!_processedArrearsReminders.containsKey(accountId)) {
            _processedArrearsReminders[accountId] = {'months': {}};
            shouldSendMessage = true; // First message today for this account
          }

          // Check if there are new months that haven't been processed yet
          if (!shouldSendMessage) {
            final processedMonths =
                _processedArrearsReminders[accountId]?['months'] ?? {};

            // Look for any month that hasn't been processed yet
            for (final monthCode in unpaidMonthCodes) {
              if (!processedMonths.contains(monthCode)) {
                shouldSendMessage = true;
                debugPrint(
                  '🆕 New unpaid month found: $monthCode for account $accountId',
                );
                break;
              }
            }
          }

          if (shouldSendMessage) {
            // Send message for new or all arrears
            await _sendArrearsReminderMessage(
              accountId,
              data,
              unpaidMonths,
              totalArrearsAmount,
            );

            // Mark all months as processed
            if (!_processedArrearsReminders[accountId]!.containsKey('months')) {
              _processedArrearsReminders[accountId]!['months'] = {};
            }

            _processedArrearsReminders[accountId]!['months']!.addAll(
              unpaidMonthCodes,
            );

            debugPrint(
              '✅ Sent arrears reminder for account $accountId with ${unpaidMonths.length} months',
            );
            return true;
          } else {
            debugPrint(
              '⏭️ No new arrears months for account $accountId, skipping reminder',
            );
          }
        }

        return false;
      } finally {
        // Always remove from processing set when done
        _accountsBeingProcessed.remove(accountId);
      }
    } catch (e) {
      _accountsBeingProcessed.remove(accountId);
      debugPrint('❌ Error checking arrears for account $accountId: $e');
      return false;
    }
  }

  /// Send a message about unpaid arrears
  Future<bool> _sendArrearsReminderMessage(
    String accountId,
    Map<String, dynamic> data,
    List<String> unpaidMonths,
    int totalAmount,
  ) async {
    try {
      debugPrint('✉️ Sending arrears reminder for account: $accountId');

      // Extract customer data
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      // Skip if no customer ID
      if (customerId.isEmpty) {
        debugPrint(
          '⚠️ No customer ID for account $accountId, skipping arrears reminder',
        );
        return false;
      }

      // Get final customer name
      final String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      // Format account number for privacy
      final String maskedAccountNumber = _maskAccountNumber(accountId);

      // Create unique message ID with timestamp to allow multiple messages per day
      final String today = _getCurrentDateFormatted();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String messageId = 'arrears_${accountId}_${today}_$timestamp';

      String message;

      // Format message based on number of unpaid months
      if (unpaidMonths.length == 1) {
        // Single month arrears notification
        message =
            "This is a reminder from Unicon Finance regarding your finance account $maskedAccountNumber. "
            "As of today, you have an outstanding arrears amount of Rs. $totalAmount for ${unpaidMonths[0]}.\n\n"
            "Kindly settle the due amount at your earliest convenience to avoid penalties or disruption of services.\n\n"
            "If payment has already been made, please disregard this notice.\n\n"
            "Thank you for your continued trust in Unicon Finance.";
      } else {
        // Multiple months arrears notification
        message =
            "This is to inform you that your finance account $maskedAccountNumber with Unicon Finance "
            "has an outstanding arrears balance of Rs. $totalAmount covering the following months:\n\n";

        // Add each month on a new line with bullet point
        for (final month in unpaidMonths) {
          message += "• $month\n";
        }

        message +=
            "\nWe kindly urge you to clear the dues to maintain a positive credit standing and avoid additional charges.\n\n"
            "If payment has already been made, please disregard this notice.\n\n"
            "Thank you for choosing Unicon Finance.";
      }

      // Create message in Firestore
      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: "Arrears Notice",
        message: message,
        messageId: messageId,
      );

      debugPrint('✅ Arrears reminder sent for account $accountId');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending arrears reminder: $e');
      return false;
    }
  }

  /// Normalize billing date to consistent string format for comparison
  String? _normalizeBillingDate(dynamic billingDateValue) {
    try {
      // Case 1: Already a string
      if (billingDateValue is String) {
        // Try direct match first
        final cleanStr = billingDateValue.trim();

        // Try to parse as DateTime
        DateTime? date = _parseAnyDateFormat(cleanStr);
        if (date != null) {
          return _formatDateForComparison(date);
        }

        // If it's just a day number (e.g. "9"), add current month/year
        if (cleanStr.length <= 2) {
          final day = int.tryParse(cleanStr);
          if (day != null && day >= 1 && day <= 31) {
            final now = DateTime.now();
            return _formatDateForComparison(DateTime(now.year, now.month, day));
          }
        }

        return cleanStr; // Return as-is if can't parse
      }
      // Case 2: Timestamp
      else if (billingDateValue is Timestamp) {
        return _formatDateForComparison(billingDateValue.toDate());
      }
      // Case 3: Integer (day of month)
      else if (billingDateValue is int) {
        final now = DateTime.now();
        return _formatDateForComparison(
          DateTime(now.year, now.month, billingDateValue),
        );
      }
    } catch (e) {
      debugPrint('❌ Error normalizing billing date: $e');
    }

    return null;
  }

  /// Parse date from any common format
  DateTime? _parseAnyDateFormat(String dateStr) {
    try {
      // Try popular formats
      final formats = [
        'yyyy-MM-dd', // ISO format
        'dd-MM-yyyy', // European format
        'MM/dd/yyyy', // US format
        'dd/MM/yyyy', // UK format
        'yyyy/MM/dd', // Alternative ISO
        'dd.MM.yyyy', // European with dots
        'yyyy.MM.dd', // ISO with dots
        'MM.dd.yyyy', // US with dots
      ];

      // Try each format
      for (final format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (_) {
          // Try next format
        }
      }

      // Try direct parse
      try {
        return DateTime.parse(dateStr);
      } catch (_) {}
    } catch (e) {
      debugPrint('❌ Error parsing date: $e');
    }

    return null;
  }

  /// Format date for consistent comparison
  String _formatDateForComparison(DateTime date) {
    return "${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}";
  }

  /// Format month string for display
  String _formatMonth(String monthStr) {
    try {
      // If format is YYYY-MM, convert to month name and year
      if (monthStr.contains('-')) {
        final parts = monthStr.split('-');
        if (parts.length == 2) {
          final year = parts[0];
          final monthNum = int.parse(parts[1]);
          final monthName = _getMonthName(monthNum);
          return "$monthName $year";
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error formatting month: $e');
    }

    // Return original if parsing fails
    return monthStr;
  }

  /// Get month name from number
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

    return ""; // Invalid month number
  }

  /// Send a payment reminder message for an account
  Future<bool> _sendReminderMessage(
    String accountId,
    Map<String, dynamic> data,
    int amountPayable,
    String monthStr,
  ) async {
    try {
      debugPrint('✉️ Sending payment reminder for account: $accountId');

      // Extract customer data
      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      // Skip if no customer ID
      if (customerId.isEmpty) {
        debugPrint(
          '⚠️ No customer ID for account $accountId, skipping reminder',
        );
        return false;
      }

      // Get final customer name (from document or customers collection)
      final String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      // Format account number for privacy
      final String maskedAccountNumber = _maskAccountNumber(accountId);

      // Use current month if month string is empty
      String displayMonth = monthStr;
      if (displayMonth.isEmpty) {
        final now = DateTime.now();
        displayMonth = "${_getMonthName(now.month)} ${now.year}";
      }

      // Create unique message ID
      final String today = _getCurrentDateFormatted();
      final String messageId = 'bill_reminder_${accountId}_$today';

      // Check if message already exists in database
      final existingMessage =
          await _db
              .collection('messages')
              .where('messageId', isEqualTo: messageId)
              .limit(1)
              .get();

      if (existingMessage.docs.isNotEmpty) {
        debugPrint(
          '⚠️ Payment reminder already exists for account $accountId today',
        );
        return true; // Already sent
      }

      // Updated message with more professional tone
      String message =
          "To maintain a good standing with Unicon Finance, please settle your monthly installment of Rs. $amountPayable for $displayMonth on your account $maskedAccountNumber.\n\n"
          "We kindly urge you to make the payment to maintain a positive credit status and avoid any additional charges.\n\n"
          "If you have already made the payment, please disregard this notice.\n\n"
          "Thank you for choosing Unicon Finance.";

      // Create message in Firestore
      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: "Pay Your Monthly Due",
        message: message,
        messageId: messageId,
      );

      debugPrint('✅ Payment reminder sent for account $accountId');
      return true;
    } catch (e) {
      debugPrint('❌ Error sending reminder message: $e');
      return false;
    }
  }

  /// Get customer name from either document or customers collection
  Future<String> _getCustomerName(
    String customerId,
    String customerName,
  ) async {
    String finalName = customerName;

    // If name is empty and we have customer ID, try to get from customers collection
    if (customerId.isNotEmpty && customerName.isEmpty) {
      try {
        final customerDoc =
            await _db.collection('customers').doc(customerId).get();
        if (customerDoc.exists && customerDoc.data() != null) {
          final customerData = customerDoc.data()!;
          finalName =
              customerData['fullName']?.toString() ??
              customerData['customerName']?.toString() ??
              customerData['name']?.toString() ??
              'Customer';
        }
      } catch (e) {
        debugPrint('⚠️ Error getting customer details: $e');
      }
    }

    // Default if still empty
    if (finalName.isEmpty) {
      finalName = 'Customer';
    }

    return finalName;
  }

  /// Mask account number for privacy
  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length > 4) {
      return 'XXXXXXX${accountNumber.substring(accountNumber.length - 4)}';
    }
    return accountNumber;
  }

  /// Create a message in Firestore
  Future<void> _createMessage({
    required String customerId,
    required String customerName,
    required String customerNic,
    required String heading,
    required String message,
    required String messageId,
  }) async {
    try {
      // Double check if message already exists
      final existingMessage =
          await _db
              .collection('messages')
              .where('messageId', isEqualTo: messageId)
              .limit(1)
              .get();

      if (existingMessage.docs.isNotEmpty) {
        debugPrint('⚠️ Message already exists with ID: $messageId');
        return;
      }

      // Get formatted date and time
      final dateFormatted = _getCurrentDateFormatted();
      final timeFormatted = _getCurrentTimeFormatted();

      // Create message document
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
        'deliveryMethod': 'payment_reminder_service',
        'attachments': [],
        'messageId': messageId,
      };

      // Add to messages collection
      final messageRef = await _db.collection('messages').add(messageData);

      debugPrint('📨 Message created with ID: ${messageRef.id}');
    } catch (e) {
      debugPrint('❌ Error creating message: $e');

      // Log error for diagnostics
      try {
        await _db.collection('errorLogs').add({
          'error': e.toString(),
          'timestamp': FieldValue.serverTimestamp(),
          'operation': 'create_payment_reminder',
          'customerId': customerId,
        });
      } catch (_) {}
    }
  }

  /// Format current date as yyyy-MM-dd
  String _getCurrentDateFormatted() {
    final now = DateTime.now();
    return "${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}";
  }

  /// Format current time as hh:mm AM/PM
  String _getCurrentTimeFormatted() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return "${_twoDigits(hour)}:${_twoDigits(now.minute)} $period";
  }

  /// Format number as two digits
  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

  /// Safely parse int values
  int _parseIntSafely(dynamic value) {
    if (value == null) return 0;

    if (value is int) {
      return value;
    } else if (value is double) {
      return value.toInt();
    } else if (value is String) {
      return int.tryParse(value) ?? 0;
    }

    return 0;
  }

  /// Test if an account's billing date matches today (manual testing)
  Future<bool> testAccount(String accountId) async {
    debugPrint('🧪 Testing account $accountId for billing date match');

    try {
      // Update today's date for testing
      _updateTodayDate();

      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('❌ Account $accountId not found');
        return false;
      }

      final data = doc.data()!;

      // Check if account has arrears
      if (!data.containsKey('arrears') || data['arrears'] is! List) {
        debugPrint('❌ No arrears for account $accountId');
        return false;
      }

      final List<dynamic> arrears = data['arrears'] as List<dynamic>;
      bool foundMatch = false;

      // Check each arrear for billing date
      for (int i = 0; i < arrears.length; i++) {
        final arrear = arrears[i];

        if (arrear is! Map) continue;

        final arrearMap = arrear as Map<String, dynamic>;

        // Check for billing date
        if (!arrearMap.containsKey('billingDate')) {
          debugPrint('❌ No billingDate in arrear $i for account $accountId');
          continue;
        }

        // Get billing date
        final billingDateValue = arrearMap['billingDate'];
        if (billingDateValue == null) {
          debugPrint(
            '❌ Billing date is null in arrear $i for account $accountId',
          );
          continue;
        }

        // Normalize billing date
        final String? billingDateFormatted = _normalizeBillingDate(
          billingDateValue,
        );
        if (billingDateFormatted == null) {
          debugPrint(
            '❌ Could not normalize billing date in arrear $i for account $accountId',
          );
          continue;
        }

        debugPrint(
          '🔍 Testing account $accountId arrear $i - billing date: $billingDateFormatted, today: $_todayFormatted',
        );

        // Check if billing date matches today
        if (billingDateFormatted == _todayFormatted) {
          debugPrint('✅ MATCH FOUND in arrear $i for account $accountId');
          foundMatch = true;
        }
      }

      if (!foundMatch) {
        debugPrint('❌ No billing date matches found for account $accountId');
      }

      return foundMatch;
    } catch (e) {
      debugPrint('❌ Error testing account $accountId: $e');
      return false;
    }
  }

  /// Test if an account has arrears (manual testing)
  Future<bool> testArrearsForAccount(String accountId) async {
    debugPrint('🧪 Testing account $accountId for arrears');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('❌ Account $accountId not found');
        return false;
      }

      final data = doc.data()!;
      return _checkForArrears(accountId, data);
    } catch (e) {
      debugPrint('❌ Error testing arrears for account $accountId: $e');
      return false;
    }
  }

  /// Force send reminder for an account for testing
  Future<void> forceSendReminder(String accountId) async {
    debugPrint('🔔 Force sending reminder for account $accountId');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('❌ Account $accountId not found');
        return;
      }

      final data = doc.data()!;

      // Extract amount and month from first non-paid arrear
      int amountPayable = 0;
      String month = '';

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          // Skip if paid
          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          // Get amount
          amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          // Get month
          month = arrearMap['month']?.toString() ?? '';
          break;
        }
      }

      if (amountPayable <= 0) {
        amountPayable =
            _parseIntSafely(data['monthlyInstallment']) > 0
                ? _parseIntSafely(data['monthlyInstallment'])
                : 10000; // Default amount if not found
      }

      // Make sure month includes the year
      final String formattedMonth;
      if (month.isNotEmpty) {
        formattedMonth = _formatMonth(month);
      } else {
        final now = DateTime.now();
        formattedMonth = "${_getMonthName(now.month)} ${now.year}";
      }

      await _sendReminderMessage(
        accountId,
        data,
        amountPayable,
        formattedMonth,
      );
    } catch (e) {
      debugPrint('❌ Error force sending reminder: $e');
    }
  }

  /// Force send arrears reminder for testing
  Future<void> forceSendArrearsReminder(String accountId) async {
    debugPrint('🔔 Force sending arrears reminder for account $accountId');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('❌ Account $accountId not found');
        return;
      }

      final data = doc.data()!;

      // Create dummy arrears data if needed
      List<String> unpaidMonths = [];
      int totalAmount = 0;

      // Try to extract real arrears first
      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          // Skip if paid
          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          // Get amount
          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          // Get month
          final month = arrearMap['month']?.toString() ?? '';
          if (month.isEmpty) continue;

          unpaidMonths.add(_formatMonth(month));
          totalAmount += amountPayable;
        }
      }

      // Use dummy data if no real arrears found
      if (unpaidMonths.isEmpty) {
        final now = DateTime.now();
        final lastMonth = now.month > 1 ? now.month - 1 : 12;
        final lastMonthYear = now.month > 1 ? now.year : now.year - 1;

        unpaidMonths.add("${_getMonthName(lastMonth)} $lastMonthYear");
        totalAmount =
            _parseIntSafely(data['monthlyInstallment']) > 0
                ? _parseIntSafely(data['monthlyInstallment'])
                : 10000;
      }

      await _sendArrearsReminderMessage(
        accountId,
        data,
        unpaidMonths,
        totalAmount,
      );
    } catch (e) {
      debugPrint('❌ Error force sending arrears reminder: $e');
    }
  }

  /// Stop monitoring and clean up resources
  void dispose() {
    _cleanup();
    _processedBillingDates.clear();
    _processedArrearsReminders.clear();
    debugPrint('🧹 Payment reminder service disposed');
  }
}

/// Initializer for the payment reminder service
class PaymentReminderInitializer {
  static bool _isInitialized = false;
  static PaymentReminderService? _service;

  /// Initialize the payment reminder service
  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Payment reminder service already initialized');
      return;
    }

    try {
      debugPrint('🚀 Initializing payment reminder service');

      // Test Firebase access
      try {
        // Test read access
        final testRead =
            await FirebaseFirestore.instance
                .collection('installments')
                .limit(1)
                .get();
        debugPrint(
          '✅ Firebase read test successful: ${testRead.docs.length} docs',
        );

        // Test write access
        final testDoc = await FirebaseFirestore.instance
            .collection('messages')
            .add({'test': true, 'timestamp': FieldValue.serverTimestamp()});
        await testDoc.delete();
        debugPrint('✅ Firebase write test successful');
      } catch (e) {
        debugPrint('⚠️ Firebase permission test failed: $e');
        // Continue anyway, as it might be a permission issue only on test doc
      }

      // Create and start service
      _service = PaymentReminderService();
      await _service!.startMonitoring();

      _isInitialized = true;
      debugPrint('✅ Payment reminder service initialized successfully');

      // Set up automatic restart timer
      _setupAutoRestart();

      // Run diagnostics after short delay
      Future.delayed(Duration(seconds: 15), _runDiagnostics);
    } catch (e) {
      debugPrint('❌ Failed to initialize payment reminder service: $e');
      // Try again after delay
      Future.delayed(Duration(seconds: 30), initialize);
    }
  }

  /// Set up auto-restart mechanism
  static void _setupAutoRestart() {
    // Check every 4 hours if service is running
    Timer.periodic(Duration(hours: 4), (timer) {
      if (!_isInitialized || _service == null) {
        debugPrint('⚠️ Service not running, restarting');
        initialize();
      }
    });
  }

  /// Run diagnostic tests
  static Future<void> _runDiagnostics() async {
    try {
      if (_service == null) return;

      debugPrint('🧪 Running diagnostic tests');

      // Get a few accounts to test
      final accounts =
          await FirebaseFirestore.instance
              .collection('installments')
              .limit(3)
              .get();

      if (accounts.docs.isEmpty) {
        debugPrint('⚠️ No accounts found for testing');
        return;
      }

      // Test each account's billing date
      for (final doc in accounts.docs) {
        final accountId = doc.id;
        final billingDateResult = await _service!.testAccount(accountId);
        debugPrint(
          '📊 Billing date test for $accountId: ${billingDateResult ? "Matches today" : "No match"}',
        );

        // Also test for arrears
        final arrearsResult = await _service!.testArrearsForAccount(accountId);
        debugPrint(
          '📊 Arrears test for $accountId: ${arrearsResult ? "Has arrears" : "No arrears"}',
        );
      }
    } catch (e) {
      debugPrint('❌ Error running diagnostics: $e');
    }
  }

  /// Get the service instance
  static PaymentReminderService? getService() {
    return _service;
  }

  /// Test a specific account
  static Future<bool> testAccount(String accountId) async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return false;
    }

    return _service!.testAccount(accountId);
  }

  /// Test a specific account for arrears
  static Future<bool> testArrearsForAccount(String accountId) async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return false;
    }

    return _service!.testArrearsForAccount(accountId);
  }

  /// Force send a reminder for testing
  static Future<void> forceSendReminder(String accountId) async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return;
    }

    await _service!.forceSendReminder(accountId);
  }

  /// Force send an arrears reminder for testing
  static Future<void> forceSendArrearsReminder(String accountId) async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return;
    }

    await _service!.forceSendArrearsReminder(accountId);
  }

  /// Check all accounts immediately
  static Future<void> checkAllNow() async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return;
    }

    await _service!.checkAllInstallments();
  }

  /// Check all accounts for arrears immediately
  static Future<void> checkAllForArrearsNow() async {
    if (_service == null) {
      debugPrint('❌ Service not initialized');
      return;
    }

    await _service!.checkAllForArrears();
  }

  /// Dispose of the service
  static void dispose() {
    _service?.dispose();
    _service = null;
    _isInitialized = false;
    debugPrint('🔄 Payment reminder service disposed');
  }
}
