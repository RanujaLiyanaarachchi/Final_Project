import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_si.dart';
import 'app_localizations_ta.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('si'),
    Locale('ta')
  ];

  /// Application name
  ///
  /// In en, this message translates to:
  /// **'UPay'**
  String get app_name;

  /// Greeting message
  ///
  /// In en, this message translates to:
  /// **'Hi There,'**
  String get hiThere;

  /// Welcome text Title
  ///
  /// In en, this message translates to:
  /// **'Welcome Back To UPay'**
  String get welcome_to_UPay;

  /// Welcome text Body
  ///
  /// In en, this message translates to:
  /// **'Easy ways to manage your finances'**
  String get welcome_message;

  /// Text on the welcome screen button
  ///
  /// In en, this message translates to:
  /// **'Let’s Begin'**
  String get lets_begin;

  /// Sign in button label
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get sign_in;

  /// Email input label
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// Password input label
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// Forgot password button label
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgot_password;

  /// Error message for connection issues
  ///
  /// In en, this message translates to:
  /// **'Check your connection and Try again'**
  String get connection_error;

  /// Loading message for validation
  ///
  /// In en, this message translates to:
  /// **'validating...'**
  String get validating;

  /// Heading for NIC verification screen
  ///
  /// In en, this message translates to:
  /// **'Validate'**
  String get nic_verification_heading;

  /// Loading message for verification
  ///
  /// In en, this message translates to:
  /// **'verifying...'**
  String get verifying;

  /// Prompt for entering a valid NIC number
  ///
  /// In en, this message translates to:
  /// **'Enter the correct NIC'**
  String get enter_valid_nic_number;

  /// Prompt for entering a 6-digit code
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 6-digit code'**
  String get enter_valid_6digit_code;

  /// Prompt for entering the correct OTP
  ///
  /// In en, this message translates to:
  /// **'Enter the correct OTP'**
  String get enter_correct_otp;

  /// Message indicating the verification code was sent again
  ///
  /// In en, this message translates to:
  /// **'Verification code sent again'**
  String get verification_code_sent_again;

  /// Message indicating the code has timed out
  ///
  /// In en, this message translates to:
  /// **'Request has timed out.Try again'**
  String get code_timed_out;

  /// Forgot password button label
  ///
  /// In en, this message translates to:
  /// **'Forgot?'**
  String get forgot_password_title;

  /// Prompt for email input to reset password
  ///
  /// In en, this message translates to:
  /// **'Dont worry! It occurs. Please enter the email address linked with your account'**
  String get enter_email_reset;

  /// Send button label
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// Reset password screen title
  ///
  /// In en, this message translates to:
  /// **'Reset Password'**
  String get reset_password;

  /// Label for new password input
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get new_password;

  /// Label for confirming password input
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirm_password;

  /// Confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Message when password is successfully updated
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get password_updated;

  /// Message after successful password update
  ///
  /// In en, this message translates to:
  /// **'Your password has been successfully updated. You can now use your new password to access your account securely.'**
  String get password_success_message_1;

  /// Message after successful password update
  ///
  /// In en, this message translates to:
  /// **'If you experience any issues or have any concerns, please don\'t hesitate to contact our support team for assistance.'**
  String get password_success_message_2;

  /// Welcome text on the welcome screen
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcome;

  /// Prompt for agreeing to terms
  ///
  /// In en, this message translates to:
  /// **'Agree to our terms and conditions?'**
  String get agree_terms;

  /// Button label to reject
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// Button label to accept
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// Terms and conditions title
  ///
  /// In en, this message translates to:
  /// **'Terms and Conditions'**
  String get terms_conditions;

  /// Privacy policy title
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacy_policy;

  /// Home screen label
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// Messages tab label
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get messages;

  /// Settings screen label
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Pay button label
  ///
  /// In en, this message translates to:
  /// **'Pay'**
  String get pay;

  /// Total amount to be paid
  ///
  /// In en, this message translates to:
  /// **'Total Payable'**
  String get total_payable;

  /// Label for payable amount
  ///
  /// In en, this message translates to:
  /// **'Payable Amount'**
  String get payable_amount;

  /// Field label for account number
  ///
  /// In en, this message translates to:
  /// **'Account Number'**
  String get account_number;

  /// Field label for national ID
  ///
  /// In en, this message translates to:
  /// **'NIC'**
  String get nic;

  /// Amount input field label
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// Next button label
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Payment gateway screen title
  ///
  /// In en, this message translates to:
  /// **'Payment Gateway'**
  String get payment_gateway;

  /// Receipt screen title
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receipt;

  /// Done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Sign out button label
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get sign_out;

  /// Label to change app language
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get change_language;

  /// Message when no messages exist
  ///
  /// In en, this message translates to:
  /// **'No messages available'**
  String get no_messages;

  /// Payment successful message
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get payment_successful;

  /// Label to download the receipt
  ///
  /// In en, this message translates to:
  /// **'Download Receipt'**
  String get download_receipt;

  /// Message on successful password reset
  ///
  /// In en, this message translates to:
  /// **'Password reset link sent to your email'**
  String get password_reset_success;

  /// Message on failed password reset
  ///
  /// In en, this message translates to:
  /// **'Password reset failed'**
  String get password_reset_failed;

  /// Title for password reset
  ///
  /// In en, this message translates to:
  /// **'Password Reset'**
  String get password_reset;

  /// Error message for mismatched passwords
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get password_mismatch;

  /// Message when update fails
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get update_failed;

  /// Button label to update profile
  ///
  /// In en, this message translates to:
  /// **'Update Profile'**
  String get update_profile;

  /// Message after profile is updated
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profile_updated;

  /// Message if profile update fails
  ///
  /// In en, this message translates to:
  /// **'Profile update failed'**
  String get update_profile_failed;

  /// Label for updating profile picture
  ///
  /// In en, this message translates to:
  /// **'Update Profile Picture'**
  String get update_profile_picture;

  /// Upload picture button
  ///
  /// In en, this message translates to:
  /// **'Upload Picture'**
  String get upload_picture;

  /// Select picture button
  ///
  /// In en, this message translates to:
  /// **'Select Picture'**
  String get select_picture;

  /// Profile screen label
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// Edit profile button
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get edit_profile;

  /// Change password button
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get change_password;

  /// Label for current password field
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get current_password;

  /// Error message for incorrect current password
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get current_password_incorrect;

  /// Validation message for current password
  ///
  /// In en, this message translates to:
  /// **'Current password is required'**
  String get current_password_required;

  /// Validation message for new password
  ///
  /// In en, this message translates to:
  /// **'New password is required'**
  String get new_password_required;

  /// Validation message for confirm password
  ///
  /// In en, this message translates to:
  /// **'Confirm password is required'**
  String get confirm_password_required;

  /// Dashboard screen label
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// Bill section label
  ///
  /// In en, this message translates to:
  /// **'Bill'**
  String get bill;

  /// Label for total amount due
  ///
  /// In en, this message translates to:
  /// **'Total Amount Due'**
  String get total_amount_due;

  /// Label for payment details section
  ///
  /// In en, this message translates to:
  /// **'Payment Details'**
  String get payment_details;

  /// Button label to confirm payment
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment'**
  String get confirm_payment;

  /// Prompt to confirm specific payment amount
  ///
  /// In en, this message translates to:
  /// **'Confirm Payment of'**
  String get confirm_payment_of;

  /// Pay now button label
  ///
  /// In en, this message translates to:
  /// **'Pay Now'**
  String get pay_now;

  /// Proceed with payment label
  ///
  /// In en, this message translates to:
  /// **'Proceed with Payment'**
  String get proceed_with_payment;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button label to go to payment screen
  ///
  /// In en, this message translates to:
  /// **'Proceed to Payment'**
  String get proceed_to_payment;

  /// Notifications screen label
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// Message when no new notifications
  ///
  /// In en, this message translates to:
  /// **'No new notifications'**
  String get no_new_notifications;

  /// Button to return to dashboard
  ///
  /// In en, this message translates to:
  /// **'Back to Dashboard'**
  String get back_to_dashboard;

  /// Message when no liabilities
  ///
  /// In en, this message translates to:
  /// **'You have no outstanding liabilities.'**
  String get no_outstanding_liabilities;

  /// Bill payments section title
  ///
  /// In en, this message translates to:
  /// **'Bill Payments'**
  String get bill_payments;

  /// Message when no bills are present
  ///
  /// In en, this message translates to:
  /// **'No bills available'**
  String get no_bills_available;

  /// Message when inbox is empty
  ///
  /// In en, this message translates to:
  /// **'No new messages'**
  String get no_new_messages;

  /// Dropdown label for selecting language
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// Sign out button label (duplicate, lowercase key recommended)
  ///
  /// In en, this message translates to:
  /// **'Sign Out'**
  String get sign_Out;

  /// Settings page title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// Prompt text for language selection
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get select_language;

  /// Greeting message with user's name
  ///
  /// In en, this message translates to:
  /// **'Hello {name},'**
  String helloUser(String name);

  /// Welcome back message
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// Label for user's liabilities
  ///
  /// In en, this message translates to:
  /// **'My Liabilities'**
  String get myLiabilities;

  /// Button label to see details
  ///
  /// In en, this message translates to:
  /// **'See details'**
  String get seeDetails;

  /// Label for monthly installment
  ///
  /// In en, this message translates to:
  /// **'Monthly Installment'**
  String get monthlyInstallment;

  /// Label for next installment
  ///
  /// In en, this message translates to:
  /// **'Next Month Installment'**
  String get nextInstallment;

  /// Label for including arrears in installments
  ///
  /// In en, this message translates to:
  /// **'Includes Arrears Installments'**
  String get includesArrearsInstallments;

  /// Label for paid status
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paid;

  /// Label for remaining balance due
  ///
  /// In en, this message translates to:
  /// **'Remaining Balance Due'**
  String get remainingBalanceDue;

  /// Support message for users
  ///
  /// In en, this message translates to:
  /// **'If there is any problem, don\'t panic'**
  String get supportMessage;

  /// Description for support message
  ///
  /// In en, this message translates to:
  /// **'For any issues or concerns, feel free to reach out to our support team. We\'re here to help! 😊❤'**
  String get supportDescription;

  /// Label for completed status
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// Payments section title
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get payments;

  /// Label for full name input
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get full_name;

  /// Label for NIC number input
  ///
  /// In en, this message translates to:
  /// **'NIC Number'**
  String get nic_number;

  /// Label for address input
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// Label for birth date input
  ///
  /// In en, this message translates to:
  /// **'Birth Day'**
  String get birth_day;

  /// Label for gender input
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// Label for landline number input
  ///
  /// In en, this message translates to:
  /// **'Land Line'**
  String get land_line;

  /// Label for mobile number input
  ///
  /// In en, this message translates to:
  /// **'Mobile'**
  String get mobile;

  /// Button label to clear all fields
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clear_all;

  /// Label for opening with viewer status
  ///
  /// In en, this message translates to:
  /// **'Opening with viewer...'**
  String get opening_with_viewer;

  /// Message when there are no new notifications
  ///
  /// In en, this message translates to:
  /// **'\n We’ll let you know when there will be \n something  to update you.'**
  String get no_new_notifications_message;

  /// Label for opening remote file status
  ///
  /// In en, this message translates to:
  /// **'Opening remote file...'**
  String get opening_remote_file;

  /// Label for file services section
  ///
  /// In en, this message translates to:
  /// **'File Services'**
  String get fileservices;

  /// Label for message details
  ///
  /// In en, this message translates to:
  /// **'Message Details'**
  String get message_details;

  /// Label for unavailable date
  ///
  /// In en, this message translates to:
  /// **'Date not available'**
  String get date_not_available;

  /// Message when there is no content
  ///
  /// In en, this message translates to:
  /// **'No content available'**
  String get no_content;

  /// Label for downloading status
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloading;

  /// Button label to open a file or link
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// Button label to share a file or link
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Error message when file URL is not available
  ///
  /// In en, this message translates to:
  /// **'File URL not available'**
  String get file_url_not_available;

  /// Label for opening status
  ///
  /// In en, this message translates to:
  /// **'Opening...'**
  String get opening;

  /// Message when file is ready to open
  ///
  /// In en, this message translates to:
  /// **'File is ready. Opening...'**
  String get file_ready_opening;

  /// Error message when download fails
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get download_failed;

  /// Error message when no app is available to open the file
  ///
  /// In en, this message translates to:
  /// **'No app available to open this file'**
  String get no_app_for_file;

  /// Button label to delete a message
  ///
  /// In en, this message translates to:
  /// **'Delete Message'**
  String get delete_message;

  /// Confirmation message for deleting a message
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this message?'**
  String get delete_message_confirmation;

  /// Message when opening fails and downloading
  ///
  /// In en, this message translates to:
  /// **'Opening failed. Downloading...'**
  String get opening_failed_downloading;

  /// Error message when storage permission is required
  ///
  /// In en, this message translates to:
  /// **'Storage permission required'**
  String get storage_permission_required;

  /// Message when file is downloaded
  ///
  /// In en, this message translates to:
  /// **'File downloaded'**
  String get file_downloaded;

  /// Error message when download fails
  ///
  /// In en, this message translates to:
  /// **'Download error'**
  String get download_error;

  /// Label for preparing to share status
  ///
  /// In en, this message translates to:
  /// **'Preparing to share...'**
  String get preparing_to_share;

  /// Button label to clear all messages
  ///
  /// In en, this message translates to:
  /// **'Clear All Messages'**
  String get clear_all_messages;

  /// Confirmation message for clearing all messages
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all messages?'**
  String get clear_all_messages_confirmation;

  /// Label for sharing status
  ///
  /// In en, this message translates to:
  /// **'Sharing...'**
  String get sharing;

  /// Error message when sharing fails
  ///
  /// In en, this message translates to:
  /// **'Sharing error'**
  String get sharing_error;

  /// Label for downloading for viewing status
  ///
  /// In en, this message translates to:
  /// **'Downloading for viewing...'**
  String get downloading_for_viewing;

  /// Label for loading messages status
  ///
  /// In en, this message translates to:
  /// **'Loading messages...'**
  String get loadingMessages;

  /// Label for total arrears amount
  ///
  /// In en, this message translates to:
  /// **'Total Arrears:'**
  String get total_arrears;

  /// Label for last bill amount
  ///
  /// In en, this message translates to:
  /// **'Last Bill Amount'**
  String get last_bill_amount;

  /// Label for last payment amount
  ///
  /// In en, this message translates to:
  /// **'Last Payment Amount'**
  String get last_payment_amount;

  /// Label for user's finances
  ///
  /// In en, this message translates to:
  /// **'My Finances Were'**
  String get myFinanceWere;

  /// Label for date or time
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get on;

  /// Label for Anuradhapura location
  ///
  /// In en, this message translates to:
  /// **'Anuradhapura'**
  String get anuradhapura;

  /// Label for Unicon Finance company
  ///
  /// In en, this message translates to:
  /// **'Unicon Finance'**
  String get uniconFinance;

  /// Label to view location on map
  ///
  /// In en, this message translates to:
  /// **'Tap to view on map'**
  String get tapToViewOnMap;

  /// Label for biometric authentication
  ///
  /// In en, this message translates to:
  /// **'Biometrics'**
  String get biometrics;

  /// Label for setting up a PIN
  ///
  /// In en, this message translates to:
  /// **'Set up PIN'**
  String get set_up_pin;

  /// Message for creating a PIN
  ///
  /// In en, this message translates to:
  /// **'Create a 4-digit PIN to secure your account.'**
  String get create_pin_message;

  /// Message for confirming a PIN
  ///
  /// In en, this message translates to:
  /// **'Confirm your 4-digit PIN.'**
  String get confirm_pin_message;

  /// Button label to save the PIN
  ///
  /// In en, this message translates to:
  /// **'Save PIN'**
  String get save_pin;

  /// Button label to disable a feature
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get disable;

  /// Label for entering a PIN
  ///
  /// In en, this message translates to:
  /// **'Enter PIN'**
  String get enter_pin;

  /// Label for confirming a PIN
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get confirm_pin;

  /// Message when profile image is updated
  ///
  /// In en, this message translates to:
  /// **'Profile image updated'**
  String get profile_image_updated;

  /// Message when profile image update fails
  ///
  /// In en, this message translates to:
  /// **'Profile image update failed'**
  String get profile_image_update_failed;

  /// Label for cleaning app data
  ///
  /// In en, this message translates to:
  /// **'Clean App Data'**
  String get clean_app_data;

  /// Message for cleaning app data
  ///
  /// In en, this message translates to:
  /// **'This will remove all app data and reset the app to its initial state.'**
  String get clean_app_data_message;

  /// Message when app data is cleaned and restarting
  ///
  /// In en, this message translates to:
  /// **'Data cleaned. Restarting app...'**
  String get data_cleaned_restarting;

  /// Confirmation message for signing out
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to sign out?'**
  String get sign_out_confirm_message;

  /// Error message when signing out fails
  ///
  /// In en, this message translates to:
  /// **'Error signing out'**
  String get sign_out_error;

  /// Label for auto sign out feature
  ///
  /// In en, this message translates to:
  /// **'Auto Sign Out'**
  String get auto_sign_out;

  /// Label for cleaning data
  ///
  /// In en, this message translates to:
  /// **'Clean Data'**
  String get clean_data;

  /// Label for about us section
  ///
  /// In en, this message translates to:
  /// **'About Us'**
  String get about_us;

  /// Label for app guide section
  ///
  /// In en, this message translates to:
  /// **'App Guide'**
  String get app_guide;

  /// Label for user's liability
  ///
  /// In en, this message translates to:
  /// **'My Liability'**
  String get my_liability;

  /// Label for user's finance details
  ///
  /// In en, this message translates to:
  /// **'Your Finance Details'**
  String get your_finance_details;

  /// Label for first name input
  ///
  /// In en, this message translates to:
  /// **'First Name:'**
  String get first_name;

  /// Label for vehicle number input
  ///
  /// In en, this message translates to:
  /// **'Vehicle Number:'**
  String get vehicle_number;

  /// Label for loan amount input
  ///
  /// In en, this message translates to:
  /// **'Loan Amount:'**
  String get loan_amount;

  /// Label for opening date input
  ///
  /// In en, this message translates to:
  /// **'Opening Date:'**
  String get opening_date;

  /// Label for interest rate input
  ///
  /// In en, this message translates to:
  /// **'Interest Rate:'**
  String get interest_rate;

  /// Label for maturity date input
  ///
  /// In en, this message translates to:
  /// **'Maturity Date:'**
  String get maturity_date;

  /// Label for balance amount
  ///
  /// In en, this message translates to:
  /// **'Balance:'**
  String get balance;

  /// Label for next installment date
  ///
  /// In en, this message translates to:
  /// **'Next Installment Date:'**
  String get next_installment_date;

  /// Label for next installment amount
  ///
  /// In en, this message translates to:
  /// **'Next Installment Amount:'**
  String get next_installment_amount;

  /// Label for remaining installments
  ///
  /// In en, this message translates to:
  /// **'Remaining Installments:'**
  String get remaining_installments;

  /// Button label to call
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// Button label to open WhatsApp
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsapp;

  /// Button label to open website
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get website;

  /// Button label to send fax
  ///
  /// In en, this message translates to:
  /// **'Fax'**
  String get fax;

  /// Button label to send mail
  ///
  /// In en, this message translates to:
  /// **'Mail'**
  String get mail;

  /// Button label to send message
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// Button label to show location
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// Button label for payment
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// Label for amount to be paid
  ///
  /// In en, this message translates to:
  /// **'Amount to be paid'**
  String get amount_to_be_paid;

  /// Button label to pay bill
  ///
  /// In en, this message translates to:
  /// **'Pay Bill'**
  String get pay_bill;

  /// Label for amount to be paid
  ///
  /// In en, this message translates to:
  /// **'Pay Amount'**
  String get pay_amount;

  /// Title for payment success message
  ///
  /// In en, this message translates to:
  /// **'Payment Successful'**
  String get payment_success_title;

  /// Subtitle for payment success message
  ///
  /// In en, this message translates to:
  /// **'Your payment was successful!'**
  String get payment_success_subtitle;

  /// Label for payment status
  ///
  /// In en, this message translates to:
  /// **'Payment Status'**
  String get payment_status;

  /// Label for success status
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get success;

  /// Label for name input
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// Label for sender input
  ///
  /// In en, this message translates to:
  /// **'Sender'**
  String get sender;

  /// Button label to get PDF receipt
  ///
  /// In en, this message translates to:
  /// **'Get PDF Receipt'**
  String get get_pdf_receipt;

  /// Title for notifications screen
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications_title;

  /// Label for changing username
  ///
  /// In en, this message translates to:
  /// **'Change Username'**
  String get change_username;

  /// Label for two-factor authentication
  ///
  /// In en, this message translates to:
  /// **'Two-Factor Authentication'**
  String get two_factor_authentication;

  /// Label for language selection
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Label for app lock feature
  ///
  /// In en, this message translates to:
  /// **'App Lock'**
  String get app_lock;

  /// Label for notification
  ///
  /// In en, this message translates to:
  /// **'notification'**
  String get notification;

  /// Error message for invalid NIC format
  ///
  /// In en, this message translates to:
  /// **'Invalid NIC format'**
  String get invalid_nic_format;

  /// Error message for unregistered NIC
  ///
  /// In en, this message translates to:
  /// **'NIC not registered'**
  String get nic_not_registered;

  /// Error message for NIC check failure
  ///
  /// In en, this message translates to:
  /// **'Error checking NIC'**
  String get error_checking_nic;

  /// Error message for verification failure
  ///
  /// In en, this message translates to:
  /// **'Verification failed'**
  String get verification_failed;

  /// Message for verification failure
  ///
  /// In en, this message translates to:
  /// **'Verification failed. Please try again.'**
  String get verification_failed_message;

  /// Validation message for NIC input
  ///
  /// In en, this message translates to:
  /// **'NIC is required'**
  String get nic_required;

  /// Button label to verify NIC
  ///
  /// In en, this message translates to:
  /// **'Verify NIC'**
  String get verify_nic;

  /// Validation message for phone number input
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phone_required;

  /// Error message for invalid phone number format
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number format'**
  String get invalid_phone_format;

  /// Help text for sign-in screen
  ///
  /// In en, this message translates to:
  /// **'Please enter your email and password to sign in.'**
  String get sign_in_help_text;

  /// Error message for invalid phone number
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number'**
  String get invalid_phone;

  /// Title for OTP verification screen
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get otp_verification;

  /// Label for verification code input
  ///
  /// In en, this message translates to:
  /// **'Verification Code'**
  String get verification_code;

  /// Message indicating where the code was sent
  ///
  /// In en, this message translates to:
  /// **'Code sent to'**
  String get code_sent_to;

  /// Button label to verify OTP
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// Message for resending OTP code
  ///
  /// In en, this message translates to:
  /// **'Didn\'t receive the code?'**
  String get didnt_receive_code;

  /// Button label to resend OTP code
  ///
  /// In en, this message translates to:
  /// **'Resend'**
  String get resend;

  /// Help text for NIC input
  ///
  /// In en, this message translates to:
  /// **'Please enter your NIC number for verification.'**
  String get nic_help_text;

  /// Title for NIC verification screen
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get nic_verification;

  /// Label for entering NIC number
  ///
  /// In en, this message translates to:
  /// **'Enter correct NIC'**
  String get enter_nic;

  /// Message for NIC verification
  ///
  /// In en, this message translates to:
  /// **'Verify your identity.'**
  String get nic_verification_message;

  /// Label for phone number input
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phone_number;

  /// Label for customer ID input
  ///
  /// In en, this message translates to:
  /// **'Customer ID'**
  String get customer_id;

  /// Label for time elapsed in minutes
  ///
  /// In en, this message translates to:
  /// **'minutes ago'**
  String get minutes_ago;

  /// Label for time elapsed in hours
  ///
  /// In en, this message translates to:
  /// **'hours ago'**
  String get hours_ago;

  /// Label for time elapsed in days
  ///
  /// In en, this message translates to:
  /// **'days ago'**
  String get days_ago;

  /// Label for unknown date
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get unknown_date;

  /// Label for reference input
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get reference;

  /// Button label to close a dialog or screen
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Button label to reply to a message
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get reply;

  /// Button label to clear all notifications
  ///
  /// In en, this message translates to:
  /// **'Clear All Notifications'**
  String get clear_all_notifications;

  /// Confirmation message for clearing all notifications
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all notifications?'**
  String get clear_all_confirmation;

  /// Button label to delete all notifications
  ///
  /// In en, this message translates to:
  /// **'Delete All'**
  String get delete_all;

  /// Button label to refresh the screen
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Error message when loading notifications fails
  ///
  /// In en, this message translates to:
  /// **'Error loading notifications'**
  String get error_loading_notifications;

  /// Error message when loading notifications fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications'**
  String get failed_load_notifications;

  /// Button label to try again
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get try_again;

  /// Loading message for notifications
  ///
  /// In en, this message translates to:
  /// **'Loading notifications...'**
  String get loading_notifications;

  /// Label for attachments in messages
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachments;

  /// Button label to download an attachment
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// Error message when loading an image fails
  ///
  /// In en, this message translates to:
  /// **'Error loading image'**
  String get image_load_error;

  /// Label for an attachment
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// Button label to delete an item
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Label for additional attachments
  ///
  /// In en, this message translates to:
  /// **'More Attachments'**
  String get more_attachments;

  /// Label for a single additional attachment
  ///
  /// In en, this message translates to:
  /// **'More Attachment'**
  String get more_attachment;

  /// Confirmation message for clearing all notifications
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all notifications? This action cannot be undone.'**
  String get clear_all_notifications_confirm;

  /// Message when notifications are cleared
  ///
  /// In en, this message translates to:
  /// **'Notifications cleared'**
  String get notifications_cleared;

  /// Button label to clear an input or selection
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Button label to retry an action
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Message when there are no notifications
  ///
  /// In en, this message translates to:
  /// **'No notifications available'**
  String get no_notifications;

  /// Message when there are no notifications
  ///
  /// In en, this message translates to:
  /// **'You have no notifications at the moment.'**
  String get no_notifications_message;

  /// Label for today's date
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// Button label to open a link
  ///
  /// In en, this message translates to:
  /// **'Open Link'**
  String get open_link;

  /// Confirmation message for clearing all notifications
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all notifications? This action cannot be undone.'**
  String get clear_all_notifications_message;

  /// Error message for invalid NIC and phone number
  ///
  /// In en, this message translates to:
  /// **'Enter a valid NIC and phone number.'**
  String get enter_valid_nic_and_phone;

  /// Error message for invalid NIC
  ///
  /// In en, this message translates to:
  /// **'Enter a valid NIC.'**
  String get enter_valid_nic;

  /// Error message for incorrect NIC format
  ///
  /// In en, this message translates to:
  /// **'NIC is in incorrect format.'**
  String get nic_incorrect_format;

  /// Error message for invalid phone number
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number.'**
  String get enter_valid_phone;

  /// Error message for phone number length
  ///
  /// In en, this message translates to:
  /// **'Phone number is in incorrect format.'**
  String get phone_must_be_10_digits;

  /// Message when there are no notifications yet
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// Button label to cancel cleaning data
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel_clean;

  /// Button label to confirm cleaning data
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm_clean;

  /// Label for support section
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// Message indicating text was copied
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get copied;

  /// Label for all items or categories
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// Label for unread items or messages
  ///
  /// In en, this message translates to:
  /// **'Unread'**
  String get unread;

  /// Button label to mark all notifications as read
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get mark_all_as_read;

  /// Button label to view all items or messages
  ///
  /// In en, this message translates to:
  /// **'View all'**
  String get view;

  /// Message when there are no notifications
  ///
  /// In en, this message translates to:
  /// **'No notifications available'**
  String get notification_empty_message;

  /// Confirmation message for deleting a notification
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this notification?'**
  String get delete_notification_confirmation;

  /// Label for bill summary section
  ///
  /// In en, this message translates to:
  /// **'Bill Summary'**
  String get bill_summary;

  /// Label for monthly bill amount
  ///
  /// In en, this message translates to:
  /// **'Monthly Bill'**
  String get monthly_bill;

  /// Label for current bill amount
  ///
  /// In en, this message translates to:
  /// **'Current Bill'**
  String get current_bill;

  /// Label for bills section
  ///
  /// In en, this message translates to:
  /// **'Bills'**
  String get bills;

  /// Button label to delete a notification
  ///
  /// In en, this message translates to:
  /// **'Delete Notification'**
  String get delete_notification;

  /// Error message when deleting a message fails
  ///
  /// In en, this message translates to:
  /// **'Error deleting message'**
  String get error_deleting_message;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'si', 'ta'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'si': return AppLocalizationsSi();
    case 'ta': return AppLocalizationsTa();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
