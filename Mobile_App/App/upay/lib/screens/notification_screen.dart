import 'package:flutter/material.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:upay/services/secure_storage_service.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:async';
import 'package:upay/screens/message_view_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_storage/firebase_storage.dart';

final FlutterLocalNotificationsPlugin globalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
String? globalCustomerId;
String? lastMessageId;
bool isListeningToMessages = false;
StreamSubscription<QuerySnapshot>? globalMessageSubscription;

Future<void> initializeGlobalNotifications() async {
  if (isListeningToMessages) return;

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );

  await globalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {},
  );

  globalCustomerId = await SecureStorageService.getUserCustomerId();

  await loadLastMessageId();

  if (globalCustomerId != null) {
    startGlobalMessageListener();
  }
}

Future<void> loadLastMessageId() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    lastMessageId = prefs.getString('last_message_id');
    debugPrint('Globally loaded last message ID: $lastMessageId');
  } catch (e) {
    debugPrint('Error loading last message ID: $e');
  }
}

Future<void> saveLastMessageId(String messageId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_message_id', messageId);
    lastMessageId = messageId;
  } catch (e) {
    debugPrint('Error saving last message ID: $e');
  }
}

void startGlobalMessageListener() {
  if (globalCustomerId == null || isListeningToMessages) return;

  isListeningToMessages = true;

  globalMessageSubscription = FirebaseFirestore.instance
      .collection('messages')
      .where('customerId', isEqualTo: globalCustomerId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .listen(
        (snapshot) {
          final docs = snapshot.docs;

          processNewMessages(docs);
        },
        onError: (error) {
          debugPrint('Error in global message listener: $error');
          isListeningToMessages = false;
        },
      );
}

void processNewMessages(List<DocumentSnapshot> docs) {
  if (docs.isEmpty) return;

  final latestMessageId = docs.first.id;

  if (lastMessageId == null) {
    saveLastMessageId(latestMessageId);
    return;
  }

  if (latestMessageId != lastMessageId) {
    for (final doc in docs) {
      if (doc.id == lastMessageId) {
        break;
      }

      final message = doc.data() as Map<String, dynamic>;
      final bool isRead = message['isRead'] == true;

      if (!isRead) {
        showGlobalNotification(
          message['heading'] ?? 'New Message',
          message['message'] ?? 'You have received a new notification',
          doc.id,
        );
      }
    }

    saveLastMessageId(latestMessageId);
  }
}

Future<void> showGlobalNotification(
  String title,
  String body,
  String messageId,
) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
        'upay_messages',
        'UPay Messages',
        channelDescription: 'Notifications for UPay messages',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        largeIcon: DrawableResourceAndroidBitmap('@drawable/ic_launcher'),
      );

  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    ),
  );

  final int notificationId = messageId.hashCode;

  await globalNotificationsPlugin.show(
    notificationId,
    title,
    body,
    platformChannelSpecifics,
    payload: messageId,
  );
}

