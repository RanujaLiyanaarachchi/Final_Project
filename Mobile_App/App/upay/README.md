# UPay

UPay is a comprehensive mobile payment application built with Flutter, designed to facilitate secure digital payments and financial management.

## Features

- **Dashboard**: Financial control center with balance overview and quick actions
- **Bill Management**: View, track, and pay bills with PDF generation support
- **Notifications**: Real-time transaction alerts and payment reminders
- **Multi-language Support**: English, Sinhala (සිංහල), and Tamil (தமிழ்)
- **Liability Tracking**: Manage loans and financial obligations
- **Profile Management**: Update personal information securely
- **Firebase Integration**: Authentication, Cloud Firestore, and Cloud Messaging
- **Secure Storage**: Protected access to sensitive user information

## Technologies Used

- **Flutter**: Cross-platform UI framework
- **Firebase**: Authentication, Firestore, Cloud Storage, and Cloud Messaging
- **Provider**: State management
- **Intl**: Internationalization support
- **PDF**: Document generation for bills and receipts
- **Local Notifications**: Background alerts for critical events

## Installation

1. Clone the repository:
    git clone <https://github.com/RanujaLiyanaarachchi/Final_Project.git>

2. Navigate to the project folder:  Mobile_App/App/
    cd upay

3. Install dependencies:
    flutter pub get

4. Run the app:
    flutter run

5. Sign in using NIC:
    Use one of the following test NIC numbers:
    - 123456789123
    - 987654321987

6. Sign in using Phone Number:
    Use the following test credentials:
    - Phone number: 0760620019
    - OTP: 123456

## Important Testing Information

1. You can use your real phone number and enter the received OTP during authentication. You can also sign in with your real NIC number after adding your personal data through the admin panel.

2. Admin Panel Access: To manage user data, access the desktop admin panel application here: [Admin Panel (flutter Desktop App)](https://github.com/RanujaLiyanaarachchi/Final_Project/tree/cd5907b1fb2733638173315f792e590eb5d61ede/Desktop_App)

3. Adding Your Data: To use the app with your real information, access the admin panel from our GitHub repository, set up your personal and financial details, and then sign in using your actual NIC number to view your real data.

4. For Evaluation: If you prefer to test first, use the provided test NICs which have been pre-configured with sample financial data.

## Source Code Access

Access the complete source code for both applications:

- Mobile Application: The main UPay mobile application built with Flutter
- Admin Panel: Desktop application for managing user data and system administration

Both are available in our GitHub repository: [UPay Project Repository](https://github.com/RanujaLiyanaarachchi/Final_Project.git)

## Project Structure

- **lib/**
  - **l10n/**: Localization files
  - **main.dart**: Entry point of the application
  - **screens/**: UI screens for different features
  - **services/**: Business logic and API interactions
  - **providers/**: State management

## Configuration

This app requires Firebase setup. Make sure to add your own `google-services.json` for Android and `GoogleService-Info.plist` for iOS.

## Future Enhancements

- QR code payments
- Advanced analytics
- Scheduled payments
- Card management features
