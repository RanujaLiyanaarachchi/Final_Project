import 'package:flutter/material.dart';

class SecurityPage extends StatelessWidget {
  const SecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    final TextEditingController userNameController =
        TextEditingController(text: "JohnDoe");
    final TextEditingController passwordController =
        TextEditingController(text: "password123");

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 200, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Security Settings',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 20),

          // Search Field
          _buildSearchField(),

          const SizedBox(height: 30),

          // Two-column layout
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left Column - Read-only Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildReadOnlyField(
                      label: 'Name',
                      value: 'John Doe',
                      icon: Icons.person,
                    ),
                    const SizedBox(height: 20),
                    _buildReadOnlyField(
                      label: 'User ID',
                      value: 'ID123456',
                      icon: Icons.verified_user,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 40),

              // Right Column - Editable Fields
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildEditableField(
                      label: 'Change User Name',
                      controller: userNameController,
                      icon: Icons.person_outline,
                      isPassword: false,
                    ),
                    const SizedBox(height: 20),
                    _buildEditableField(
                      label: 'Change Password',
                      controller: passwordController,
                      icon: Icons.lock_outline,
                      isPassword: true,
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Update Button
          Center(
            child: ElevatedButton(
              onPressed: () {
                // Handle update logic
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Updated Successfully')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Update'),
            ),
          ),
        ],
      ),
    );
  }

  // Search Field
  Widget _buildSearchField() {
    return TextField(
      decoration: InputDecoration(
        hintText: 'Search Settings',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 15, horizontal: 15),
      ),
    );
  }

  // Editable Field
  Widget _buildEditableField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    required bool isPassword,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 16, color: Colors.blue)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          decoration: InputDecoration(
            prefixIcon: Icon(icon),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  // Read-only Field
  Widget _buildReadOnlyField({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w500, fontSize: 16, color: Colors.blue)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 15),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade100),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.blue.shade600),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 16, color: Colors.black),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
