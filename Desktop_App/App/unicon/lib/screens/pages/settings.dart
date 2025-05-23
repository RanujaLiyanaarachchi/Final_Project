import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../signin.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String userEmail = '';
  String lastLoginDate = '';
  String lastLoginTime = '';
  String accountCreated = '';
  bool isLoading = true;
  bool isSigningOut = false;
  bool isSavingSupport = false;
  bool _showSupportSection = false;

  // Customer support details
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whatsappController = TextEditingController();
  final TextEditingController _webController = TextEditingController();
  final TextEditingController _faxController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();

  // Keys for form validation
  final _supportFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadSupportData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _whatsappController.dispose();
    _webController.dispose();
    _faxController.dispose();
    _emailController.dispose();
    _messageController.dispose();
    _addressController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    setState(() => isLoading = true);

    try {
      // Get current user
      final User? currentUser = _auth.currentUser;

      if (currentUser != null) {
        // Get user email
        userEmail = currentUser.email ?? 'No email available';

        // Set current time as login time
        final now = DateTime.now();
        lastLoginDate = DateFormat('yyyy-MM-dd').format(now);
        lastLoginTime = DateFormat('h:mm a').format(now);

        // Set default account created value
        accountCreated = 'Unicon Finance pvt (Ltd)';

        // Don't let Firestore errors block the UI
        _tryLoadFirestoreData(currentUser.uid).catchError((e) {
          debugPrint('Firestore access error (handled): $e');
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
      // Set default values on error
      userEmail = _auth.currentUser?.email ?? 'No email available';
      final now = DateTime.now();
      lastLoginDate = DateFormat('yyyy-MM-dd').format(now);
      lastLoginTime = DateFormat('h:mm a').format(now);
      accountCreated = 'Unicon Finance pvt (Ltd)';
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // Load customer support data from Firestore
  Future<void> _loadSupportData() async {
    try {
      final supportDoc =
          await _firestore.collection('support').doc('contact').get();

      if (supportDoc.exists) {
        final data = supportDoc.data()!;

        setState(() {
          _phoneController.text = data['phone'] ?? '';
          _whatsappController.text = data['whatsapp'] ?? '';
          _webController.text = data['web'] ?? '';
          _faxController.text = data['fax'] ?? '';
          _emailController.text = data['email'] ?? '';
          _messageController.text = data['message'] ?? '';
          _addressController.text = data['address'] ?? '';
          _locationController.text = data['location'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Error loading support data: $e');
    }
  }

  // Save customer support data
  Future<void> _saveSupportData() async {
    if (!_supportFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isSavingSupport = true;
    });

    try {
      await _firestore.collection('support').doc('contact').set({
        'phone': _phoneController.text.trim(),
        'whatsapp': _whatsappController.text.trim(),
        'web': _webController.text.trim(),
        'fax': _faxController.text.trim(),
        'email': _emailController.text.trim(),
        'message': _messageController.text.trim(),
        'address': _addressController.text.trim(),
        'location': _locationController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Customer support details updated successfully'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );

      setState(() {
        _showSupportSection = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating customer support details: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isSavingSupport = false;
        });
      }
    }
  }

  // Separate method to isolate Firestore operations
  Future<void> _tryLoadFirestoreData(String uid) async {
    try {
      // First attempt to check if collection and document exist
      final docExists = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .then((doc) => doc.exists)
          .catchError((_) => false);

      if (docExists) {
        final userData = await _firestore.collection('users').doc(uid).get();

        if (userData.exists && userData.data() != null) {
          final data = userData.data()!;
          if (data.containsKey('accountCreated')) {
            setState(() {
              accountCreated =
                  data['accountCreated'] ?? 'Unicon Finance pvt (Ltd)';
            });
          }
        }
      }
    } catch (e) {
      // If there's a permission error, it's caught here but doesn't block UI
      debugPrint('Firestore error details: $e');
    }
  }

  Future<void> _signOut() async {
    if (isSigningOut) return;

    setState(() {
      isSigningOut = true;
    });

    try {
      await _auth.signOut();
      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SignInPage()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
      setState(() {
        isSigningOut = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for responsive layout
    final size = MediaQuery.of(context).size;
    final isSmallScreen = size.width < 600;
    final horizontalMargin =
        size.width > 1000 ? 300.0 : (size.width > 800 ? 100.0 : 16.0);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child:
            isLoading
                ? Center(
                  child: SpinKitFadingCircle(
                    color: Colors.blue[700]!,
                    size: 45.0,
                  ),
                )
                : SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontalMargin,
                      vertical: isSmallScreen ? 16 : 24,
                    ),
                    child: Column(
                      children: [
                        // Main card
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(
                                  (0.05 * 255).toInt(),
                                ),
                                spreadRadius: 1,
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Header with purple background - using local gradient instead of network image
                              Container(
                                height: 100,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF8863F7),
                                      const Color(0xFF6E8BF7),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.purple.withAlpha(
                                        (0.3 * 255).toInt(),
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    // Decorative elements
                                    Positioned(
                                      top: -20,
                                      right: -20,
                                      child: Container(
                                        width: 100,
                                        height: 100,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(
                                            (0.1 * 255).toInt(),
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      bottom: -40,
                                      left: -20,
                                      child: Container(
                                        width: 80,
                                        height: 80,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(
                                            (0.1 * 255).toInt(),
                                          ),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),

                                    // Admin badge
                                    Positioned(
                                      top: 16,
                                      right: 16,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withAlpha(
                                            (0.2 * 255).toInt(),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withAlpha(
                                              (0.5 * 255).toInt(),
                                            ),
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(
                                                (0.1 * 255).toInt(),
                                              ),
                                              blurRadius: 8,
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.verified,
                                              color: Colors.white,
                                              size: 16,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              'Administrator',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Avatar - overlapping header and content
                              Transform.translate(
                                offset: const Offset(0, -40),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withAlpha(
                                          (0.1 * 255).toInt(),
                                        ),
                                        spreadRadius: 1,
                                        blurRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Hero(
                                    tag: 'profile-avatar',
                                    child: Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        image: DecorationImage(
                                          image: AssetImage(
                                            'assets/images/profile.png',
                                          ),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),

                              // Name and information
                              Transform.translate(
                                offset: const Offset(0, -30),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Column(
                                    children: [
                                      const Text(
                                        'Unicon Finance',
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF333333),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Welcome to your account settings',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 20),

                                      // Email with actual user email
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[50],
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[200]!,
                                            width: 1,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withAlpha(
                                                (0.02 * 255).toInt(),
                                              ),
                                              blurRadius: 5,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withAlpha(
                                                  (0.1 * 255).toInt(),
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                Icons.email_outlined,
                                                size: 16,
                                                color: Colors.blue[700],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              userEmail,
                                              style: TextStyle(
                                                color: Colors.grey[800],
                                                fontWeight: FontWeight.w500,
                                                fontSize: 15,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 40),

                                      // Info cards with fixed heights
                                      LayoutBuilder(
                                        builder: (context, constraints) {
                                          if (constraints.maxWidth < 400) {
                                            // Stack cards vertically on small screens
                                            return Column(
                                              children: [
                                                _buildBeautifulInfoCard(
                                                  'Last Login',
                                                  '$lastLoginDate • $lastLoginTime',
                                                  Icons.access_time_rounded,
                                                  Colors.blue,
                                                ),
                                                const SizedBox(height: 12),
                                                _buildBeautifulInfoCard(
                                                  'Account Creator',
                                                  accountCreated,
                                                  Icons.business_rounded,
                                                  Colors.purple,
                                                ),
                                              ],
                                            );
                                          } else {
                                            // Place cards side by side on larger screens
                                            return IntrinsicHeight(
                                              child: Row(
                                                children: [
                                                  Expanded(
                                                    child: _buildBeautifulInfoCard(
                                                      'Last Login',
                                                      '$lastLoginDate • $lastLoginTime',
                                                      Icons.access_time_rounded,
                                                      Colors.blue,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child:
                                                        _buildBeautifulInfoCard(
                                                          'Account Creator',
                                                          accountCreated,
                                                          Icons
                                                              .business_rounded,
                                                          Colors.purple,
                                                        ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                      ),

                                      const SizedBox(height: 30),

                                      // Customer Support Section
                                      _buildCustomerSupportSection(),

                                      const SizedBox(height: 0),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Sign Out Button styled like Sign In button
                        Container(
                          width: double.infinity,
                          height: 54,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withAlpha(
                                  (0.3 * 255).toInt(),
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: isSigningOut ? null : _signOut,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.blueAccent
                                  .withAlpha((0.7 * 255).toInt()),
                              disabledForegroundColor: Colors.white.withAlpha(
                                (0.8 * 255).toInt(),
                              ),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child:
                                isSigningOut
                                    ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: SpinKitFadingCircle(
                                        color: Colors.white,
                                        size: 22.0,
                                      ),
                                    )
                                    : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.logout, size: 20),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Sign Out',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                          ),
                        ),

                        // Bottom spacer for better scrolling experience
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
      ),
    );
  }

  // Customer Support Section
  Widget _buildCustomerSupportSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with toggle button
        InkWell(
          onTap: () {
            setState(() {
              _showSupportSection = !_showSupportSection;
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withAlpha(15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.withAlpha(50)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.support_agent_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Customer Support Information',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
                Icon(
                  _showSupportSection
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.blue,
                ),
              ],
            ),
          ),
        ),

        // Expandable form for customer support details
        if (_showSupportSection)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(10),
                  blurRadius: 6,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Form(
              key: _supportFormKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Contact Information',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF333333),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'These details will be displayed in the customer app',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 24),

                  // Two columns layout on larger screens
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 500;

                      if (isWide) {
                        return Column(
                          children: [
                            // First row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _phoneController,
                                    'Phone Number',
                                    'Enter company phone number',
                                    Icons.phone,
                                    true,
                                    textInputType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    _whatsappController,
                                    'WhatsApp',
                                    'Enter WhatsApp number',
                                    Icons.forum_rounded,
                                    false,
                                    textInputType: TextInputType.phone,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Second row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _webController,
                                    'Website',
                                    'Enter company website URL',
                                    Icons.web,
                                    false,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    _faxController,
                                    'Fax Number',
                                    'Enter fax number if available',
                                    Icons.fax,
                                    false,
                                    textInputType: TextInputType.phone,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Third row
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _emailController,
                                    'Email Address',
                                    'Enter company email address',
                                    Icons.email,
                                    true,
                                    textInputType: TextInputType.emailAddress,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    _messageController,
                                    'Support Message',
                                    'Enter support message or greeting',
                                    Icons.message,
                                    false,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Bottom row with address and location
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _buildTextField(
                                    _addressController,
                                    'Address',
                                    'Enter company address',
                                    Icons.location_on,
                                    true,
                                    maxLines: 3,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildTextField(
                                    _locationController,
                                    'Google Maps Link',
                                    'Enter Google Maps location link',
                                    Icons.map,
                                    false,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      } else {
                        // Single column layout for smaller screens
                        return Column(
                          children: [
                            _buildTextField(
                              _phoneController,
                              'Phone Number',
                              'Enter company phone number',
                              Icons.phone,
                              true,
                              textInputType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _whatsappController,
                              'WhatsApp',
                              'Enter WhatsApp number',
                              Icons.forum_rounded,
                              false,
                              textInputType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _webController,
                              'Website',
                              'Enter company website URL',
                              Icons.web,
                              false,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _faxController,
                              'Fax Number',
                              'Enter fax number if available',
                              Icons.fax,
                              false,
                              textInputType: TextInputType.phone,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _emailController,
                              'Email Address',
                              'Enter company email address',
                              Icons.email,
                              true,
                              textInputType: TextInputType.emailAddress,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _messageController,
                              'Support Message',
                              'Enter support message or greeting',
                              Icons.message,
                              false,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _addressController,
                              'Address',
                              'Enter company address',
                              Icons.location_on,
                              true,
                              maxLines: 3,
                            ),
                            const SizedBox(height: 16),
                            _buildTextField(
                              _locationController,
                              'Google Maps Link',
                              'Enter Google Maps location link',
                              Icons.map,
                              false,
                            ),
                          ],
                        );
                      }
                    },
                  ),

                  const SizedBox(height: 24),

                  // Save & Cancel Buttons
                  // UPDATED: Improved button layout with same size and better visual appearance
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSavingSupport ? null : _saveSupportData,
                          icon: isSavingSupport
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 20),
                          label: Text(
                            isSavingSupport ? 'Saving...' : 'Save Changes',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 1,
                            shadowColor: Colors.blue.withAlpha((0.4 * 255).toInt()),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: isSavingSupport
                              ? null
                              : () {
                                  setState(() {
                                    _showSupportSection = false;
                                    _loadSupportData(); // Reset fields to original values
                                  });
                                },
                          icon: const Icon(Icons.delete_forever_rounded, size: 20),
                          label: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 1,
                            shadowColor: Colors.red.withAlpha((0.4 * 255).toInt()),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // Text field with consistent design for customer support form
  Widget _buildTextField(
    TextEditingController controller,
    String label,
    String hint,
    IconData icon,
    bool isRequired, {
    TextInputType textInputType = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: textInputType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.blue),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red[400]!, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red[400]!, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator:
          isRequired
              ? (value) {
                if (value == null || value.isEmpty) {
                  return '$label is required';
                }

                // Email validation
                if (textInputType == TextInputType.emailAddress) {
                  final bool emailValid = RegExp(
                    r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
                  ).hasMatch(value);

                  if (!emailValid) {
                    return 'Please enter a valid email address';
                  }
                }

                // Phone validation
                if (textInputType == TextInputType.phone) {
                  // Simple validation to ensure it's numeric
                  if (value.replaceAll(RegExp(r'[\s\-\(\)]'), '').length < 6) {
                    return 'Please enter a valid phone number';
                  }
                }

                return null;
              }
              : null,
    );
  }

  // Beautiful info card with consistent height and better date/time presentation
  Widget _buildBeautifulInfoCard(
    String title,
    String value,
    IconData icon,
    MaterialColor color,
  ) {
    return Container(
      height: 90, // Fixed height for consistent sizing
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha((0.08 * 255).toInt()),
            spreadRadius: 0,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Left side with icon in colored circle
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withAlpha((0.12 * 255).toInt()),
              shape: BoxShape.circle,
            ),
            child: Center(child: Icon(icon, color: color[700], size: 22)),
          ),

          const SizedBox(width: 14),

          // Right side with text information
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: color[800],
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}