import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/Home.png', // Your image path
            width: 720, // Set your desired width
            height: 420, // Set your desired height
            fit:
                BoxFit
                    .cover, // You can use different BoxFit types, like `contain` or `cover`
          ),
          const SizedBox(height: 0),
        ],
      ),
    );
  }
}
