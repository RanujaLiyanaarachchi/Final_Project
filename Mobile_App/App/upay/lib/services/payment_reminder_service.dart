import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class PaymentReminderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  StreamSubscription? _installmentsListener;

  final Map<String, Set<String>> _processedBillingDates = {};
  final Map<String, Map<String, Set<String>>> _processedArrearsReminders = {};

  final Set<String> _accountsBeingProcessed = {};

  Timer? _periodicTimer;

  Timer? _arrearsTimer;

  Timer? _midnightTimer;

  late String _todayFormatted;

  bool _isProcessing = false;
  bool _isProcessingArrears = false;

  static final PaymentReminderService _instance =
      PaymentReminderService._internal();

  factory PaymentReminderService() {
    return _instance;
  }

  PaymentReminderService._internal() {
    _updateTodayDate();
    debugPrint(
      'Initializing payment reminder service for date: $_todayFormatted',
    );
  }

  void _updateTodayDate() {
    final now = DateTime.now();
    _todayFormatted = _formatDateForComparison(now);
  }

  Future<void> startMonitoring() async {
    debugPrint('Starting payment reminder service...');

    _updateTodayDate();
    debugPrint('Today is: $_todayFormatted');

    _cleanup();

    try {
      _setupRealtimeMonitoring();

      _setupPeriodicCheck();

      _setupArrearsCheck();

      _setupMidnightReset();

      await checkAllInstallments();

      await checkAllForArrears();

      debugPrint('Payment reminder service running');
    } catch (e) {
      debugPrint('Error starting payment reminder service: $e');
      Future.delayed(const Duration(minutes: 1), startMonitoring);
    }
  }

  void _cleanup() {
    _installmentsListener?.cancel();
    _installmentsListener = null;

    _periodicTimer?.cancel();
    _periodicTimer = null;

    _arrearsTimer?.cancel();
    _arrearsTimer = null;

    _midnightTimer?.cancel();
    _midnightTimer = null;

    _accountsBeingProcessed.clear();
  }

  void _setupRealtimeMonitoring() {
    _installmentsListener = _db
        .collection('installments')
        .snapshots()
        .listen(
          (snapshot) {
            for (final change in snapshot.docChanges) {
              final doc = change.doc;
              final accountId = doc.id;

              if (change.type == DocumentChangeType.added ||
                  change.type == DocumentChangeType.modified) {
                _processBillingDate(accountId, doc.data() ?? {});

                _checkForArrears(accountId, doc.data() ?? {});
              }
            }
          },
          onError: (error) {
            debugPrint('Error in real-time listener: $error');
            Future.delayed(Duration(seconds: 30), () {
              _setupRealtimeMonitoring();
            });
          },
        );

    debugPrint('Installments real-time monitoring established');
  }

  void _setupPeriodicCheck() {
    _periodicTimer = Timer.periodic(Duration(minutes: 30), (_) async {
      debugPrint('Running periodic installments check');
      await checkAllInstallments();
    });
  }

  void _setupArrearsCheck() {
    final now = DateTime.now();
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
    );

    Duration timeUntilCheck;
    if (now.isAfter(morning)) {
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 9, 0);
      timeUntilCheck = tomorrow.difference(now);
    } else {
      timeUntilCheck = morning.difference(now);
    }

    Timer(timeUntilCheck, () {
      checkAllForArrears();

      _arrearsTimer = Timer.periodic(Duration(hours: 24), (_) {
        checkAllForArrears();
      });
    });

    debugPrint(
      'Arrears check scheduled in ${timeUntilCheck.inHours}h ${timeUntilCheck.inMinutes % 60}m',
    );
  }

  void _setupMidnightReset() {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final timeUntilMidnight = tomorrow.difference(now);

    _midnightTimer = Timer(timeUntilMidnight, () {
      _processedBillingDates.clear();
      _processedArrearsReminders.clear();
      _accountsBeingProcessed.clear();

      _updateTodayDate();
      debugPrint('Midnight reset - new date: $_todayFormatted');

      checkAllInstallments();
      checkAllForArrears();

      _setupMidnightReset();
    });

    debugPrint(
      'Midnight reset scheduled in ${timeUntilMidnight.inHours}h ${timeUntilMidnight.inMinutes % 60}m',
    );
  }

  Future<void> checkAllInstallments() async {
    if (_isProcessing) {
      debugPrint('Check already in progress, skipping');
      return;
    }

    _isProcessing = true;

    try {
      debugPrint(
        'Checking all installments for billing dates matching today: $_todayFormatted',
      );

      _updateTodayDate();

      final snapshot = await _db.collection('installments').get();
      debugPrint('Found ${snapshot.docs.length} installment accounts');

      int matchCount = 0;

      for (final doc in snapshot.docs) {
        final accountId = doc.id;
        final data = doc.data();

        if (await _processBillingDate(accountId, data)) {
          matchCount++;
        }
      }

      debugPrint(
        'Check completed - found $matchCount accounts with billing date matching today',
      );
    } catch (e) {
      debugPrint('Error checking all installments: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> checkAllForArrears() async {
    if (_isProcessingArrears) {
      debugPrint('Arrears check already in progress, skipping');
      return;
    }

    _isProcessingArrears = true;

    try {
      debugPrint('Checking all installments for arrears');

      final snapshot = await _db.collection('installments').get();

      int accountsWithArrears = 0;

      for (final doc in snapshot.docs) {
        final accountId = doc.id;
        final data = doc.data();

        if (await _checkForArrears(accountId, data)) {
          accountsWithArrears++;
        }
      }

      debugPrint(
        'Arrears check completed - found $accountsWithArrears accounts with arrears',
      );
    } catch (e) {
      debugPrint('Error checking for arrears: $e');
    } finally {
      _isProcessingArrears = false;
    }
  }

  Future<bool> _processBillingDate(
    String accountId,
    Map<String, dynamic> data,
  ) async {
    try {
      bool sentMessage = false;

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        if (!_processedBillingDates.containsKey(accountId)) {
          _processedBillingDates[accountId] = {};
        }

        for (int i = 0; i < arrears.length; i++) {
          final arrear = arrears[i];

          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          if (!arrearMap.containsKey('billingDate')) continue;

          final billingDateValue = arrearMap['billingDate'];
          if (billingDateValue == null) continue;

          final month = arrearMap['month']?.toString() ?? '';
          final formattedMonth = _formatMonth(month);

          final String? billingDateFormatted = _normalizeBillingDate(
            billingDateValue,
          );
          if (billingDateFormatted == null) continue;

          debugPrint(
            'Account $accountId arrear $i: billing date $billingDateFormatted vs today $_todayFormatted',
          );

          if (billingDateFormatted == _todayFormatted) {
            final billingKey = '$accountId-$i-$billingDateFormatted';

            if (_processedBillingDates[accountId]!.contains(billingKey)) {
              debugPrint(
                'Already sent reminder for account $accountId arrear $i',
              );
              continue;
            }

            if (await _sendReminderMessage(
              accountId,
              data,
              amountPayable,
              formattedMonth,
            )) {
              _processedBillingDates[accountId]!.add(billingKey);
              sentMessage = true;

              break;
            }
          }
        }
      }

      return sentMessage;
    } catch (e) {
      debugPrint('Error processing billing date for account $accountId: $e');
      return false;
    }
  }

  Future<bool> _checkForArrears(
    String accountId,
    Map<String, dynamic> data,
  ) async {
    try {
      if (_accountsBeingProcessed.contains(accountId)) {
        debugPrint('Account $accountId is already being processed for arrears');
        return false;
      }

      _accountsBeingProcessed.add(accountId);

      try {
        if (!data.containsKey('arrears') || data['arrears'] is! List) {
          return false;
        }

        final List<dynamic> arrears = data['arrears'] as List<dynamic>;
        final List<String> unpaidMonths = [];
        final Set<String> unpaidMonthCodes = {};
        int totalArrearsAmount = 0;

        final now = DateTime.now();

        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          final month = arrearMap['month']?.toString() ?? '';
          if (month.isEmpty) continue;

          bool isPastDue = false;

          if (arrearMap.containsKey('billingDate')) {
            final billingDateValue = arrearMap['billingDate'];
            if (billingDateValue != null) {
              final String? billingDateFormatted = _normalizeBillingDate(
                billingDateValue,
              );
              if (billingDateFormatted != null) {
                final billingDate = _parseAnyDateFormat(billingDateFormatted);
                if (billingDate != null) {
                  final yesterday = DateTime(now.year, now.month, now.day - 1);
                  if (billingDate.isBefore(yesterday)) {
                    isPastDue = true;
                  }
                }
              }
            }
          } else {
            try {
              if (month.contains('-')) {
                final parts = month.split('-');
                if (parts.length == 2) {
                  final year = int.parse(parts[0]);
                  final monthNum = int.parse(parts[1]);

                  if (year < now.year ||
                      (year == now.year && monthNum < now.month)) {
                    isPastDue = true;
                  }
                }
              }
            } catch (e) {
              debugPrint('Error parsing month for arrears: $e');
            }
          }

          if (isPastDue) {
            final formattedMonth = _formatMonth(month);
            unpaidMonths.add(formattedMonth);

            final monthCode = month.replaceAll(' ', '_').toLowerCase();
            unpaidMonthCodes.add(monthCode);

            totalArrearsAmount += amountPayable;
          }
        }

        if (unpaidMonths.isNotEmpty) {
          bool shouldSendMessage = false;

          if (!_processedArrearsReminders.containsKey(accountId)) {
            _processedArrearsReminders[accountId] = {'months': {}};
            shouldSendMessage = true;
          }

          if (!shouldSendMessage) {
            final processedMonths =
                _processedArrearsReminders[accountId]?['months'] ?? {};

            for (final monthCode in unpaidMonthCodes) {
              if (!processedMonths.contains(monthCode)) {
                shouldSendMessage = true;
                debugPrint(
                  'New unpaid month found: $monthCode for account $accountId',
                );
                break;
              }
            }
          }

          if (shouldSendMessage) {
            await _sendArrearsReminderMessage(
              accountId,
              data,
              unpaidMonths,
              totalArrearsAmount,
            );

            if (!_processedArrearsReminders[accountId]!.containsKey('months')) {
              _processedArrearsReminders[accountId]!['months'] = {};
            }

            _processedArrearsReminders[accountId]!['months']!.addAll(
              unpaidMonthCodes,
            );

            debugPrint(
              'Sent arrears reminder for account $accountId with ${unpaidMonths.length} months',
            );
            return true;
          } else {
            debugPrint(
              'No new arrears months for account $accountId, skipping reminder',
            );
          }
        }

        return false;
      } finally {
        _accountsBeingProcessed.remove(accountId);
      }
    } catch (e) {
      _accountsBeingProcessed.remove(accountId);
      debugPrint('Error checking arrears for account $accountId: $e');
      return false;
    }
  }

  Future<bool> _sendArrearsReminderMessage(
    String accountId,
    Map<String, dynamic> data,
    List<String> unpaidMonths,
    int totalAmount,
  ) async {
    try {
      debugPrint('Sending arrears reminder for account: $accountId');

      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      if (customerId.isEmpty) {
        debugPrint(
          'No customer ID for account $accountId, skipping arrears reminder',
        );
        return false;
      }

      final String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      final String maskedAccountNumber = _maskAccountNumber(accountId);

      final String today = _getCurrentDateFormatted();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final String messageId = 'arrears_${accountId}_${today}_$timestamp';

      String message;

      if (unpaidMonths.length == 1) {
        message =
            "This is a reminder from Unicon Finance regarding your finance account $maskedAccountNumber. "
            "As of today, you have an outstanding arrears amount of Rs. $totalAmount for ${unpaidMonths[0]}.\n\n"
            "Kindly settle the due amount at your earliest convenience to avoid penalties or disruption of services.\n\n"
            "If payment has already been made, please disregard this notice.\n\n"
            "Thank you for your continued trust in Unicon Finance.";
      } else {
        message =
            "This is to inform you that your finance account $maskedAccountNumber with Unicon Finance "
            "has an outstanding arrears balance of Rs. $totalAmount covering the following months:\n\n";

        for (final month in unpaidMonths) {
          message += "• $month\n";
        }

        message +=
            "\nWe kindly urge you to clear the dues to maintain a positive credit standing and avoid additional charges.\n\n"
            "If payment has already been made, please disregard this notice.\n\n"
            "Thank you for choosing Unicon Finance.";
      }

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: "Arrears Notice",
        message: message,
        messageId: messageId,
      );

      debugPrint('Arrears reminder sent for account $accountId');
      return true;
    } catch (e) {
      debugPrint('Error sending arrears reminder: $e');
      return false;
    }
  }

  String? _normalizeBillingDate(dynamic billingDateValue) {
    try {
      if (billingDateValue is String) {
        final cleanStr = billingDateValue.trim();

        DateTime? date = _parseAnyDateFormat(cleanStr);
        if (date != null) {
          return _formatDateForComparison(date);
        }

        if (cleanStr.length <= 2) {
          final day = int.tryParse(cleanStr);
          if (day != null && day >= 1 && day <= 31) {
            final now = DateTime.now();
            return _formatDateForComparison(DateTime(now.year, now.month, day));
          }
        }

        return cleanStr;
      } else if (billingDateValue is Timestamp) {
        return _formatDateForComparison(billingDateValue.toDate());
      } else if (billingDateValue is int) {
        final now = DateTime.now();
        return _formatDateForComparison(
          DateTime(now.year, now.month, billingDateValue),
        );
      }
    } catch (e) {
      debugPrint('Error normalizing billing date: $e');
    }

    return null;
  }

  DateTime? _parseAnyDateFormat(String dateStr) {
    try {
      final formats = [
        'yyyy-MM-dd',
        'dd-MM-yyyy',
        'MM/dd/yyyy',
        'dd/MM/yyyy',
        'yyyy/MM/dd',
        'dd.MM.yyyy',
        'yyyy.MM.dd',
        'MM.dd.yyyy',
      ];

      for (final format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (_) {}
      }

      try {
        return DateTime.parse(dateStr);
      } catch (_) {}
    } catch (e) {
      debugPrint('Error parsing date: $e');
    }

    return null;
  }

  String _formatDateForComparison(DateTime date) {
    return "${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}";
  }

  String _formatMonth(String monthStr) {
    try {
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
      debugPrint('Error formatting month: $e');
    }

    return monthStr;
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

    return "";
  }

  Future<bool> _sendReminderMessage(
    String accountId,
    Map<String, dynamic> data,
    int amountPayable,
    String monthStr,
  ) async {
    try {
      debugPrint('Sending payment reminder for account: $accountId');

      final String customerId = data['customerId']?.toString() ?? '';
      final String customerName = data['customerName']?.toString() ?? '';
      final String customerNic = data['nic']?.toString() ?? '';

      if (customerId.isEmpty) {
        debugPrint('No customer ID for account $accountId, skipping reminder');
        return false;
      }

      final String finalCustomerName = await _getCustomerName(
        customerId,
        customerName,
      );

      final String maskedAccountNumber = _maskAccountNumber(accountId);

      String displayMonth = monthStr;
      if (displayMonth.isEmpty) {
        final now = DateTime.now();
        displayMonth = "${_getMonthName(now.month)} ${now.year}";
      }

      final String today = _getCurrentDateFormatted();
      final String messageId = 'bill_reminder_${accountId}_$today';

      final existingMessage =
          await _db
              .collection('messages')
              .where('messageId', isEqualTo: messageId)
              .limit(1)
              .get();

      if (existingMessage.docs.isNotEmpty) {
        debugPrint(
          'Payment reminder already exists for account $accountId today',
        );
        return true;
      }

      String message =
          "To maintain a good standing with Unicon Finance, please settle your monthly installment of Rs. $amountPayable for $displayMonth on your account $maskedAccountNumber.\n\n"
          "We kindly urge you to make the payment to maintain a positive credit status and avoid any additional charges.\n\n"
          "If you have already made the payment, please disregard this notice.\n\n"
          "Thank you for choosing Unicon Finance.";

      await _createMessage(
        customerId: customerId,
        customerName: finalCustomerName,
        customerNic: customerNic,
        heading: "Pay Your Monthly Due",
        message: message,
        messageId: messageId,
      );

      debugPrint('Payment reminder sent for account $accountId');
      return true;
    } catch (e) {
      debugPrint('Error sending reminder message: $e');
      return false;
    }
  }

  Future<String> _getCustomerName(
    String customerId,
    String customerName,
  ) async {
    String finalName = customerName;

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
        debugPrint('Error getting customer details: $e');
      }
    }

    if (finalName.isEmpty) {
      finalName = 'Customer';
    }

    return finalName;
  }

  String _maskAccountNumber(String accountNumber) {
    if (accountNumber.length > 4) {
      return 'XXXXXXX${accountNumber.substring(accountNumber.length - 4)}';
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
    try {
      final existingMessage =
          await _db
              .collection('messages')
              .where('messageId', isEqualTo: messageId)
              .limit(1)
              .get();

      if (existingMessage.docs.isNotEmpty) {
        debugPrint('Message already exists with ID: $messageId');
        return;
      }

      final dateFormatted = _getCurrentDateFormatted();
      final timeFormatted = _getCurrentTimeFormatted();

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

      final messageRef = await _db.collection('messages').add(messageData);

      debugPrint('Message created with ID: ${messageRef.id}');
    } catch (e) {
      debugPrint('Error creating message: $e');

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

  String _getCurrentDateFormatted() {
    final now = DateTime.now();
    return "${now.year}-${_twoDigits(now.month)}-${_twoDigits(now.day)}";
  }

  String _getCurrentTimeFormatted() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour >= 12 ? 'PM' : 'AM';
    return "${_twoDigits(hour)}:${_twoDigits(now.minute)} $period";
  }

  String _twoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }

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

  Future<bool> testAccount(String accountId) async {
    debugPrint('Testing account $accountId for billing date match');

    try {
      _updateTodayDate();

      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountId not found');
        return false;
      }

      final data = doc.data()!;

      if (!data.containsKey('arrears') || data['arrears'] is! List) {
        debugPrint('No arrears for account $accountId');
        return false;
      }

      final List<dynamic> arrears = data['arrears'] as List<dynamic>;
      bool foundMatch = false;

      for (int i = 0; i < arrears.length; i++) {
        final arrear = arrears[i];

        if (arrear is! Map) continue;

        final arrearMap = arrear as Map<String, dynamic>;

        if (!arrearMap.containsKey('billingDate')) {
          debugPrint('No billingDate in arrear $i for account $accountId');
          continue;
        }

        final billingDateValue = arrearMap['billingDate'];
        if (billingDateValue == null) {
          debugPrint(
            'Billing date is null in arrear $i for account $accountId',
          );
          continue;
        }

        final String? billingDateFormatted = _normalizeBillingDate(
          billingDateValue,
        );
        if (billingDateFormatted == null) {
          debugPrint(
            'Could not normalize billing date in arrear $i for account $accountId',
          );
          continue;
        }

        debugPrint(
          'Testing account $accountId arrear $i - billing date: $billingDateFormatted, today: $_todayFormatted',
        );

        if (billingDateFormatted == _todayFormatted) {
          debugPrint('MATCH FOUND in arrear $i for account $accountId');
          foundMatch = true;
        }
      }

      if (!foundMatch) {
        debugPrint('No billing date matches found for account $accountId');
      }

      return foundMatch;
    } catch (e) {
      debugPrint('Error testing account $accountId: $e');
      return false;
    }
  }

  Future<bool> testArrearsForAccount(String accountId) async {
    debugPrint('Testing account $accountId for arrears');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountId not found');
        return false;
      }

      final data = doc.data()!;
      return _checkForArrears(accountId, data);
    } catch (e) {
      debugPrint('Error testing arrears for account $accountId: $e');
      return false;
    }
  }

  Future<void> forceSendReminder(String accountId) async {
    debugPrint('Force sending reminder for account $accountId');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountId not found');
        return;
      }

      final data = doc.data()!;

      int amountPayable = 0;
      String month = '';

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          month = arrearMap['month']?.toString() ?? '';
          break;
        }
      }

      if (amountPayable <= 0) {
        amountPayable =
            _parseIntSafely(data['monthlyInstallment']) > 0
                ? _parseIntSafely(data['monthlyInstallment'])
                : 10000;
      }

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
      debugPrint('Error force sending reminder: $e');
    }
  }

  Future<void> forceSendArrearsReminder(String accountId) async {
    debugPrint('Force sending arrears reminder for account $accountId');

    try {
      final doc = await _db.collection('installments').doc(accountId).get();
      if (!doc.exists || doc.data() == null) {
        debugPrint('Account $accountId not found');
        return;
      }

      final data = doc.data()!;

      List<String> unpaidMonths = [];
      int totalAmount = 0;

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final List<dynamic> arrears = data['arrears'] as List<dynamic>;

        for (final arrear in arrears) {
          if (arrear is! Map) continue;

          final arrearMap = arrear as Map<String, dynamic>;

          final status = arrearMap['status']?.toString().toLowerCase() ?? '';
          if (status == 'paid') continue;

          final amountPayable = _parseIntSafely(arrearMap['amountPayable']);
          if (amountPayable <= 0) continue;

          final month = arrearMap['month']?.toString() ?? '';
          if (month.isEmpty) continue;

          unpaidMonths.add(_formatMonth(month));
          totalAmount += amountPayable;
        }
      }

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
      debugPrint('Error force sending arrears reminder: $e');
    }
  }

  void dispose() {
    _cleanup();
    _processedBillingDates.clear();
    _processedArrearsReminders.clear();
    debugPrint('Payment reminder service disposed');
  }
}

