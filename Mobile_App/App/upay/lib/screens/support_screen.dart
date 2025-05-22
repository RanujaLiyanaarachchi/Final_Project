import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:upay/l10n/app_localizations.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String? copiedKey;

  Map<String, dynamic> _contactData = {};

  final Map<String, dynamic> _defaultContactData = {
    'phone': '0252236432',
    'whatsapp': '0714193207',
    'web': 'https://rainbowpages.lk/other/unclassified/unicon-finance-pvt-ltd/',
    'fax': '0252236432',
    'email': 'uniconfinance@gmail.com',
    'address': '3D 1st Flor, Maithreepala Senanayake Mawatha, Anuradhapura.',
    'location': 'https://g.co/kgs/DsEGQxv',
    'message': 'You can message us anytime',
  };

  late Stream<DocumentSnapshot> _contactStream;

  @override
  void initState() {
    super.initState();
    _setupContactStream();
  }

  void _setupContactStream() {
    _contactStream =
        FirebaseFirestore.instance
            .collection('support')
            .doc('contact')
            .snapshots();

    _loadContactData();
  }

  Future<void> _loadContactData() async {
    try {
      final DocumentSnapshot contactDoc = await FirebaseFirestore.instance
          .collection('support')
          .doc('contact')
          .get(const GetOptions(source: Source.serverAndCache));

      if (contactDoc.exists && mounted) {
        final data = contactDoc.data() as Map<String, dynamic>;
        setState(() {
          _contactData = data;
        });
      }
    } catch (e) {
      debugPrint('Error loading contact data: $e');
    }
  }

  String _cleanValue(dynamic value) {
    if (value == null) return '';

    String strValue = value.toString();
    if (strValue.startsWith('"') && strValue.endsWith('"')) {
      strValue = strValue.substring(1, strValue.length - 1);
    }

    return strValue;
  }

  String _formatPhoneNumber(String phone) {
    phone = _cleanValue(phone).replaceAll(RegExp(r'\s+'), '');

    if (phone.length > 6) {
      return "${phone.substring(0, 3)} ${phone.substring(3, 6)} ${phone.substring(6)}";
    } else if (phone.length > 3) {
      return "${phone.substring(0, 3)} ${phone.substring(3)}";
    }

    return phone;
  }

  String _formatMessageWithPhone(String message) {
    if (RegExp(r'^\d+$').hasMatch(message.replaceAll(RegExp(r'\s+'), ''))) {
      return _formatPhoneNumber(message);
    }
    return message;
  }

  String _formatWhatsAppNumber(String phone) {
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');

    if (cleanPhone.startsWith('94')) {
      return cleanPhone;
    }

    if (cleanPhone.startsWith('0')) {
      return '94${cleanPhone.substring(1)}';
    }

    return '94$cleanPhone';
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showSnackBar('Cannot launch: $url');
      }
    } catch (e) {
      _showSnackBar('Cannot launch: $url');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _copyToClipboard(String text, String key) {
    Clipboard.setData(ClipboardData(text: text));

    setState(() {
      copiedKey = key;
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && copiedKey == key) {
        setState(() {
          copiedKey = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _contactStream,
        builder: (context, snapshot) {
          Map<String, dynamic> contactData = {..._defaultContactData};

          if (snapshot.hasData &&
              snapshot.data != null &&
              snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            contactData.addAll(data);
          } else if (_contactData.isNotEmpty) {
            contactData.addAll(_contactData);
          }

          final String phone = _formatPhoneNumber(
            _cleanValue(contactData['phone']),
          );
          final String whatsapp = _formatPhoneNumber(
            _cleanValue(contactData['whatsapp']),
          );
          final String website = _cleanValue(contactData['web']);
          final String fax = _formatPhoneNumber(
            _cleanValue(contactData['fax']),
          );
          final String email = _cleanValue(contactData['email']);
          final String address = _cleanValue(contactData['address']);
          final String location = _cleanValue(contactData['location']);
          final String messageText = _formatMessageWithPhone(
            _cleanValue(contactData['message']),
          );

          final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
          final cleanWhatsapp = _formatWhatsAppNumber(whatsapp);
          final cleanFax = fax.replaceAll(RegExp(r'\s+'), '');

          final List<Map<String, dynamic>> supportItems = [
            {
              'icon': Icons.call,
              'color': Colors.green,
              'title': t.call,
              'subtitle': phone,
              'action': () => _launchUrl('tel:$cleanPhone'),
              'key': 'call',
            },
            {
              'icon': Icons.message_outlined,
              'color': Colors.teal,
              'title': t.whatsapp,
              'subtitle': whatsapp,
              'action': () => _launchUrl('https://wa.me/$cleanWhatsapp'),
              'key': 'whatsapp',
            },
            {
              'icon': Icons.language,
              'color': Colors.blue,
              'title': t.website,
              'subtitle': 'Unicon Finance (Pvt) Ltd',
              'action': () => _launchUrl(website),
              'key': 'website',
            },
            {
              'icon': Icons.print,
              'color': Colors.purple,
              'title': t.fax,
              'subtitle': fax,
              'action': () => _launchUrl('tel:$cleanFax'),
              'key': 'fax',
            },
            {
              'icon': Icons.email_outlined,
              'color': Colors.orange,
              'title': t.mail,
              'subtitle': email,
              'action': () => _launchUrl('mailto:$email'),
              'key': 'mail',
            },
            {
              'icon': Icons.message_outlined,
              'color': Colors.deepPurple,
              'title': t.message,
              'subtitle': messageText,
              'action': () => _launchUrl('sms:$cleanPhone'),
              'key': 'sms',
            },
            {
              'icon': Icons.location_on_outlined,
              'color': Colors.redAccent,
              'title': t.address,
              'subtitle': address,
              'action': () => _copyToClipboard(address, 'address'),
              'key': 'address',
            },
            {
              'icon': Icons.map_outlined,
              'color': Colors.lightBlue,
              'title': t.location,
              'subtitle': t.tapToViewOnMap,
              'action': () => _launchUrl(location),
              'key': 'location',
            },
          ];

          return Column(
            children: [
              const SizedBox(height: 80),
              Text(
                t.support,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 60),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(255, 239, 246, 255),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Image.asset(
                            'assets/images/support/support.png',
                            width: 40,
                            height: 40,
                            cacheWidth: 80,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.uniconFinance,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  t.anuradhapura,
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Divider(thickness: 1),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  physics: const ClampingScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(25, 0, 25, 20),
                  itemCount: supportItems.length,
                  addRepaintBoundaries: true,
                  itemBuilder: (context, index) {
                    final item = supportItems[index];
                    final itemKey = item['key'];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: item['action'],
                        child: Stack(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color.fromARGB(
                                    255,
                                    173,
                                    169,
                                    228,
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: item['color'].withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    item['icon'],
                                    color: item['color'],
                                  ),
                                ),
                                title: Text(
                                  item['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(item['subtitle']),
                              ),
                            ),
                            if (copiedKey == itemKey)
                              Positioned(
                                top: 6,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purpleAccent.withAlpha(51),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    t.copied,
                                    style: const TextStyle(
                                      color: Colors.purpleAccent,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
