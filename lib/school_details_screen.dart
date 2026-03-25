import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SchoolDetailsScreen extends StatelessWidget {
  final String schoolId;

  const SchoolDetailsScreen({super.key, required this.schoolId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('School Details')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schools')
            .doc(schoolId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('School not found'));
          }
          final school = snapshot.data!.data() as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Name: ${school['name']}',
                  style: const TextStyle(fontSize: 20),
                ),
                Text('ID: $schoolId'),
                Text('Admin: ${school['admin_username']}'),
                Text('Status: ${school['status']}'),
                Text(
                  'Last Updated: ${school['last_updated']?.toDate().toString() ?? 'N/A'}',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