class PaymentReminderInitializer {
  static bool _isInitialized = false;
  static PaymentReminderService? _service;

  static Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('Payment reminder service already initialized');
      return;
    }

    try {
      debugPrint('Initializing payment reminder service');

      try {
        final testRead =
            await FirebaseFirestore.instance
                .collection('installments')
                .limit(1)
                .get();
        debugPrint(
          'Firebase read test successful: ${testRead.docs.length} docs',
        );

        final testDoc = await FirebaseFirestore.instance
            .collection('messages')
            .add({'test': true, 'timestamp': FieldValue.serverTimestamp()});
        await testDoc.delete();
        debugPrint('Firebase write test successful');
      } catch (e) {
        debugPrint('Firebase permission test failed: $e');
      }

      _service = PaymentReminderService();
      await _service!.startMonitoring();

      _isInitialized = true;
      debugPrint('Payment reminder service initialized successfully');

      _setupAutoRestart();

      Future.delayed(Duration(seconds: 15), _runDiagnostics);
    } catch (e) {
      debugPrint('Failed to initialize payment reminder service: $e');
      Future.delayed(Duration(seconds: 30), initialize);
    }
  }

  static void _setupAutoRestart() {
    Timer.periodic(Duration(hours: 4), (timer) {
      if (!_isInitialized || _service == null) {
        debugPrint('Service not running, restarting');
        initialize();
      }
    });
  }

  static Future<void> _runDiagnostics() async {
    try {
      if (_service == null) return;

      debugPrint('Running diagnostic tests');

      final accounts =
          await FirebaseFirestore.instance
              .collection('installments')
              .limit(3)
              .get();

      if (accounts.docs.isEmpty) {
        debugPrint('No accounts found for testing');
        return;
      }

      for (final doc in accounts.docs) {
        final accountId = doc.id;
        final billingDateResult = await _service!.testAccount(accountId);
        debugPrint(
          'Billing date test for $accountId: ${billingDateResult ? "Matches today" : "No match"}',
        );

        final arrearsResult = await _service!.testArrearsForAccount(accountId);
        debugPrint(
          'Arrears test for $accountId: ${arrearsResult ? "Has arrears" : "No arrears"}',
        );
      }
    } catch (e) {
      debugPrint('Error running diagnostics: $e');
    }
  }

  static PaymentReminderService? getService() {
    return _service;
  }

  static Future<bool> testAccount(String accountId) async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return false;
    }

    return _service!.testAccount(accountId);
  }

  static Future<bool> testArrearsForAccount(String accountId) async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return false;
    }

    return _service!.testArrearsForAccount(accountId);
  }

  static Future<void> forceSendReminder(String accountId) async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return;
    }

    await _service!.forceSendReminder(accountId);
  }

  static Future<void> forceSendArrearsReminder(String accountId) async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return;
    }

    await _service!.forceSendArrearsReminder(accountId);
  }

  static Future<void> checkAllNow() async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return;
    }

    await _service!.checkAllInstallments();
  }

  static Future<void> checkAllForArrearsNow() async {
    if (_service == null) {
      debugPrint('Service not initialized');
      return;
    }

    await _service!.checkAllForArrears();
  }

  static void dispose() {
    _service?.dispose();
    _service = null;
    _isInitialized = false;
    debugPrint('Payment reminder service disposed');
  }
}