void cancelGlobalMessageSubscription() {
  globalMessageSubscription?.cancel();
  isListeningToMessages = false;
}

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with TickerProviderStateMixin {
  String? customerId;
  String? userNic;
  List<DocumentSnapshot> messages = [];
  bool isLoading = true;
  bool isClearing = false;
  StreamSubscription<QuerySnapshot>? _subscription;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      globalNotificationsPlugin;

  final List<String> _messagesToRemove = [];

  final Map<String, AnimationController> _animationControllers = {};

  @override
  void initState() {
    super.initState();
    initializeGlobalNotifications();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      customerId = await SecureStorageService.getUserCustomerId();
      userNic = await SecureStorageService.getUserNic();

      if (customerId == null || userNic == null) {
        setState(() {
          isLoading = false;
        });
        return;
      }

      globalCustomerId = customerId;

      _subscribeToMessages();
    } catch (e) {
      debugPrint('Error loading user data: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  void _subscribeToMessages() {
    if (customerId == null) return;

    _subscription = FirebaseFirestore.instance
        .collection('messages')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            final docs = snapshot.docs;

            for (final doc in docs) {
              if (!_animationControllers.containsKey(doc.id)) {
                _animationControllers[doc.id] = AnimationController(
                  vsync: this,
                  duration: const Duration(milliseconds: 300),
                );
              }
            }

            setState(() {
              messages = docs;
              isLoading = false;
            });
          },
          onError: (error) {
            debugPrint('Error subscribing to messages: $error');
            setState(() {
              isLoading = false;
            });
          },
        );
  }

  @override
  void dispose() {
    _subscription?.cancel();

    for (final controller in _animationControllers.values) {
      controller.dispose();
    }
    _animationControllers.clear();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 50),
            Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)?.notifications ??
                      'Notifications',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.all(10.0),
                        child: Icon(
                          Icons.arrow_back_ios_rounded,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                if (messages.isNotEmpty && !isLoading)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _confirmClearAllMessages,
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 150),
                          scale: isClearing ? 0.95 : 1.0,
                          child: const Padding(
                            padding: EdgeInsets.all(10.0),
                            child: Icon(
                              Icons.delete_sweep_outlined,
                              color: Color.fromARGB(255, 12, 24, 92),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 50),

            Expanded(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (messages.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index].data() as Map<String, dynamic>;
        final messageId = messages[index].id;

        if (_messagesToRemove.contains(messageId)) {
          return const SizedBox.shrink();
        }

        return _buildMessageItem(message, messageId, index);
      },
    );
  }

  Widget _buildMessageItem(
    Map<String, dynamic> message,
    String messageId,
    int index,
  ) {
    final hasAttachments =
        message['attachments'] != null &&
        (message['attachments'] as List).isNotEmpty;

    final bool isRead = message['isRead'] == true;

    String timeAgo = '';
    if (message['createdAt'] != null) {
      try {
        final timestamp = message['createdAt'] as Timestamp;
        final dateTime = timestamp.toDate();
        timeAgo = timeago
            .format(dateTime, locale: 'en_short')
            .replaceAll('~', '');
      } catch (e) {
        timeAgo = '';
      }
    }

    IconData icon;
    Color iconColor;
    Color iconBgColor;
    String title = message['heading'] ?? 'Message';
    String lowerTitle = title.toLowerCase();

    if (lowerTitle.contains('cash deposit')) {
      icon = Icons.payments;
      iconColor = Colors.green.shade700;
      iconBgColor = Colors.green.shade100;
    } else if (lowerTitle.contains('monthly installment')) {
      icon = Icons.calendar_month;
      iconColor = Colors.indigo;
      iconBgColor = Colors.indigo.shade100;
    } else if (lowerTitle.contains('arrears notice')) {
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.red;
      iconBgColor = Colors.red.shade100;
    } else if (lowerTitle.contains('pay your monthly due')) {
      icon = Icons.receipt_long;
      iconColor = Colors.blue;
      iconBgColor = Colors.blue.shade100;
    } else if (lowerTitle.contains('finance fully settled')) {
      icon = Icons.check_circle;
      iconColor = Colors.orange;
      iconBgColor = Colors.orange.shade50;
    } else if (lowerTitle.contains('alert') ||
        lowerTitle.contains('important')) {
      icon = Icons.warning_amber_rounded;
      iconColor = Colors.red;
      iconBgColor = Colors.red.shade100;
    } else if (lowerTitle.contains('monthly payment') ||
        lowerTitle.contains('card')) {
      icon = Icons.credit_card;
      iconColor = Colors.blue;
      iconBgColor = Colors.blue.shade100;
    } else if (lowerTitle.contains('bill') || lowerTitle.contains('invoice')) {
      icon = Icons.receipt_long;
      iconColor = Colors.orange;
      iconBgColor = Colors.orange.shade100;
    } else if (lowerTitle.contains('offer') ||
        lowerTitle.contains('discount')) {
      icon = Icons.local_offer;
      iconColor = Colors.purple;
      iconBgColor = Colors.purple.shade100;
    } else if (lowerTitle.contains('arrears') ||
        lowerTitle.contains('location')) {
      icon = Icons.warning_rounded;
      iconColor = Colors.green;
      iconBgColor = Colors.green.shade100;
    } else if (lowerTitle.contains('pay')) {
      icon = Icons.payment;
      iconColor = Colors.green.shade700;
      iconBgColor = Colors.green.shade100;
    } else if (lowerTitle.contains('installment')) {
      icon = Icons.calendar_month;
      iconColor = Colors.indigo;
      iconBgColor = Colors.indigo.shade100;
    } else {
      icon = Icons.mail;
      iconColor = Colors.blue;
      iconBgColor = Colors.blue.shade100;
    }

    String displayTitle =
        title.length > 22 ? '${title.substring(0, 20)}...' : title;

    final animController =
        _animationControllers[messageId] ??
        (_animationControllers[messageId] = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 300),
        ));

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-1.5, 0),
      ).animate(
        CurvedAnimation(parent: animController, curve: Curves.easeOutCubic),
      ),
      child: Dismissible(
        key: Key(messageId),
        direction: DismissDirection.horizontal,
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.red),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: Colors.red.shade100,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete_outline, color: Colors.red),
        ),
        confirmDismiss: (direction) async {
          return await _confirmDeleteMessage();
        },
        onDismissed: (direction) {
          _deleteMessageWithAnimation(messageId, message);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: GestureDetector(
            onTap: () => _showMessageDetails(message, messageId),
            child: Stack(
              children: [
                Container(
                  height: 96,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color:
                          isRead ? Colors.grey.shade200 : Colors.grey.shade300,
                      width: isRead ? 0.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            isRead
                                ? Colors.black.withAlpha(10)
                                : Colors.black.withAlpha(20),
                        blurRadius: isRead ? 5 : 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 96,
                            color: iconBgColor,
                            alignment: Alignment.center,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(icon, color: iconColor, size: 36),

                                if (!isRead)
                                  Positioned(
                                    top: 12,
                                    right: 12,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              decoration: BoxDecoration(
                                color:
                                    isRead
                                        ? Colors.white
                                        : const Color(0xFFF8FBFF),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    displayTitle,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight:
                                          isRead
                                              ? FontWeight.w600
                                              : FontWeight.bold,
                                      color: Colors.black,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),

                                  Text(
                                    _getMessagePreview(message['message']),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color:
                                          isRead
                                              ? Colors.grey.shade700
                                              : Colors.grey.shade800,
                                      fontWeight:
                                          isRead
                                              ? FontWeight.normal
                                              : FontWeight.w500,
                                    ),
                                  ),

                                  Align(
                                    alignment: Alignment.bottomRight,
                                    child: Text(
                                      timeAgo.isEmpty ? '' : '$timeAgo ago',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (hasAttachments)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: 0,
                        child: Icon(
                          Icons.attach_file,
                          color: Colors.grey.shade600,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getMessagePreview(dynamic messageBody) {
    final message = messageBody?.toString() ?? 'Part of the message body.....';
    if (message.length <= 30) {
      return message;
    }
    return '${message.substring(0, 28)}...';
  }

  Future<void> _showMessageDetails(
    Map<String, dynamic> message,
    String messageId,
  ) async {
    if (message['isRead'] != true) {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .update({'isRead': true});
    }

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => MessageViewScreen(
              message: message,
              messageId: messageId,
              onDelete: () => _confirmAndDeleteMessage(messageId, message),
            ),
      ),
    );
  }

  Future<bool> _confirmDeleteMessage() async {
    return await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Delete Message'),
              content: const Text(
                'Are you sure you want to delete this message?',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Delete',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  Future<void> _confirmAndDeleteMessage(
    String messageId,
    Map<String, dynamic> message,
  ) async {
    if (await _confirmDeleteMessage()) {
      _deleteMessageWithAnimation(messageId, message);
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _deleteAttachments(Map<String, dynamic> message) async {
    try {
      if (message['attachments'] != null && message['attachments'] is List) {
        List<dynamic> attachments = message['attachments'];

        for (var attachment in attachments) {
          if (attachment is Map && attachment.containsKey('storagePath')) {
            String storagePath = attachment['storagePath'];
            await _deleteAttachmentByPath(storagePath);
          } else if (attachment is Map && attachment.containsKey('path')) {
            String path = attachment['path'];
            await _deleteAttachmentByPath(path);
          }
        }
      }
    } catch (e) {
      debugPrint('Error deleting attachments: $e');
    }
  }

  Future<void> _deleteAttachmentByPath(String path) async {
    try {
      await _storage.ref(path).delete();
      debugPrint('Successfully deleted attachment at path: $path');
    } catch (e) {
      debugPrint('Error deleting attachment: $e');

      try {
        String cleanPath = path.startsWith('/') ? path.substring(1) : path;
        await _storage.ref(cleanPath).delete();
        debugPrint(
          'Successfully deleted attachment at cleaned path: $cleanPath',
        );
      } catch (e2) {
        debugPrint('Failed to delete attachment with clean path: $e2');

        try {
          await _storage.refFromURL(path).delete();
          debugPrint('Successfully deleted attachment using full URL approach');
        } catch (e3) {
          debugPrint('Failed to delete attachment with URL approach: $e3');
        }
      }
    }
  }

  Future<void> _deleteMessageWithAnimation(
    String messageId,
    Map<String, dynamic> message,
  ) async {
    try {
      final controller = _animationControllers[messageId];
      if (controller != null) {
        await controller.forward();
      }

      setState(() {
        _messagesToRemove.add(messageId);
      });

      await _deleteAttachments(message);

      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();
    } catch (e) {
      debugPrint('Error deleting message: $e');
    }
  }

  Future<void> _confirmClearAllMessages() async {
    if (customerId == null || messages.isEmpty) return;

    bool confirm =
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Clear All Messages'),
              content: const Text(
                'Are you sure you want to delete all messages? This action cannot be undone.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Delete All',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (confirm) {
      _clearAllMessages();
    }
  }

  Future<void> _clearAllMessages() async {
    setState(() => isClearing = true);

    try {
      final messagesToDelete = List<DocumentSnapshot>.from(messages);
      final int totalMessages = messagesToDelete.length;

      const baseDelay = Duration(milliseconds: 50);
      const completeDelay = Duration(milliseconds: 20);

      for (int i = totalMessages - 1; i >= 0; i--) {
        final messageId = messagesToDelete[i].id;
        final message = messagesToDelete[i].data() as Map<String, dynamic>;
        final controller = _animationControllers[messageId];

        await Future.delayed(baseDelay);

        if (!mounted) break;

        if (controller != null) {
          controller.forward();

          await Future.delayed(completeDelay);

          if (!mounted) break;

          setState(() {
            _messagesToRemove.add(messageId);
          });

          await _deleteAttachments(message);

          FirebaseFirestore.instance
              .collection('messages')
              .doc(messageId)
              .delete()
              .catchError((e) => debugPrint('Error deleting message: $e'));
        }
      }

      await Future.delayed(const Duration(milliseconds: 300));
    } catch (e) {
      debugPrint('Error clearing messages: $e');
    } finally {
      if (mounted) {
        setState(() => isClearing = false);
      }
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 25),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: Icon(
                  Icons.notifications_off_rounded,
                  size: 70,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                AppLocalizations.of(context)?.no_new_notifications ??
                    'No New Notifications',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                AppLocalizations.of(context)?.no_new_notifications_message ??
                    'You don\'t have any notifications at the moment. We\'ll notify you when something new arrives.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}
