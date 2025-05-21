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

class _SupportScreenState extends State<SupportScreen> with AutomaticKeepAliveClientMixin {
  // Enable AutomaticKeepAliveClientMixin to prevent rebuilding when navigating
  @override
  bool get wantKeepAlive => true;

  // Track which item was copied to clipboard for UI feedback
  String? copiedKey;
  
  // Store contact data from Firestore
  Map<String, dynamic> _contactData = {};
  
  // Default contact values to use while loading or if Firestore fails
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

  // Stream subscription for real-time updates
  late Stream<DocumentSnapshot> _contactStream;

  @override
  void initState() {
    super.initState();
    // Set up real-time data stream from Firestore
    _setupContactStream();
  }

  // Set up a stream for real-time contact data updates
  void _setupContactStream() {
    // Create a stream that listens to changes in the contact document
    _contactStream = FirebaseFirestore.instance
        .collection('support')
        .doc('contact')
        .snapshots();

    // Initial load of contact data (non-blocking)
    _loadContactData();
  }

  // Load contact information from Firestore (once, at startup)
  Future<void> _loadContactData() async {
    try {
      // Get contact data from Firestore
      final DocumentSnapshot contactDoc = await FirebaseFirestore.instance
          .collection('support')
          .doc('contact')
          .get(const GetOptions(source: Source.serverAndCache)); // Try cache first for faster loading

      if (contactDoc.exists && mounted) {
        final data = contactDoc.data() as Map<String, dynamic>;
        setState(() {
          _contactData = data;
        });
      }
    } catch (e) {
      // Log error but continue with default data
      debugPrint('Error loading contact data: $e');
    }
  }

  // Helper function to clean up string values from Firebase
  String _cleanValue(dynamic value) {
    if (value == null) return '';

    String strValue = value.toString();
    // Remove surrounding quotes if present
    if (strValue.startsWith('"') && strValue.endsWith('"')) {
      strValue = strValue.substring(1, strValue.length - 1);
    }

    return strValue;
  }

  // Format phone numbers with spaces after 3 and 6 digits for readability
  String _formatPhoneNumber(String phone) {
    // First clean the phone number by removing spaces
    phone = _cleanValue(phone).replaceAll(RegExp(r'\s+'), '');

    // Check if we have enough digits to format
    if (phone.length > 6) {
      return "${phone.substring(0, 3)} ${phone.substring(3, 6)} ${phone.substring(6)}";
    } else if (phone.length > 3) {
      return "${phone.substring(0, 3)} ${phone.substring(3)}";
    }

    return phone;
  }

  // Format message text that contains a phone number
  String _formatMessageWithPhone(String message) {
    // Check if message is just a phone number (only digits)
    if (RegExp(r'^\d+$').hasMatch(message.replaceAll(RegExp(r'\s+'), ''))) {
      return _formatPhoneNumber(message);
    }
    return message;
  }

  // Format WhatsApp number with country code for Sri Lanka (+94)
  String _formatWhatsAppNumber(String phone) {
    // Clean the number first (remove spaces, + symbols)
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // If it already has the country code, use it as is
    if (cleanPhone.startsWith('94')) {
      return cleanPhone;
    }
    
    // If it starts with 0, remove the 0 and add 94
    if (cleanPhone.startsWith('0')) {
      return '94${cleanPhone.substring(1)}';
    }
    
    // Otherwise just add 94 prefix
    return '94$cleanPhone';
  }

  // Launch a URL (web, phone, email, etc)
  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      // Use external application mode for better performance
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        _showSnackBar('Cannot launch: $url');
      }
    } catch (e) {
      _showSnackBar('Cannot launch: $url');
    }
  }

  // Show a message to the user
  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  // Copy text to clipboard and show visual feedback
  void _copyToClipboard(String text, String key) {
    // Copy text to clipboard
    Clipboard.setData(ClipboardData(text: text));
    
    // Update UI to show "Copied" indicator
    setState(() {
      copiedKey = key;
    });
    
    // Remove the indicator after 2 seconds
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
    // Call super for AutomaticKeepAliveClientMixin
    super.build(context);
    
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: const Color(0xFFFEF7FF),
      // Use StreamBuilder for real-time updates
      body: StreamBuilder<DocumentSnapshot>(
        stream: _contactStream,
        builder: (context, snapshot) {
          // Merge default data with loaded data
          Map<String, dynamic> contactData = {..._defaultContactData};
          
          // If we have data from the stream, update with it
          if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
            final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
            contactData.addAll(data);
          } else if (_contactData.isNotEmpty) {
            // Use previously loaded data if stream hasn't delivered yet
            contactData.addAll(_contactData);
          }
          
          // Clean and format the contact information
          final String phone = _formatPhoneNumber(_cleanValue(contactData['phone']));
          final String whatsapp = _formatPhoneNumber(_cleanValue(contactData['whatsapp']));
          final String website = _cleanValue(contactData['web']);
          final String fax = _formatPhoneNumber(_cleanValue(contactData['fax']));
          final String email = _cleanValue(contactData['email']);
          final String address = _cleanValue(contactData['address']);
          final String location = _cleanValue(contactData['location']);
          final String messageText = _formatMessageWithPhone(_cleanValue(contactData['message']));

          // Clean up phone numbers for dialing (remove spaces)
          final cleanPhone = phone.replaceAll(RegExp(r'\s+'), '');
          final cleanWhatsapp = _formatWhatsAppNumber(whatsapp); // Use our new method with country code
          final cleanFax = fax.replaceAll(RegExp(r'\s+'), '');

          // Create the list of support items
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

          // Always show content immediately without loading indicator
          return Column(
            children: [
              const SizedBox(height: 80),
              // Title
              Text(
                t.support,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 60),
              // Header Card
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
                          // Company logo - use fixed dimensions to avoid layout shifts
                          Image.asset(
                            'assets/images/support/support.png',
                            width: 40,
                            height: 40,
                            // Use memory efficient loading
                            cacheWidth: 80, // 2x for high-res displays
                          ),
                          const SizedBox(width: 12),
                          // Company details
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
                                  style: const TextStyle(
                                    color: Colors.grey,
                                  ),
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
              // Support Items List - use optimized ListView
              Expanded(
                child: ListView.builder(
                  // Use physics that works better on low-end devices
                  physics: const ClampingScrollPhysics(),
                  // Use keyCache to prevent unnecessary rebuilds
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(25, 0, 25, 20),
                  itemCount: supportItems.length,
                  // Use addRepaintBoundaries for better performance
                  addRepaintBoundaries: true,
                  itemBuilder: (context, index) {
                    final item = supportItems[index];
                    final itemKey = item['key'];
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: GestureDetector(
                        // Optimize touch response
                        behavior: HitTestBehavior.opaque,
                        onTap: item['action'],
                        child: Stack(
                          children: [
                            // Support item card
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color.fromARGB(255, 173, 169, 228),
                                  width: 1,
                                ),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                // Icon container
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
                                // Support item title
                                title: Text(
                                  item['title'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                // Support item details
                                subtitle: Text(item['subtitle']),
                              ),
                            ),
                            // "Copied" indicator that appears when text is copied
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