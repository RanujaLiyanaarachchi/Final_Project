import 'package:flutter/material.dart';
import 'package:upay/screens/profile_screen.dart';
import 'package:upay/screens/notification_screen.dart';
import 'package:upay/screens/liability_screen.dart';
import 'package:upay/screens/payment_screen.dart';
import 'package:upay/screens/bill_screen.dart';
import 'package:upay/screens/support_screen.dart';
import 'package:upay/screens/settings_screen.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;

  late final PageController _pageController;

  final List<Widget> _screens = [
    const DashboardHome(),
    const SupportScreen(),
    const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _onNavItemTapped(int index) {
    _pageController.jumpToPage(index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const NeverScrollableScrollPhysics(),
        children: _screens,
      ),
      bottomNavigationBar: _buildNavBarWithTopIndicator(),
    );
  }

  Widget _buildNavBarWithTopIndicator() {
    final indicatorWidth = MediaQuery.of(context).size.width / 3;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      height: 80,
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            left: indicatorWidth * _currentIndex,
            child: Container(
              height: 4,
              width: indicatorWidth,
              color: const Color.fromARGB(255, 120, 25, 137),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(3, (index) {
              final icons = [
                [Icons.home_rounded, Icons.home_outlined],
                [Icons.support_agent, Icons.support_agent_outlined],
                [Icons.settings_rounded, Icons.settings_outlined],
              ];

              final isSelected = _currentIndex == index;

              return Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _onNavItemTapped(index),
                  child: SizedBox(
                    height: double.infinity,
                    child: Icon(
                      isSelected ? icons[index][0] : icons[index][1],
                      color: const Color.fromARGB(255, 120, 25, 137),
                      size: 32,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class DashboardHome extends StatefulWidget {
  const DashboardHome({super.key});

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome>
    with AutomaticKeepAliveClientMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _firstName = 'User';
  String? _profileImageUrl;
  String _userId = '';
  String _nic = '';
  String _customerId = '';
  String _accountNumber = '';

  String _liabilitiesAmount = 'LKR. 000,000.00';
  bool _isLoanCompleted = false;

  String _nextInstallmentDate = '00/00/0000';
  String _lastPaymentDate = '';
  String _monthlyInstallmentDate = '00/00/0000';
  bool _isMonthlyInstallmentPaid = false;

  double _amountPayable = 0.0;
  double _nextInstallmentAmount = 0000.0;

  String _nextInstallmentMonth = '';
  String _nextInstallmentStatus = '';
  final Map<String, Map<String, dynamic>> _installmentsByMonth = {};

  double _totalArrearsAmount = 0.0;
  bool _hasArrears = false;

  bool _showMonthlyInstallment = true;

  int _unreadNotificationsCount = 0;

  StreamSubscription<QuerySnapshot>? _installmentSubscription;
  StreamSubscription<QuerySnapshot>? _notificationsSubscription;
  StreamSubscription<QuerySnapshot>? _paymentsSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _installmentSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _paymentsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      await _loadUserData();
      _setupRealTimeStreams();
      await _loadUnreadNotificationsCount();
      await _loadLastPayment();
    } catch (e) {
      debugPrint('Error loading data: $e');
    }
  }

  void _setupRealTimeStreams() {
    _installmentSubscription?.cancel();
    _notificationsSubscription?.cancel();
    _paymentsSubscription?.cancel();

    if (_nic.isEmpty && _customerId.isEmpty && _accountNumber.isEmpty) return;

    Query? installmentsQuery;
    if (_nic.isNotEmpty) {
      installmentsQuery = _firestore
          .collection('installments')
          .where('nic', isEqualTo: _nic);
    } else if (_customerId.isNotEmpty) {
      installmentsQuery = _firestore
          .collection('installments')
          .where('customerId', isEqualTo: _customerId);
    } else if (_accountNumber.isNotEmpty) {
      installmentsQuery = _firestore
          .collection('installments')
          .where('accountNumber', isEqualTo: _accountNumber);
    }

    if (installmentsQuery != null) {
      _installmentSubscription = installmentsQuery.snapshots().listen((
        snapshot,
      ) {
        if (snapshot.docs.isNotEmpty) {
          _processInstallmentData(snapshot.docs.first);
        }
      });
    }

    Query? notificationsQuery;
    if (_nic.isNotEmpty) {
      notificationsQuery = _firestore
          .collection('messages')
          .where('customerNic', isEqualTo: _nic);
    } else if (_customerId.isNotEmpty) {
      notificationsQuery = _firestore
          .collection('messages')
          .where('customerId', isEqualTo: _customerId);
    }

    if (notificationsQuery != null) {
      _notificationsSubscription = notificationsQuery.snapshots().listen((
        snapshot,
      ) {
        final unreadCount =
            snapshot.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['isRead'] == false;
            }).length;

        if (mounted) {
          setState(() => _unreadNotificationsCount = unreadCount);
        }
      });
    }

    Query? paymentsQuery;
    if (_customerId.isNotEmpty) {
      paymentsQuery = _firestore
          .collection('payments')
          .where('customerId', isEqualTo: _customerId)
          .orderBy('paymentDate', descending: true)
          .limit(1);
    } else if (_nic.isNotEmpty) {
      paymentsQuery = _firestore
          .collection('payments')
          .where('nic', isEqualTo: _nic)
          .orderBy('paymentDate', descending: true)
          .limit(1);
    } else if (_accountNumber.isNotEmpty) {
      paymentsQuery = _firestore
          .collection('payments')
          .where('accountNumber', isEqualTo: _accountNumber)
          .orderBy('paymentDate', descending: true)
          .limit(1);
    }

    if (paymentsQuery != null) {
      _paymentsSubscription = paymentsQuery.snapshots().listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
          _processPaymentData(snapshot.docs.first);
        }
      });
    }
  }

  Future<void> _loadLastPayment() async {
    try {
      Query? query;

      if (_customerId.isNotEmpty) {
        query = _firestore
            .collection('payments')
            .where('customerId', isEqualTo: _customerId)
            .orderBy('paymentDate', descending: true)
            .limit(1);
      } else if (_nic.isNotEmpty) {
        query = _firestore
            .collection('payments')
            .where('nic', isEqualTo: _nic)
            .orderBy('paymentDate', descending: true)
            .limit(1);
      } else if (_accountNumber.isNotEmpty) {
        query = _firestore
            .collection('payments')
            .where('accountNumber', isEqualTo: _accountNumber)
            .orderBy('paymentDate', descending: true)
            .limit(1);
      }

      if (query != null) {
        final snapshot = await query.get();
        if (snapshot.docs.isNotEmpty) {
          _processPaymentData(snapshot.docs.first);
        }
      }
    } catch (e) {
      debugPrint('Error loading last payment: $e');
    }
  }

  void _processPaymentData(DocumentSnapshot doc) {
    if (!mounted) return;

    try {
      final data = doc.data() as Map<String, dynamic>;

      String formattedPaymentDate = '';
      if (data.containsKey('paymentDate')) {
        try {
          dynamic paymentDate = data['paymentDate'];
          if (paymentDate is Timestamp) {
            formattedPaymentDate = DateFormat(
              'dd/MM/yyyy',
            ).format(paymentDate.toDate());
          } else if (paymentDate is String) {
            final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
            if (regex.hasMatch(paymentDate)) {
              final parts = paymentDate.split('-');
              formattedPaymentDate = '${parts[2]}/${parts[1]}/${parts[0]}';
            } else {
              try {
                DateTime parsedDate = DateTime.parse(paymentDate);
                formattedPaymentDate = DateFormat(
                  'dd/MM/yyyy',
                ).format(parsedDate);
              } catch (e) {
                formattedPaymentDate = paymentDate;
              }
            }
          }
        } catch (e) {
          debugPrint('Error parsing payment date: $e');
        }
      }

      bool isMonthlyPayment = false;
      if (data.containsKey('paymentType')) {
        final paymentType = data['paymentType'].toString().toLowerCase();
        isMonthlyPayment =
            paymentType.contains('monthly') ||
            paymentType.contains('install') ||
            paymentType.contains('completed');
      }

      final now = DateTime.now();
      bool isCurrentMonthPayment = false;
      DateTime? paymentDateTime;

      if (data.containsKey('paymentDate')) {
        try {
          dynamic paymentDate = data['paymentDate'];

          if (paymentDate is Timestamp) {
            paymentDateTime = paymentDate.toDate();
          } else if (paymentDate is String) {
            try {
              paymentDateTime = DateTime.parse(paymentDate);
            } catch (_) {
              if (paymentDate.contains('-') &&
                  paymentDate.split('-').length == 3) {
                final parts = paymentDate.split('-');
                paymentDateTime = DateTime(
                  int.parse(parts[0]),
                  int.parse(parts[1]),
                  int.parse(parts[2]),
                );
              }
            }
          }

          if (paymentDateTime != null) {
            isCurrentMonthPayment =
                paymentDateTime.year == now.year &&
                paymentDateTime.month == now.month;
          }
        } catch (e) {
          debugPrint('Error checking if payment is current: $e');
        }
      }

      if (formattedPaymentDate.isNotEmpty) {
        setState(() {
          _lastPaymentDate = formattedPaymentDate;

          if (isCurrentMonthPayment && isMonthlyPayment) {
            _isMonthlyInstallmentPaid = true;

            if (!_hasArrears) {
              _showMonthlyInstallment = false;
            } else {
              _showMonthlyInstallment = true;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error processing payment data: $e');
    }
  }

  Future<void> _loadUserData() async {
    try {
      final User? currentUser = _auth.currentUser;
      _userId = currentUser?.uid ?? '';

      final nic = await SecureStorageService.getUserNic();
      if (nic == null || nic.isEmpty) return;

      setState(() => _nic = nic);

      final QuerySnapshot snapshot =
          await _firestore
              .collection('customers')
              .where('nic', isEqualTo: nic)
              .limit(1)
              .get();

      if (snapshot.docs.isNotEmpty) {
        _updateUserDataFromDocument(snapshot.docs.first);
        await _loadProfileImage();
        return;
      }

      if (nic.length == 10) {
        String alternativeNic;
        if (nic.endsWith('v')) {
          alternativeNic = '${nic.substring(0, 9)}V';
        } else if (nic.endsWith('V')) {
          alternativeNic = '${nic.substring(0, 9)}v';
        } else {
          alternativeNic = nic;
        }

        if (alternativeNic != nic) {
          final alternativeSnapshot =
              await _firestore
                  .collection('customers')
                  .where('nic', isEqualTo: alternativeNic)
                  .limit(1)
                  .get();

          if (alternativeSnapshot.docs.isNotEmpty) {
            _updateUserDataFromDocument(alternativeSnapshot.docs.first);
            await _loadProfileImage();
            return;
          }
        }
      }

      if (currentUser != null && currentUser.phoneNumber != null) {
        final phoneSnapshot =
            await _firestore
                .collection('customers')
                .where('mobile', isEqualTo: currentUser.phoneNumber)
                .limit(1)
                .get();

        if (phoneSnapshot.docs.isNotEmpty) {
          _updateUserDataFromDocument(phoneSnapshot.docs.first);
          await _loadProfileImage();
        }
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _loadUnreadNotificationsCount() async {
    if (!mounted) return;

    try {
      if (_auth.currentUser == null) {
        final isLoggedIn = await SecureStorageService.isUserLoggedIn();
        if (isLoggedIn) {
          try {
            await _auth.signInAnonymously();
          } catch (e) {
            debugPrint('Ignore auth errors');
          }
        }
      }

      final nic = await SecureStorageService.getUserNic();
      final customerId = await SecureStorageService.getUserCustomerId();

      if (nic == null && customerId == null) {
        setState(() => _unreadNotificationsCount = 0);
        return;
      }

      Query? query;
      if (nic != null && nic.isNotEmpty) {
        query = _firestore
            .collection('messages')
            .where('customerNic', isEqualTo: nic);
      } else if (customerId != null && customerId.isNotEmpty) {
        query = _firestore
            .collection('messages')
            .where('customerId', isEqualTo: customerId);
      }

      if (query != null) {
        final snapshot = await query.get();
        final unreadMessages =
            snapshot.docs.where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['isRead'] == false;
            }).toList();

        if (mounted) {
          setState(() => _unreadNotificationsCount = unreadMessages.length);
        }
      }
    } catch (e) {
      debugPrint('Error in loadUnreadNotificationsCount: $e');
    }
  }

  void _updateUserDataFromDocument(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>;

      String firstName = '';
      if (data.containsKey('firstName') && data['firstName'] != null) {
        firstName = data['firstName'];
      } else if (data.containsKey('fullName') && data['fullName'] != null) {
        final fullName = data['fullName'].toString();
        firstName = fullName.contains(' ') ? fullName.split(' ')[0] : fullName;
      } else if (data.containsKey('name') && data['name'] != null) {
        final name = data['name'].toString();
        firstName = name.contains(' ') ? name.split(' ')[0] : name;
      }

      String? docProfileImageUrl;
      for (final field in [
        'profileImage',
        'profileImageUrl',
        'photoURL',
        'photoUrl',
        'image',
      ]) {
        if (data.containsKey(field) && data[field] != null) {
          docProfileImageUrl = data[field];
          break;
        }
      }

      String accountNumber = '';
      if (data.containsKey('accountNumber') && data['accountNumber'] != null) {
        accountNumber = data['accountNumber'].toString();
      }

      if (mounted) {
        setState(() {
          _customerId =
              data['customerId'] ??
              data['customerID'] ??
              data['customerNo'] ??
              doc.id;

          if (accountNumber.isNotEmpty) {
            _accountNumber = accountNumber;
          }

          if (firstName.isNotEmpty) {
            _firstName = firstName;
          }

          if (docProfileImageUrl != null && docProfileImageUrl.isNotEmpty) {
            _profileImageUrl = docProfileImageUrl;
          }
        });
      }
    } catch (e) {
      debugPrint('Error updating user data: $e');
    }
  }

  Future<void> _loadProfileImage() async {
    if (!mounted) return;

    try {
      if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
        return;
      }

      final cachedUrl = await SecureStorageService.getProfileImageUrl();
      if (cachedUrl != null && cachedUrl.isNotEmpty && mounted) {
        setState(() => _profileImageUrl = cachedUrl);
        return;
      }

      List<String> identifiers = [];
      if (_userId.isNotEmpty) identifiers.add(_userId);
      if (_customerId.isNotEmpty) identifiers.add(_customerId);
      if (_nic.isNotEmpty) identifiers.add(_nic);

      if (identifiers.isEmpty) return;

      try {
        final listResult = await _storage.ref('customer_images').listAll();

        for (final id in identifiers) {
          for (var item in listResult.items) {
            if (item.name.contains(id)) {
              try {
                final url = await item.getDownloadURL();
                if (mounted) {
                  setState(() => _profileImageUrl = url);
                  await SecureStorageService.saveProfileImageUrl(url);
                }
                return;
              } catch (_) {}
            }
          }
        }
      } catch (_) {}

      for (final id in identifiers) {
        final paths = [
          'customer_images/$id.jpg',
          'customer_images/$id.png',
          'customer_images/${id}_profile.jpg',
          'customer_images/${id}_profile.png',
          'customer_images/profile_$id.jpg',
          'customer_images/profile_$id.png',
          'profiles/$id.jpg',
          'profiles/$id.png',
          'profile_images/$id.jpg',
          'profile_images/$id.png',
        ];

        for (final path in paths) {
          try {
            final ref = _storage.ref().child(path);
            final url = await ref.getDownloadURL();

            if (mounted) {
              setState(() => _profileImageUrl = url);
              await SecureStorageService.saveProfileImageUrl(url);
            }
            return;
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('Error loading profile image: $e');
    }
  }

  void _processInstallmentData(DocumentSnapshot doc) {
    if (!mounted) return;

    try {
      final data = doc.data() as Map<String, dynamic>;

      bool isCompleted = false;
      if (data.containsKey('status')) {
        final status = data['status'].toString().toLowerCase();
        isCompleted = [
          'completed',
          'paid',
          'closed',
          'finished',
        ].contains(status);
      }

      dynamic balanceAmount;
      for (final field in [
        'balance',
        'currentBalance',
        'outstandingBalance',
        'remainingAmount',
      ]) {
        if (data.containsKey(field)) {
          balanceAmount = data[field];
          break;
        }
      }

      if (_accountNumber.isEmpty && data.containsKey('accountNumber')) {
        _accountNumber = data['accountNumber'].toString();
      }

      dynamic nextDueDate;
      if (data.containsKey('nextDueDate')) {
        nextDueDate = data['nextDueDate'];
      } else if (data.containsKey('nextInstallmentDate')) {
        nextDueDate = data['nextInstallmentDate'];
      }

      dynamic monthlyBillingDate;
      if (data.containsKey('billingDate')) {
        monthlyBillingDate = data['billingDate'];
      } else if (data.containsKey('installmentDate')) {
        monthlyBillingDate = data['installmentDate'];
      } else {
        monthlyBillingDate = nextDueDate;
      }

      double currentMonthPayable = 0.0;
      double nextInstallmentAmount = 0000.0;
      double totalArrearsAmount = 0.0;
      List<Map<String, dynamic>> arrearsList = [];
      String installmentMonth = '';
      String installmentStatus = '';
      bool hasArrears = false;

      _installmentsByMonth.clear();
      String nextInstallmentMonth = '';
      String nextInstallmentStatus = '';

      if (data.containsKey('arrears') && data['arrears'] is List) {
        final arrears = data['arrears'] as List<dynamic>;

        for (var arrear in arrears) {
          if (arrear is Map<dynamic, dynamic> && arrear.containsKey('month')) {
            final monthKey = arrear['month'].toString();
            _installmentsByMonth[monthKey] = Map<String, dynamic>.from(arrear);
          }
        }

        const targetMonth = "2025-08";
        if (_installmentsByMonth.containsKey(targetMonth)) {
          final augustData = _installmentsByMonth[targetMonth]!;
          final status = augustData['status']?.toString().toLowerCase() ?? '';

          if (status == "partial" && augustData.containsKey('amountPayable')) {
            nextInstallmentAmount = _parseAmount(augustData['amountPayable']);
            nextInstallmentMonth = targetMonth;
            nextInstallmentStatus = status;
            debugPrint(
              'Found partial payment for August: $nextInstallmentAmount',
            );
          }
        }

        if (nextInstallmentMonth.isEmpty && nextDueDate != null) {
          DateTime nextDueDateParsed;
          if (nextDueDate is Timestamp) {
            nextDueDateParsed = nextDueDate.toDate();
          } else if (nextDueDate is String) {
            nextDueDateParsed = _parseDate(nextDueDate);
          } else {
            nextDueDateParsed = DateTime.now();
            if (nextDueDateParsed.month == 12) {
              nextDueDateParsed = DateTime(nextDueDateParsed.year + 1, 1, 15);
            } else {
              nextDueDateParsed = DateTime(
                nextDueDateParsed.year,
                nextDueDateParsed.month + 1,
                15,
              );
            }
          }

          nextInstallmentMonth =
              "${nextDueDateParsed.year}-${nextDueDateParsed.month.toString().padLeft(2, '0')}";

          if (_installmentsByMonth.containsKey(nextInstallmentMonth)) {
            final nextMonthData = _installmentsByMonth[nextInstallmentMonth]!;
            nextInstallmentStatus =
                nextMonthData['status']?.toString().toLowerCase() ?? 'due';

            if (nextMonthData.containsKey('amountPayable')) {
              nextInstallmentAmount = _parseAmount(
                nextMonthData['amountPayable'],
              );
              debugPrint(
                'Next installment amount from amountPayable: $nextInstallmentAmount',
              );
            } else if (nextMonthData.containsKey('standardAmount')) {
              nextInstallmentAmount = _parseAmount(
                nextMonthData['standardAmount'],
              );
              debugPrint(
                'Next installment amount from standardAmount: $nextInstallmentAmount',
              );
            }
          }
        }

        final now = DateTime.now();
        final currentMonth = now.month;
        final currentYear = now.year;

        for (var i = 0; i < arrears.length; i++) {
          if (arrears[i] is Map) {
            final arrear = arrears[i] as Map;

            if (arrear.containsKey('month')) {
              installmentMonth = arrear['month'].toString();
              if (installmentMonth.contains(currentMonth.toString()) &&
                  installmentMonth.contains(currentYear.toString())) {
                if (arrear.containsKey('amountPayable')) {
                  currentMonthPayable = _parseAmount(arrear['amountPayable']);
                } else if (arrear.containsKey('standardAmount')) {
                  currentMonthPayable = _parseAmount(arrear['standardAmount']);
                }

                if (arrear.containsKey('status')) {
                  installmentStatus = arrear['status'].toString();
                }

                break;
              }
            } else if (arrear.containsKey('billingDate')) {
              try {
                final billingDate = _parseDate(arrear['billingDate']);
                if (billingDate.month == currentMonth &&
                    billingDate.year == currentYear) {
                  if (arrear.containsKey('month')) {
                    installmentMonth = arrear['month'].toString();
                  } else {
                    installmentMonth = DateFormat(
                      'MMMM yyyy',
                    ).format(billingDate);
                  }

                  if (arrear.containsKey('amountPayable')) {
                    currentMonthPayable = _parseAmount(arrear['amountPayable']);
                  } else if (arrear.containsKey('standardAmount')) {
                    currentMonthPayable = _parseAmount(
                      arrear['standardAmount'],
                    );
                  }

                  if (arrear.containsKey('status')) {
                    installmentStatus = arrear['status'].toString();
                  }

                  break;
                }
              } catch (_) {}
            }
          }
        }

        for (var i = 0; i < arrears.length; i++) {
          if (arrears[i] is Map) {
            final arrear = arrears[i] as Map;

            final status = arrear['status']?.toString().toLowerCase() ?? '';
            if (status == 'paid') continue;

            double amount = 0;
            if (arrear.containsKey('amountPayable')) {
              amount = _parseAmount(arrear['amountPayable']);
            } else if (arrear.containsKey('standardAmount')) {
              amount = _parseAmount(arrear['standardAmount']);
            }

            if (amount <= 0) continue;

            String month = '';
            if (arrear.containsKey('month')) {
              month = arrear['month'].toString();
            }

            DateTime? billingDate;
            if (arrear.containsKey('billingDate')) {
              billingDate = _parseDate(arrear['billingDate']);
            }

            bool isPastDue = false;

            if (month.contains('-')) {
              try {
                final parts = month.split('-');
                if (parts.length >= 2) {
                  final year = int.tryParse(parts[0]);
                  final monthNum = int.tryParse(parts[1]);

                  if (year != null && monthNum != null) {
                    if (year < currentYear ||
                        (year == currentYear && monthNum < currentMonth)) {
                      isPastDue = true;
                    }
                  }
                }
              } catch (_) {}
            }

            if (!isPastDue && billingDate != null) {
              final yesterday = DateTime(now.year, now.month, now.day - 1);
              if (billingDate.isBefore(yesterday)) {
                isPastDue = true;
              }
            }

            if (isPastDue) {
              totalArrearsAmount += amount;

              String formattedMonth = month;
              if (billingDate != null) {
                formattedMonth = DateFormat('MMMM yyyy').format(billingDate);
              }

              arrearsList.add({
                'month': formattedMonth,
                'amount': amount,
                'status': status,
                'date': billingDate,
              });

              hasArrears = true;
            }
          }
        }

        arrearsList.sort((a, b) {
          final dateA = a['date'] as DateTime?;
          final dateB = b['date'] as DateTime?;
          if (dateA == null && dateB == null) return 0;
          if (dateA == null) return 1;
          if (dateB == null) return -1;
          return dateA.compareTo(dateB);
        });
      }

      if (currentMonthPayable == 0.0) {
        if (data.containsKey('installmentAmount')) {
          currentMonthPayable = _parseAmount(data['installmentAmount']);
        } else if (data.containsKey('monthlyPayment')) {
          currentMonthPayable = _parseAmount(data['monthlyPayment']);
        } else if (data.containsKey('emi')) {
          currentMonthPayable = _parseAmount(data['emi']);
        }
      }

      final formattedNextDueDate = _formatNextDueDate(nextDueDate);
      final formattedMonthlyDate = _formatNextDueDate(monthlyBillingDate);
      final formattedLiabilityAmount =
          isCompleted ? 'LKR. 0.00' : _formatCurrency(balanceAmount);

      bool isMonthlyPaid = installmentStatus.toLowerCase() == 'paid';

      bool showMonthlyCard = true;
      if (isMonthlyPaid && !hasArrears) {
        showMonthlyCard = false;
      } else {
        showMonthlyCard = true;
      }

      setState(() {
        _isLoanCompleted = isCompleted;
        _liabilitiesAmount = formattedLiabilityAmount;
        _nextInstallmentDate = formattedNextDueDate;
        _monthlyInstallmentDate = formattedMonthlyDate;
        _isMonthlyInstallmentPaid = isMonthlyPaid;
        _nextInstallmentMonth = nextInstallmentMonth;
        _nextInstallmentStatus = nextInstallmentStatus;

        _amountPayable = currentMonthPayable;
        _nextInstallmentAmount = nextInstallmentAmount;

        _totalArrearsAmount = totalArrearsAmount;
        _hasArrears = hasArrears;

        _showMonthlyInstallment = showMonthlyCard;
      });
    } catch (e) {
      debugPrint('Error processing installment data: $e');
    }
  }

  double _parseAmount(dynamic amount) {
    if (amount is num) {
      return amount.toDouble();
    } else if (amount is String) {
      try {
        String cleanedString = amount.replaceAll(RegExp(r'[^0-9.]'), '');
        return double.parse(cleanedString);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  DateTime _parseDate(dynamic dateValue) {
    if (dateValue is Timestamp) {
      return dateValue.toDate();
    } else if (dateValue is String) {
      try {
        return DateTime.parse(dateValue);
      } catch (_) {
        final formats = [
          'yyyy-MM-dd',
          'dd-MM-yyyy',
          'MM/dd/yyyy',
          'dd/MM/yyyy',
          'yyyy/MM/dd',
        ];

        for (final format in formats) {
          try {
            return DateFormat(format).parse(dateValue);
          } catch (_) {}
        }
        return DateTime.now();
      }
    }
    return DateTime.now();
  }

  String _formatNextDueDate(dynamic dateValue) {
    if (dateValue == null) {
      final now = DateTime.now();
      final nextMonth = now.month < 12 ? now.month + 1 : 1;
      final nextYear = now.month < 12 ? now.year : now.year + 1;
      final nextDate = DateTime(nextYear, nextMonth, 30);
      return DateFormat('dd/MM/yyyy').format(nextDate);
    }

    if (dateValue is Timestamp) {
      final date = dateValue.toDate();
      return DateFormat('dd/MM/yyyy').format(date);
    }

    if (dateValue is String) {
      try {
        final date = _parseDate(dateValue);
        return DateFormat('dd/MM/yyyy').format(date);
      } catch (_) {
        return dateValue;
      }
    }

    return '00/00/0000';
  }

  String _formatCurrency(dynamic amount) {
    double value = 0.0;

    if (amount is num) {
      value = amount.toDouble();
    } else if (amount is String) {
      try {
        value = double.parse(amount);
      } catch (_) {}
    }

    return NumberFormat.currency(
      symbol: 'LKR. ',
      decimalDigits: 2,
    ).format(value);
  }

  String _formatAmount() {
    if (_isLoanCompleted) {
      return AppLocalizations.of(context)!.completed;
    }

    double amount = _amountPayable;
    if (_hasArrears && !_isMonthlyInstallmentPaid) {
      amount += _totalArrearsAmount;
    }
    return _formatCurrency(amount).replaceFirst("LKR. ", "");
  }

  String _formatNextAmount() {
    if (_isLoanCompleted) {
      return AppLocalizations.of(context)!.completed;
    }

    if (_nextInstallmentMonth.isNotEmpty &&
        _installmentsByMonth.containsKey(_nextInstallmentMonth)) {
      final nextMonthData = _installmentsByMonth[_nextInstallmentMonth]!;

      String status =
          nextMonthData['status']?.toString().toLowerCase() ?? 'due';

      if (status == 'partial') {
        if (nextMonthData.containsKey('amountPayable')) {
          final amount = _parseAmount(nextMonthData['amountPayable']);
          return _formatCurrency(amount).replaceFirst("LKR. ", "");
        }
      } else if (status == 'due') {
        if (nextMonthData.containsKey('amountPayable')) {
          final amount = _parseAmount(nextMonthData['amountPayable']);
          return _formatCurrency(amount).replaceFirst("LKR. ", "");
        } else if (nextMonthData.containsKey('standardAmount')) {
          final amount = _parseAmount(nextMonthData['standardAmount']);
          return _formatCurrency(amount).replaceFirst("LKR. ", "");
        }
      } else if (status == 'paid') {
        try {
          final parts = _nextInstallmentMonth.split('-');
          if (parts.length == 2) {
            int year = int.parse(parts[0]);
            int month = int.parse(parts[1]);

            if (month == 12) {
              year++;
              month = 1;
            } else {
              month++;
            }

            final followingMonth = "$year-${month.toString().padLeft(2, '0')}";

            if (_installmentsByMonth.containsKey(followingMonth)) {
              final futureMonthData = _installmentsByMonth[followingMonth]!;

              if (futureMonthData.containsKey('amountPayable')) {
                final amount = _parseAmount(futureMonthData['amountPayable']);
                return _formatCurrency(amount).replaceFirst("LKR. ", "");
              } else if (futureMonthData.containsKey('standardAmount')) {
                final amount = _parseAmount(futureMonthData['standardAmount']);
                return _formatCurrency(amount).replaceFirst("LKR. ", "");
              }
            }
          }
        } catch (e) {
          debugPrint('Error finding month after paid month: $e');
        }
      }
    }

    return _formatCurrency(_nextInstallmentAmount).replaceFirst("LKR. ", "");
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopRow(context),
            const SizedBox(height: 38),
            _buildLiabilitiesBox(context),
            const SizedBox(height: 10),
            _buildInstallmentCards(context),
            const SizedBox(height: 20),
            _buildInfoBox(context),
            const SizedBox(height: 20),
            _buildPaymentsSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Hero(
          tag: 'profile-image',
          child: GestureDetector(
            onTap: () => _navigateToScreen(const ProfileScreen()),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.purpleAccent, width: 3),
              ),
              child: ClipOval(
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child:
                      _profileImageUrl != null
                          ? Image.network(
                            _profileImageUrl!,
                            fit: BoxFit.cover,
                            cacheWidth: 100,
                            errorBuilder:
                                (_, __, ___) =>
                                    Container(color: Colors.grey[300]),
                          )
                          : Container(color: Colors.grey[300]),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppLocalizations.of(context)!.helloUser(_firstName),
                style: const TextStyle(fontSize: 16),
              ),
              Text(
                AppLocalizations.of(context)!.welcomeBack,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Stack(
          children: [
            IconButton(
              icon: const Icon(
                Icons.notifications_active_rounded,
                size: 30,
                color: Color(0xFF2E3A59),
              ),
              onPressed:
                  () => _navigateToScreen(
                    const NotificationScreen(),
                  ).then((_) => _loadUnreadNotificationsCount()),
            ),
            if (_unreadNotificationsCount > 0)
              Positioned(
                top: 5,
                right: 5,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    _unreadNotificationsCount > 9
                        ? '9+'
                        : _unreadNotificationsCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLiabilitiesBox(BuildContext context) {
    return GestureDetector(
      onTap: () => _navigateToScreen(const LiabilityScreen()),
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 150,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFF2E3A59),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.myLiabilities,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  _liabilitiesAmount,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  AppLocalizations.of(context)!.seeDetails,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Image.asset(
                "assets/images/dashboard/liabilities.png",
                height: 68,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstallmentCards(BuildContext context) {
    bool canToggle = _isMonthlyInstallmentPaid && !_hasArrears;

    return GestureDetector(
      onTap: () {
        if (canToggle) {
          setState(() {
            _showMonthlyInstallment = !_showMonthlyInstallment;
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF92BBD9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            _showMonthlyInstallment
                ? _buildMonthlyInstallmentContent(context)
                : _buildNextInstallmentContent(context),
            const SizedBox(height: 15),
            if (canToggle)
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color:
                          _showMonthlyInstallment
                              ? Colors.white
                              : Colors.white.withValues(
                                red: 255,
                                green: 255,
                                blue: 255,
                                alpha: 127,
                              ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color:
                          !_showMonthlyInstallment
                              ? Colors.white
                              : Colors.white.withValues(
                                red: 255,
                                green: 255,
                                blue: 255,
                                alpha: 127,
                              ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              ),
            if (!canToggle) const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyInstallmentContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppLocalizations.of(context)!.monthlyInstallment,
              style: const TextStyle(color: Colors.white),
            ),
            if (_hasArrears &&
                !_isLoanCompleted &&
                !_isMonthlyInstallmentPaid) ...[
              const SizedBox(width: 18),
              Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white,
                    size: 10,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context)!.includesArrearsInstallments,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isMonthlyInstallmentPaid && _lastPaymentDate.isNotEmpty
                  ? _lastPaymentDate
                  : _monthlyInstallmentDate,
              style: const TextStyle(color: Colors.white70),
            ),

            _isMonthlyInstallmentPaid
                ? Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      AppLocalizations.of(context)!.paid,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
                : Text(
                  _isLoanCompleted
                      ? AppLocalizations.of(context)!.completed
                      : "LKR. ${_formatAmount()}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
          ],
        ),
      ],
    );
  }

  Widget _buildNextInstallmentContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _isLoanCompleted
                  ? AppLocalizations.of(context)!.myFinanceWere
                  : AppLocalizations.of(context)!.nextInstallment,
              style: const TextStyle(color: Colors.white),
            ),
            if (_nextInstallmentStatus.toLowerCase() == 'partial') ...[
              const SizedBox(width: 24),
              Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white, size: 10),
                  const SizedBox(width: 2),
                  Text(
                    AppLocalizations.of(context)!.remainingBalanceDue,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ],
              ),
            ],
          ],
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _isLoanCompleted && _lastPaymentDate.isNotEmpty
                  ? "${AppLocalizations.of(context)!.on} $_lastPaymentDate"
                  : _nextInstallmentDate,
              style: const TextStyle(color: Colors.white70),
            ),

            Text(
              _isLoanCompleted
                  ? AppLocalizations.of(context)!.completed
                  : "LKR. ${_formatNextAmount()}",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoBox(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.supportMessage,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocalizations.of(context)!.supportDescription,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.only(left: 24, top: 12),
            child: SizedBox(
              width: 50,
              height: 50,
              child: Image.asset(
                "assets/images/dashboard/help.png",
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context)!.payments,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Color(0xFF2E3A59),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildModernCard(
                context,
                bgColor: const Color.fromARGB(255, 217, 242, 251),
                imagePath: 'assets/images/dashboard/pay.png',
                label: AppLocalizations.of(context)!.pay,
                page: const PaymentScreen(),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildModernCard(
                context,
                bgColor: const Color(0xFFFFE2EA),
                imagePath: 'assets/images/dashboard/bill.png',
                label: AppLocalizations.of(context)!.bill,
                page: const BillScreen(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModernCard(
    BuildContext context, {
    required Color bgColor,
    required String imagePath,
    required String label,
    required Widget page,
  }) {
    return GestureDetector(
      onTap: () => _navigateToScreen(page),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color.fromARGB(0, 255, 255, 255),
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: Image.asset(imagePath, height: 40)),
            ),
            const SizedBox(width: 18),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Future<T?> _navigateToScreen<T extends Object?>(Widget screen) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}
