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

2. Navigate to the project folder:
    cd upay

3. Install dependencies:
    flutter pub get

4. Run the app:
    flutter run

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
