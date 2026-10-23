import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import 'package:universal_html/html.dart' as html;
import 'package:flutter/foundation.dart' show kIsWeb;

class AdminAddUsersScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;

  const AdminAddUsersScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
  });

  @override
  State<AdminAddUsersScreen> createState() => _AdminAddUsersScreenState();
}

class _AdminAddUsersScreenState extends State<AdminAddUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _selectedRole;
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _subjectController = TextEditingController();
  final _classTeacherForController = TextEditingController();
  String? _selectedClassName;
  String? _selectedSection;
  final _rollNumberController = TextEditingController();
  final _parentNameController = TextEditingController();
  final _parentMobileController = TextEditingController();
  final _mobileController = TextEditingController();
  final _alternateMobileController = TextEditingController();
  final _schoolTelephoneController = TextEditingController();
  final _gmailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _status = 'active';
  PlatformFile? _selectedFile;
  String? _errorMessage;
  bool _isLoading = false;
  int _successCount = 0;
  int _errorCount = 0;
  List<Map<String, dynamic>> _processingResults = [];

  // New state variables for bulk upload preview
  List<Map<String, dynamic>> _validUsersForBulk = [];
  List<Map<String, dynamic>> _bulkValidationErrors = [];
  bool _showBulkPreview = false;
  bool _isCreatingBulkUsers = false;

  // For class data
  List<String> _availableGrades = [];
  Map<String, List<String>> _gradeSections = {};
  bool _isLoadingClasses = false;

  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Responsive breakpoints
  static const double mobileBreakpoint = 600;
  static const double tabletBreakpoint = 1200;

  bool get _isMobile => MediaQuery.of(context).size.width < mobileBreakpoint;
  bool get _isTablet =>
      MediaQuery.of(context).size.width >= mobileBreakpoint &&
      MediaQuery.of(context).size.width < tabletBreakpoint;
  bool get _isDesktop => MediaQuery.of(context).size.width >= tabletBreakpoint;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAvailableClasses();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    _studentIdController.dispose();
    _subjectController.dispose();
    _classTeacherForController.dispose();
    _rollNumberController.dispose();
    _parentNameController.dispose();
    _parentMobileController.dispose();
    _mobileController.dispose();
    _alternateMobileController.dispose();
    _schoolTelephoneController.dispose();
    _gmailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableClasses() async {
    setState(() {
      _isLoadingClasses = true;
    });

    try {
      final classesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      final grades = <String>{};
      final gradeSections = <String, List<String>>{};

      for (final doc in classesSnapshot.docs) {
        final data = doc.data();
        final grade = data['grade']?.toString() ?? '';
        final sections = data['sections'];

        if (grade.isNotEmpty) {
          grades.add(grade);

          final sectionList = <String>[];
          if (sections is List) {
            for (final section in sections) {
              final sectionStr = section.toString().trim();
              if (sectionStr.isNotEmpty) {
                sectionList.add(sectionStr);
              }
            }
          } else if (sections is String && sections.isNotEmpty) {
            final sectionSplit = sections
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
            sectionList.addAll(sectionSplit);
          }

          // FIXED: Store all sections for each grade
          if (gradeSections.containsKey(grade)) {
            // Merge sections if grade already exists
            final existingSections = gradeSections[grade]!;
            final allSections = {...existingSections, ...sectionList}.toList();
            gradeSections[grade] = allSections;
          } else {
            gradeSections[grade] = sectionList;
          }
        }
      }

      setState(() {
        _availableGrades = grades.toList()..sort();
        _gradeSections = gradeSections;
        _isLoadingClasses = false;
      });

      print('Loaded classes: $_availableGrades');
      print('Grade sections: $_gradeSections');
    } catch (e) {
      print('Error loading classes: $e');
      setState(() {
        _isLoadingClasses = false;
      });
    }
  }

  Future<void> _downloadExcelTemplate() async {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a role (Teacher, Student, or Driver) first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Create a new workbook
      final xlsio.Workbook workbook = xlsio.Workbook();

      // Access the default worksheet
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Template';

      if (_selectedRole == 'teacher') {
        _createTeacherTemplateWithValidation(workbook, sheet);
      } else {
        _createStudentTemplateWithValidation(workbook, sheet);
      }

      // Save the workbook
      final List<int> bytes = workbook.saveAsStream();
      workbook.dispose();

      final fileName =
          '${_selectedRole}_template_${widget.schoolCode}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      if (kIsWeb) {
        // For web platform
        _downloadForWeb(bytes, fileName);
      } else {
        // For mobile platforms
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        await OpenFile.open(filePath);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_selectedRole == 'teacher' ? 'Teacher' : 'Student'} template downloaded successfully!',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      print('Error creating template: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error downloading template: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _createTeacherTemplateWithValidation(
    xlsio.Workbook workbook,
    xlsio.Worksheet sheet,
  ) {
    // Set headers
    final headers = [
      'username*',
      'role*',
      'password*',
      'full_name*',
      'mobile_number',
      'gmail',
      'status*',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
    }

    // Add data validation for role column (column B)
    final xlsio.DataValidation roleValidation = sheet
        .getRangeByName('B2:B100')
        .dataValidation;
    roleValidation.listOfValues = ['teacher'];
    roleValidation.showErrorBox = true;
    roleValidation.errorBoxText = 'Please select "teacher" from the dropdown';
    roleValidation.promptBoxText = 'Select role from dropdown list';

    // Add data validation for status column (column G)
    final xlsio.DataValidation statusValidation = sheet
        .getRangeByName('G2:G100')
        .dataValidation;
    statusValidation.listOfValues = ['active', 'inactive'];
    statusValidation.showErrorBox = true;
    statusValidation.errorBoxText =
        'Please select "active" or "inactive" from the dropdown';
    statusValidation.promptBoxText = 'Select status from dropdown list';
  }

  void _createStudentTemplateWithValidation(
    xlsio.Workbook workbook,
    xlsio.Worksheet sheet,
  ) {
    // Set headers
    final headers = [
      'username*',
      'role*',
      'password*',
      'full_name*',
      'class_name*',
      'section*',
      'roll_number',
      'parent_guardian_name',
      'parent_guardian_mobile',
      'mobile_number',
      'gmail',
      'status*',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
    }

    // Add data validation for role column (column B)
    final xlsio.DataValidation roleValidation = sheet
        .getRangeByName('B2:B100')
        .dataValidation;
    roleValidation.listOfValues = ['student'];
    roleValidation.showErrorBox = true;
    roleValidation.errorBoxText = 'Please select "student" from the dropdown';
    roleValidation.promptBoxText = 'Select role from dropdown list';

    // Add data validation for class_name column (column E)
    if (_availableGrades.isNotEmpty) {
      final xlsio.DataValidation classValidation = sheet
          .getRangeByName('E2:E100')
          .dataValidation;
      classValidation.listOfValues = _availableGrades;
      classValidation.showErrorBox = true;
      classValidation.errorBoxText =
          'Please select a valid class from the dropdown';
      classValidation.promptBoxText = 'Select class from dropdown list';
    }

    // FIXED: Create dropdown for sections with all available sections
    // Get all unique sections across all classes
    final allSections = <String>{};
    for (final sections in _gradeSections.values) {
      allSections.addAll(sections);
    }
    final sortedSections = allSections.toList()..sort();

    if (sortedSections.isNotEmpty) {
      final xlsio.DataValidation sectionValidation = sheet
          .getRangeByName('F2:F100')
          .dataValidation;
      sectionValidation.listOfValues = sortedSections;
      sectionValidation.showErrorBox = true;
      sectionValidation.errorBoxText =
          'Please select a valid section from the dropdown';
      sectionValidation.promptBoxText = 'Select section from dropdown list';
    }

    // Add data validation for status column (column L)
    final xlsio.DataValidation statusValidation = sheet
        .getRangeByName('L2:L100')
        .dataValidation;
    statusValidation.listOfValues = ['active', 'inactive'];
    statusValidation.showErrorBox = true;
    statusValidation.errorBoxText =
        'Please select "active" or "inactive" from the dropdown';
    statusValidation.promptBoxText = 'Select status from dropdown list';

    // FIXED: Remove sample data row - template should be empty
    // Only headers, no sample data

    // Add instructions note
    final instructions = [
      'INSTRUCTIONS:',
      '1. Fill data starting from row 2',
      '2. Class name must match exactly from dropdown',
      '3. Section must match exactly from dropdown',
      '4. Required fields are marked with *',
      '5. For students: class_name and section are required',
      '6. Password must be at least 6 characters',
      '7. IMPORTANT: Ensure the section you select is available for the chosen class',
    ];

    final instructionsSheet = workbook.worksheets.add();
    instructionsSheet.name = 'Instructions';

    for (int i = 0; i < instructions.length; i++) {
      instructionsSheet.getRangeByIndex(i + 1, 1).setText(instructions[i]);
    }

    // Add available classes and sections reference
    if (_availableGrades.isNotEmpty) {
      instructionsSheet
          .getRangeByIndex(instructions.length + 2, 1)
          .setText('AVAILABLE CLASSES AND SECTIONS:');
      int row = instructions.length + 3;

      for (final grade in _availableGrades) {
        final sections = _gradeSections[grade] ?? [];
        instructionsSheet.getRangeByIndex(row, 1).setText('Grade $grade:');
        instructionsSheet.getRangeByIndex(row, 2).setText(sections.join(', '));
        row++;
      }
    }
  }

  void _downloadForWeb(List<int> bytes, String fileName) {
    try {
      // Convert bytes to base64
      final base64 = base64Encode(bytes);
      // Create download link
      final anchor =
          html.AnchorElement(
              href:
                  'data:application/vnd.openxmlformats-officedocument.spreadsheetml.sheet;base64,$base64',
            )
            ..download = fileName
            ..style.display = 'none';

      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
    } catch (e) {
      print('Error in web download: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Please right-click and "Save link as" to download the template',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _createUser() async {
    if (_selectedRole == null) {
      setState(() {
        _errorMessage = 'Please select a role (Teacher, Student, or Driver)';
      });
      return;
    }

    String username;
    if (_selectedRole == 'student') {
      username = _studentIdController.text.trim();
    } else {
      // Both teacher and driver use the username field
      username = _usernameController.text.trim();
    }

    final password = _passwordController.text.trim();
    final fullName = _fullNameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'ID/Username is required';
      });
      return;
    }
    if (fullName.isEmpty) {
      setState(() {
        _errorMessage = 'Full Name is required';
      });
      return;
    }
    if (password.isEmpty || password.length < 6) {
      setState(() {
        _errorMessage = 'Password must be at least 6 characters';
      });
      return;
    }

    // Additional validation for students
    if (_selectedRole == 'student') {
      if (_selectedClassName == null || _selectedClassName!.isEmpty) {
        setState(() {
          _errorMessage = 'Class Name is required for students';
        });
        return;
      }
      if (_selectedSection == null || _selectedSection!.isEmpty) {
        setState(() {
          _errorMessage = 'Section is required for students';
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      Map<String, dynamic> userData = {
        'username': username,
        'role': _selectedRole,
        'schoolCode': widget.schoolCode,
        'password': password,
        'status': _status,
        'full_name': fullName,
      };

      _addOptionalField(userData, _mobileController.text, 'mobile_number');
      _addOptionalField(userData, _gmailController.text, 'gmail');

      if (_selectedRole == 'teacher') {
        _addOptionalField(userData, _subjectController.text, 'subject');
        _addOptionalField(
          userData,
          _classTeacherForController.text,
          'class_teacher_for',
        );
      } else if (_selectedRole == 'student') {
        final className = _selectedClassName!;
        final section = _selectedSection!;

        // CRITICAL FIX: Send raw class name without "Grade" prefix
        // The Cloud Function will handle adding the prefix and finding class_id
        userData['class_name'] = className; // Send without "Grade" prefix
        userData['section'] = section;

        // Don't try to find class_id locally - let Cloud Function handle it
        userData['class_id'] = ''; // Cloud Function will find and set this

        print('📝 Sending student data to Cloud Function:');
        print('Class Name (raw): $className');
        print('Section: $section');
        print('Class ID: Will be found by Cloud Function');
      }

      // CRITICAL FIX: Add ALL optional fields to ensure they're included
      _addOptionalField(userData, _rollNumberController.text, 'roll_number');
      _addOptionalField(
        userData,
        _parentNameController.text,
        'parent_guardian_name',
      );
      _addOptionalField(
        userData,
        _parentMobileController.text,
        'parent_guardian_mobile',
      );
      _addOptionalField(
        userData,
        _alternateMobileController.text,
        'alternate_mobile_number',
      );
      _addOptionalField(
        userData,
        _schoolTelephoneController.text,
        'school_telephone_number',
      );

      // DEBUG: Print the final userData being sent to Cloud Function
      print('=== FINAL USER DATA BEING SENT TO CLOUD FUNCTION ===');
      print('Username: ${userData['username']}');
      print('Role: ${userData['role']}');
      print('Class Name: ${userData['class_name']}');
      print('Section: ${userData['section']}');
      print('Class ID: ${userData['class_id']}');
      print('School Code: ${userData['schoolCode']}');
      print('Full userData: $userData');
      print('====================================================');

      // Add debug logging before calling the Cloud Function
      print('Sending user data to Cloud Function:');
      print('Role: ${userData['role']}');
      print('Class Name: ${userData['class_name']}');
      print('Section: ${userData['section']}');
      print('Class ID: ${userData['class_id']}');

      final result = await _functions.httpsCallable('createUser').call({
        'userData': userData,
      });

      final response = result.data;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response['message']),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 5),
        ),
      );

      _clearFields();
    } catch (e) {
      print('❌ Error creating user: $e');

      String errorMessage = 'Error creating user';
      if (e is FirebaseFunctionsException) {
        errorMessage = e.message ?? 'Unknown error occurred';
        print('FirebaseFunctionsException details: ${e.details}');
        print('FirebaseFunctionsException code: ${e.code}');
      } else if (e.toString().contains('already-exists')) {
        errorMessage =
            'Username already exists. Please try a different username.';
      } else if (e.toString().contains('permission-denied')) {
        errorMessage =
            'Permission denied. You are not authorized to perform this action.';
      } else if (e.toString().contains('invalid-argument')) {
        errorMessage = 'Invalid input. Please check your data and try again.';
      } else {
        errorMessage = 'Error creating user: ${e.toString()}';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<DocumentSnapshot<Map<String, dynamic>>?> _findClassByGradeAndSection(
    String grade,
    String section,
  ) async {
    try {
      print('Searching for class with grade: "$grade" and section: "$section"');

      final classesSnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('classes')
          .get();

      if (classesSnapshot.docs.isEmpty) {
        print('No classes found for school: ${widget.schoolCode}');
        return null;
      }

      for (final doc in classesSnapshot.docs) {
        final data = doc.data();
        final docGrade = data['grade']?.toString()?.trim() ?? '';
        final sections = data['sections'];

        print(
          'Checking class ${doc.id}: grade="$docGrade", sections=$sections',
        );

        if (docGrade != grade) continue;

        // Check if section exists in this class
        bool found = false;
        if (sections is List) {
          for (final sec in sections) {
            if (sec.toString().trim() == section) {
              found = true;
              break;
            }
          }
        } else if (sections is String && sections.isNotEmpty) {
          final sectionList = sections
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty)
              .toList();
          if (sectionList.contains(section)) {
            found = true;
          }
        }

        if (found) {
          print(
            '✓ Found class match: $docGrade with section: $section, class_id: ${doc.id}',
          );
          return doc;
        }
      }

      print(
        '✗ No class found matching grade: "$grade" and section: "$section"',
      );
      return null;
    } catch (e) {
      print(
        'Error finding class for grade "$grade" and section "$section": $e',
      );
      return null;
    }
  }

  void _addOptionalField(
    Map<String, dynamic> data,
    String value,
    String fieldName,
  ) {
    final trimmedValue = value.trim();
    if (trimmedValue.isNotEmpty) {
      data[fieldName] = trimmedValue;
      print('✓ Added field $fieldName: $trimmedValue');
    }
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedFile = result.files.first;
          _errorMessage = null;
          _successCount = 0;
          _errorCount = 0;
          _processingResults.clear();
          _showBulkPreview = false;
          _validUsersForBulk.clear();
          _bulkValidationErrors.clear();
        });
      }
    } catch (e) {
      print('Error picking file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error picking file: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _validateBulkUsers() async {
    if (_selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a role (Teacher, Student, or Driver)'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a file first'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successCount = 0;
      _errorCount = 0;
      _processingResults.clear();
      _validUsersForBulk.clear();
      _bulkValidationErrors.clear();
      _showBulkPreview = false;
    });

    try {
      String fileContent = _selectedFile!.bytes != null
          ? utf8.decode(_selectedFile!.bytes!)
          : await File(_selectedFile!.path!).readAsString();

      final converter = CsvToListConverter(
        eol: '\n',
        shouldParseNumbers: false,
      );
      final List<List<dynamic>> csvRows = converter.convert(fileContent);

      if (csvRows.isEmpty) {
        throw Exception('CSV file is empty after processing');
      }

      if (csvRows.length < 2) {
        throw Exception(
          'CSV file must have at least a header row and one data row. Found ${csvRows.length} lines.',
        );
      }

      final headers = csvRows[0]
          .map((e) => e.toString().toLowerCase().trim().replaceAll('*', ''))
          .toList();
      final headerIndex = {
        for (var i = 0; i < headers.length; i++) headers[i]: i,
      };

      final List<Map<String, dynamic>> validUsers = [];
      final List<Map<String, dynamic>> validationErrors = [];

      // Step 1: Basic validation (field requirements) - FAST LOCAL VALIDATION
      for (int i = 1; i < csvRows.length; i++) {
        final row = csvRows[i];
        if (row.isEmpty || row.every((cell) => cell.toString().trim().isEmpty))
          continue;

        try {
          final username = _getFieldValue(row, headerIndex, 'username');
          final password = _getFieldValue(row, headerIndex, 'password');
          final role = _getFieldValue(row, headerIndex, 'role');
          final fullName = _getFieldValue(row, headerIndex, 'full_name');

          // Quick validation checks
          if (username.isEmpty) throw Exception('Username is required');
          if (password.isEmpty) throw Exception('Password is required');
          if (password.length < 6)
            throw Exception('Password must be at least 6 characters');
          if (fullName.isEmpty) throw Exception('Full Name is required');
          if (role != _selectedRole)
            throw Exception(
              'Role mismatch: expected $_selectedRole, found $role',
            );

          final userData = <String, dynamic>{
            'username': username,
            'role': role,
            'schoolCode': widget.schoolCode,
            'password': password,
            'full_name': fullName,
          };

          _addOptionalFieldFromCsv(userData, row, headerIndex, 'status');

          if (role == 'teacher') {
            _addOptionalFieldFromCsv(userData, row, headerIndex, 'subject');
            _addOptionalFieldFromCsv(
              userData,
              row,
              headerIndex,
              'class_teacher_for',
            );
            _addOptionalFieldFromCsv(
              userData,
              row,
              headerIndex,
              'mobile_number',
            );
            _addOptionalFieldFromCsv(userData, row, headerIndex, 'gmail');
          } else if (role == 'student') {
            final className = _getFieldValue(row, headerIndex, 'class_name');
            final section = _getFieldValue(row, headerIndex, 'section');

            if (className.isEmpty)
              throw Exception('Class name is required for students');
            if (section.isEmpty)
              throw Exception('Section is required for students');

            // Validate class name exists
            if (!_availableGrades.contains(className)) {
              throw Exception(
                'Class name "$className" is not available. Available classes: ${_availableGrades.join(', ')}',
              );
            }

            // Validate section exists for the class
            final availableSections = _gradeSections[className] ?? [];
            if (!availableSections.contains(section)) {
              throw Exception(
                'Section "$section" is not available for class "$className". Available sections: ${availableSections.join(', ') ?? "None"}',
              );
            }

            // CRITICAL FIX: Send raw class name - Cloud Function will handle prefix and class_id lookup
            userData['class_name'] = className; // No "Grade" prefix
            userData['section'] = section;
            userData['class_id'] = ''; // Cloud Function will find this

            print('📝 Bulk - Student data prepared:');
            print('Class Name (raw): $className');
            print('Section: $section');
            print('Class ID: Will be found by Cloud Function');

            _addOptionalFieldFromCsv(userData, row, headerIndex, 'roll_number');
            _addOptionalFieldFromCsv(
              userData,
              row,
              headerIndex,
              'parent_guardian_name',
            );
            _addOptionalFieldFromCsv(
              userData,
              row,
              headerIndex,
              'parent_guardian_mobile',
            );
            _addOptionalFieldFromCsv(
              userData,
              row,
              headerIndex,
              'mobile_number',
            );
            _addOptionalFieldFromCsv(userData, row, headerIndex, 'gmail');
          }

          if (!userData.containsKey('status') || userData['status'] == null) {
            userData['status'] = 'active';
          }

          validUsers.add(userData);
        } catch (e) {
          final username =
              _getFieldValue(row, headerIndex, 'username') ?? 'Unknown';
          validationErrors.add({
            'username': username,
            'status': 'error',
            'message': e.toString(),
          });
        }
      }

      if (validUsers.isEmpty && validationErrors.isEmpty) {
        throw Exception('No valid user data found in the CSV file');
      }

      // Step 2: OPTIMIZED - Check for existing users in database using batch query
      if (validUsers.isNotEmpty) {
        await _checkExistingUsersOptimized(validUsers, validationErrors);
      }

      setState(() {
        _validUsersForBulk = validUsers;
        _bulkValidationErrors = validationErrors;
        _showBulkPreview = true;
      });

      _showValidationPreviewDialog();
    } catch (e) {
      print('Error processing file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error processing file: ${e.toString()}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // OPTIMIZED: Check for existing users using batch queries
  Future<void> _checkExistingUsersOptimized(
    List<Map<String, dynamic>> validUsers,
    List<Map<String, dynamic>> validationErrors,
  ) async {
    try {
      // Show loading indicator for database check
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Quick checking for existing users...')),
            ],
          ),
          duration: Duration(seconds: 3),
        ),
      );

      // Get all usernames from valid users
      final usernames = validUsers
          .map((user) => user['username'] as String)
          .toList();

      // Split into batches of 30 (Firestore 'in' query limit is 30)
      const batchSize = 30;
      final batches = <List<String>>[];

      for (var i = 0; i < usernames.length; i += batchSize) {
        final end = (i + batchSize < usernames.length)
            ? i + batchSize
            : usernames.length;
        batches.add(usernames.sublist(i, end));
      }

      final existingUsernames = <String>{};

      // Process batches in parallel
      final batchFutures = batches.map((batch) async {
        final existingUsersQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('school_code', isEqualTo: widget.schoolCode)
            .where('role', isEqualTo: _selectedRole)
            .where('username', whereIn: batch)
            .get();

        return existingUsersQuery.docs
            .map((doc) {
              final userData = doc.data();
              return userData['username']?.toString().trim().toLowerCase() ??
                  '';
            })
            .where((username) => username.isNotEmpty);
      }).toList();

      // Wait for all batches to complete
      final batchResults = await Future.wait(batchFutures);

      // Combine all results
      for (final result in batchResults) {
        existingUsernames.addAll(result);
      }

      // Check each valid user against existing usernames
      final List<Map<String, dynamic>> uniqueUsers = [];

      for (var user in validUsers) {
        final username =
            user['username']?.toString().trim().toLowerCase() ?? '';

        if (existingUsernames.contains(username)) {
          // Move to validation errors
          validationErrors.add({
            'username': user['username'],
            'status': 'error',
            'message': 'Username already exists in the database',
          });
        } else {
          // Keep as valid user
          uniqueUsers.add(user);
        }
      }

      // Update the validUsers list to only include unique users
      validUsers.clear();
      validUsers.addAll(uniqueUsers);

      // Show result of duplicate check
      final duplicateCount = validationErrors
          .where(
            (error) =>
                error['message'] == 'Username already exists in the database',
          )
          .length;

      if (duplicateCount > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Found $duplicateCount duplicate users'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error checking existing users: $e');
      // If there's an error checking duplicates, we can still proceed but show a warning
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warning: Could not check for existing users. Some users might already exist. Error: ${e.toString()}',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // New method to check for existing users in Firestore
  Future<void> _checkExistingUsers(
    List<Map<String, dynamic>> validUsers,
    List<Map<String, dynamic>> validationErrors,
  ) async {
    try {
      // Show loading indicator for database check
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Checking for existing users in database...')),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      // Get all existing usernames for this school and role
      final existingUsersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('school_code', isEqualTo: widget.schoolCode)
          .where('role', isEqualTo: _selectedRole)
          .get();

      final existingUsernames = <String>{};
      for (var doc in existingUsersQuery.docs) {
        final userData = doc.data();
        final username = userData['username']?.toString().trim();
        if (username != null && username.isNotEmpty) {
          existingUsernames.add(username.toLowerCase());
        }
      }

      // Check each valid user against existing usernames
      final List<Map<String, dynamic>> uniqueUsers = [];

      for (var user in validUsers) {
        final username =
            user['username']?.toString().trim().toLowerCase() ?? '';

        if (existingUsernames.contains(username)) {
          // Move to validation errors
          validationErrors.add({
            'username': user['username'],
            'status': 'error',
            'message': 'Username already exists in the database',
          });
        } else {
          // Keep as valid user
          uniqueUsers.add(user);
        }
      }

      // Update the validUsers list to only include unique users
      validUsers.clear();
      validUsers.addAll(uniqueUsers);

      // Show result of duplicate check
      if (validationErrors.any(
        (error) =>
            error['message'] == 'Username already exists in the database',
      )) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found ${validationErrors.where((error) => error['message'] == 'Username already exists in the database').length} duplicate users',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error checking existing users: $e');
      // If there's an error checking duplicates, we can still proceed but show a warning
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Warning: Could not check for existing users. Some users might already exist. Error: ${e.toString()}',
          ),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _createBulkUsers([StateSetter? setDialogState]) async {
    if (setDialogState != null) {
      setDialogState(() {
        _isCreatingBulkUsers = true;
      });
    } else {
      setState(() {
        _isCreatingBulkUsers = true;
      });
    }

    try {
      // OPTIMIZED: Use larger batch sizes and longer timeout
      const batchSize = 100; // Increased batch size
      final batches = <List<Map<String, dynamic>>>[];

      for (var i = 0; i < _validUsersForBulk.length; i += batchSize) {
        final end = (i + batchSize < _validUsersForBulk.length)
            ? i + batchSize
            : _validUsersForBulk.length;
        batches.add(_validUsersForBulk.sublist(i, end));
      }

      // Reset counters
      _successCount = 0;
      _errorCount = 0;
      _processingResults.clear();

      print(
        '🔄 Processing ${_validUsersForBulk.length} users in ${batches.length} batches of $batchSize',
      );

      // Track processed usernames to avoid duplicates
      final processedUsernames = <String>{};
      final List<Map<String, dynamic>> allBatchResults = [];

      // Process each batch sequentially
      for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];
        final batchNumber = batchIndex + 1;

        print(
          '📦 Processing batch $batchNumber/${batches.length} with ${batch.length} users',
        );

        // Check for duplicates in current batch
        final currentBatchUsernames = <String>{};
        for (final user in batch) {
          final username = user['username'] as String;
          if (currentBatchUsernames.contains(username)) {
            print('⚠️ Duplicate username in same batch: $username');
          }
          currentBatchUsernames.add(username);
        }

        // Check for duplicates across batches
        final batchToProcess = <Map<String, dynamic>>[];
        for (final user in batch) {
          final username = user['username'] as String;
          if (processedUsernames.contains(username)) {
            print('⚠️ Duplicate username across batches: $username');
          } else {
            processedUsernames.add(username);
            batchToProcess.add(user);
          }
        }

        // Update progress in dialog
        if (setDialogState != null) {
          setDialogState(() {});
        }

        // Skip empty batches (if all were duplicates)
        if (batchToProcess.isEmpty) {
          print('⏭️ Skipping empty batch $batchNumber');
          continue;
        }

        // OPTIMIZED: Create callable with longer timeout for larger batches
        final callable = _functions.httpsCallable(
          'createUsersBulk',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 300), // 5 minutes per batch
          ),
        );

        final result = await callable.call({'users': batchToProcess});

        // CRITICAL FIX: Convert the ENTIRE response at the top level
        final response = Map<String, dynamic>.from(
          result.data,
        ); // <-- THIS IS THE FIX
        final batchResults = (response['results'] as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        // Store all results for final processing
        allBatchResults.addAll(batchResults.cast<Map<String, dynamic>>());

        // Process batch results immediately for progress updates
        int batchSuccess = 0;
        int batchError = 0;

        for (final result in batchResults) {
          final resultMap = Map<String, dynamic>.from(result);
          if (resultMap['success'] == true) {
            batchSuccess++;
          } else {
            batchError++;
          }
        }

        // Update main counters
        _successCount += batchSuccess;
        _errorCount += batchError;

        print(
          '📊 Batch $batchNumber results: $batchSuccess success, $batchError errors',
        );

        // OPTIMIZED: Smaller delay between batches
        if (batchIndex < batches.length - 1) {
          print('⏳ Waiting 2 seconds before next batch...');
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      // Final processing of all results with accurate counts
      _successCount = 0;
      _errorCount = 0;
      _processingResults.clear();

      for (final result in allBatchResults) {
        final resultMap = result as Map<String, dynamic>;

        if (resultMap['success'] == true) {
          _successCount++;
          _processingResults.add({
            'username': resultMap['username'],
            'status': 'success',
            'message': 'User created successfully',
          });
        } else {
          _errorCount++;
          _processingResults.add({
            'username': resultMap['username'],
            'status': 'error',
            'message': resultMap['error'],
          });
        }

        // Update progress in dialog
        if (setDialogState != null) {
          setDialogState(() {});
        }
      }

      // Show final results
      if (mounted) {
        Navigator.pop(context); // Close the progress dialog
        _showFinalResultsDialog();
      }

      print('🎉 Final results: $_successCount success, $_errorCount errors');
    } on FirebaseFunctionsException catch (e) {
      print('Firebase Functions Error creating bulk users: $e');
      print('Error code: ${e.code}');
      print('Error details: ${e.details}');
      print('Error message: ${e.message}');

      if (mounted) {
        Navigator.pop(context);

        String errorMessage = 'Error creating users';
        if (e.code == 'deadline-exceeded') {
          errorMessage =
              'Batch processing timed out. Some users were created. Please check the results.';
        } else {
          errorMessage = 'Error: ${e.message ?? e.toString()}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      print('Error creating bulk users: $e');
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating users: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingBulkUsers = false;
          _validUsersForBulk.clear();
          _bulkValidationErrors.clear();
        });
      }
    }
  }

  void _showValidationPreviewDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 600;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Calculate batch progress here, outside the widget tree
          final totalBatches = (_validUsersForBulk.length / 50).ceil();
          final currentBatch = (_successCount / 50).floor() + 1;

          return Dialog(
            insetPadding: EdgeInsets.all(isSmallScreen ? 16 : 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isSmallScreen ? screenWidth - 32 : 600,
                maxHeight: screenHeight * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isCreatingBulkUsers
                              ? Icons.hourglass_empty
                              : Icons.preview,
                          color: _isCreatingBulkUsers
                              ? Colors.orange
                              : Colors.blue,
                          size: isSmallScreen ? 20 : 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _isCreatingBulkUsers
                                ? 'Creating Users'
                                : 'Bulk Upload Preview',
                            style: TextStyle(
                              fontSize: isSmallScreen ? 18 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content - Scrollable
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!_isCreatingBulkUsers) ...[
                            // Validation Summary
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey[300]!),
                              ),
                              child: Column(
                                children: [
                                  _buildSummaryRow(
                                    'Valid users ready for creation:',
                                    _validUsersForBulk.length.toString(),
                                    Colors.green,
                                    Icons.check_circle,
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSummaryRow(
                                    'Invalid users (will be skipped):',
                                    _bulkValidationErrors.length.toString(),
                                    Colors.red,
                                    Icons.error,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),

                            if (_bulkValidationErrors.isNotEmpty) ...[
                              _buildSectionHeader('Validation Errors:'),
                              const SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: isSmallScreen ? 120 : 150,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _bulkValidationErrors.length,
                                  itemBuilder: (context, index) {
                                    final error = _bulkValidationErrors[index];
                                    final isDuplicate =
                                        error['message'] ==
                                        'Username already exists in the database';
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: index > 0
                                            ? Border(
                                                top: BorderSide(
                                                  color: Colors.grey[200]!,
                                                ),
                                              )
                                            : null,
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: isSmallScreen ? 12 : 16,
                                          vertical: 4,
                                        ),
                                        leading: Icon(
                                          isDuplicate
                                              ? Icons.person_off
                                              : Icons.error,
                                          color: isDuplicate
                                              ? Colors.orange
                                              : Colors.red,
                                          size: 18,
                                        ),
                                        title: Text(
                                          error['username'],
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 13 : 14,
                                            color: isDuplicate
                                                ? Colors.orange
                                                : Colors.red,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          error['message'],
                                          style: TextStyle(
                                            color: isDuplicate
                                                ? Colors.orange
                                                : Colors.red,
                                            fontSize: isSmallScreen ? 11 : 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            if (_validUsersForBulk.isNotEmpty) ...[
                              _buildSectionHeader('Valid Users (Preview):'),
                              const SizedBox(height: 8),
                              Container(
                                constraints: BoxConstraints(
                                  maxHeight: isSmallScreen ? 120 : 150,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.grey[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _validUsersForBulk.length,
                                  itemBuilder: (context, index) {
                                    final user = _validUsersForBulk[index];
                                    return Container(
                                      decoration: BoxDecoration(
                                        border: index > 0
                                            ? Border(
                                                top: BorderSide(
                                                  color: Colors.grey[200]!,
                                                ),
                                              )
                                            : null,
                                      ),
                                      child: ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: isSmallScreen ? 12 : 16,
                                          vertical: 4,
                                        ),
                                        leading: const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 18,
                                        ),
                                        title: Text(
                                          user['username'],
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 13 : 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${user['full_name']} - ${user['role']}${user['class_name'] != null ? ' (${user['class_name']}${user['section'] != null ? ' - ${user['section']}' : ''})' : ''}',
                                          style: TextStyle(
                                            fontSize: isSmallScreen ? 11 : 12,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ] else ...[
                            // Loading Progress UI with Batch Tracking
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    SizedBox(
                                      width: isSmallScreen ? 60 : 80,
                                      height: isSmallScreen ? 60 : 80,
                                      child: CircularProgressIndicator(
                                        value:
                                            _successCount /
                                            _validUsersForBulk.length,
                                        strokeWidth: isSmallScreen ? 6 : 8,
                                        backgroundColor: Colors.grey[300],
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              Colors.green,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      '${((_successCount / _validUsersForBulk.length) * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: isSmallScreen ? 14 : 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Creating Users...',
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 16 : 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                // Batch Progress Section - Now using pre-calculated variables
                                if (_validUsersForBulk.length > 50) ...[
                                  Text(
                                    'Processing batch $currentBatch of $totalBatches',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 14 : 16,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.blue,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                Text(
                                  '$_successCount of ${_validUsersForBulk.length} users created',
                                  style: TextStyle(
                                    fontSize: isSmallScreen ? 13 : 14,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                LinearProgressIndicator(
                                  value:
                                      _successCount / _validUsersForBulk.length,
                                  backgroundColor: Colors.grey[300],
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.green,
                                      ),
                                  minHeight: isSmallScreen ? 4 : 6,
                                ),
                                const SizedBox(height: 12),

                                // Additional info for large operations
                                if (_validUsersForBulk.length > 100) ...[
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange[50],
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.orange[200]!,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.info,
                                          color: Colors.orange[800],
                                          size: isSmallScreen ? 16 : 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            'Large operation - processing in batches for reliability',
                                            style: TextStyle(
                                              fontSize: isSmallScreen ? 11 : 12,
                                              color: Colors.orange[800],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],

                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isSmallScreen ? 8 : 16,
                                  ),
                                  child: Text(
                                    'Please wait while users are being added to Firebase...',
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 11 : 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Actions
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      border: Border(top: BorderSide(color: Colors.grey[300]!)),
                    ),
                    child: Row(
                      children: [
                        if (!_isCreatingBulkUsers) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                setState(() {
                                  _showBulkPreview = false;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 10 : 12,
                                ),
                              ),
                              child: Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 16,
                                ),
                              ),
                            ),
                          ),
                          if (_validUsersForBulk.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isCreatingBulkUsers
                                    ? null
                                    : () async {
                                        setDialogState(() {});
                                        await _createBulkUsers(setDialogState);
                                      },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  padding: EdgeInsets.symmetric(
                                    vertical: isSmallScreen ? 10 : 12,
                                  ),
                                ),
                                child: _isCreatingBulkUsers
                                    ? SizedBox(
                                        width: isSmallScreen ? 16 : 20,
                                        height: isSmallScreen ? 16 : 20,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.white,
                                              ),
                                        ),
                                      )
                                    : Text(
                                        'Continue & Create',
                                        style: TextStyle(
                                          fontSize: isSmallScreen ? 14 : 16,
                                          color: Colors.white,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ] else ...[
                          Expanded(
                            child: ElevatedButton(
                              onPressed: null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.grey,
                                padding: EdgeInsets.symmetric(
                                  vertical: isSmallScreen ? 10 : 12,
                                ),
                              ),
                              child: Text(
                                'Creating Users...',
                                style: TextStyle(
                                  fontSize: isSmallScreen ? 14 : 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showFinalResultsDialog() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isSmallScreen = screenWidth < 600;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.all(isSmallScreen ? 16 : 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isSmallScreen ? screenWidth - 32 : 600,
            maxHeight: screenHeight * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border(bottom: BorderSide(color: Colors.green[300]!)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_done,
                      color: Colors.green,
                      size: isSmallScreen ? 20 : 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Bulk Upload Complete',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Content - Scrollable
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Results Summary
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          children: [
                            _buildSummaryRow(
                              'Successfully created:',
                              '$_successCount users',
                              Colors.green,
                              Icons.check_circle,
                            ),
                            const SizedBox(height: 8),
                            _buildSummaryRow(
                              'Failed:',
                              '$_errorCount users',
                              Colors.red,
                              Icons.error,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (_processingResults.isNotEmpty) ...[
                        _buildSectionHeader('Detailed Results:'),
                        const SizedBox(height: 8),
                        Container(
                          constraints: BoxConstraints(
                            maxHeight: isSmallScreen ? 150 : 200,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: _processingResults.length,
                            itemBuilder: (context, index) {
                              final result = _processingResults[index];
                              return Container(
                                decoration: BoxDecoration(
                                  border: index > 0
                                      ? Border(
                                          top: BorderSide(
                                            color: Colors.grey[200]!,
                                          ),
                                        )
                                      : null,
                                ),
                                child: ListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: isSmallScreen ? 12 : 16,
                                    vertical: 4,
                                  ),
                                  leading: Icon(
                                    result['status'] == 'success'
                                        ? Icons.check_circle
                                        : Icons.error,
                                    color: result['status'] == 'success'
                                        ? Colors.green
                                        : Colors.red,
                                    size: 18,
                                  ),
                                  title: Text(
                                    result['username'],
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 13 : 14,
                                      fontWeight: FontWeight.w500,
                                      color: result['status'] == 'success'
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  subtitle: Text(
                                    result['message'],
                                    style: TextStyle(
                                      color: result['status'] == 'success'
                                          ? Colors.green
                                          : Colors.red,
                                      fontSize: isSmallScreen ? 11 : 12,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Actions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _selectedFile = null;
                        _validUsersForBulk.clear();
                        _bulkValidationErrors.clear();
                        _showBulkPreview = false;
                        _processingResults.clear();
                        _successCount = 0;
                        _errorCount = 0;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(
                        vertical: isSmallScreen ? 12 : 14,
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        fontSize: isSmallScreen ? 16 : 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Row(
      children: [
        Icon(icon, color: color, size: isSmallScreen ? 18 : 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isSmallScreen ? 14 : 16,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isSmallScreen ? 14 : 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final isSmallScreen = MediaQuery.of(context).size.width < 600;

    return Text(
      title,
      style: TextStyle(
        fontSize: isSmallScreen ? 16 : 18,
        fontWeight: FontWeight.bold,
        color: Colors.blue[800],
      ),
    );
  }

  String _getFieldValue(
    List<dynamic> row,
    Map<String, int> headerIndex,
    String fieldName,
  ) {
    final fieldIndex = headerIndex[fieldName];
    if (fieldIndex != null && fieldIndex >= 0 && row.length > fieldIndex) {
      return row[fieldIndex].toString().trim();
    }
    return '';
  }

  void _addOptionalFieldFromCsv(
    Map<String, dynamic> userData,
    List<dynamic> row,
    Map<String, int> headerIndex,
    String fieldName,
  ) {
    final value = _getFieldValue(row, headerIndex, fieldName);
    if (value.isNotEmpty) {
      userData[fieldName] = value;
    }
  }

  void _clearFields() {
    _usernameController.clear();
    _fullNameController.clear();
    _studentIdController.clear();
    _subjectController.clear();
    _classTeacherForController.clear();
    _rollNumberController.clear();
    _parentNameController.clear();
    _parentMobileController.clear();
    _mobileController.clear();
    _alternateMobileController.clear();
    _schoolTelephoneController.clear();
    _gmailController.clear();
    _passwordController.clear();
    setState(() {
      _selectedRole = null;
      _selectedClassName = null;
      _selectedSection = null;
      _status = 'active';
      _errorMessage = null;
    });
  }

  Widget _buildTemplateDownloadSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.download,
              size: 48,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
            const SizedBox(height: 16),
            const Text(
              'Download Excel Template',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Get a clean Excel template with required columns. Fill only the data rows starting from row 2.',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (_isLoadingClasses) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text(
                'Loading available classes...',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ] else ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _downloadExcelTemplate,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(
                    _isLoading
                        ? 'Preparing Template...'
                        : 'Download ${_selectedRole == 'teacher' ? 'Teacher' : 'Student'} Template',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (_selectedRole == 'student' && _availableGrades.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[100]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Available Classes (use exact format):',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _availableGrades.join(', '),
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                    if (_gradeSections.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Available Sections by Class:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ..._gradeSections.entries.map((entry) {
                        return Text(
                          '${entry.key}: ${entry.value.join(', ')}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.blue,
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isDesktop ? null : _buildAppBar(),
      body: _isDesktop ? _buildDesktopLayout() : _buildMobileTabletLayout(),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text('Add Users - ${widget.schoolName}'),
      backgroundColor: Colors.white,
      foregroundColor: const Color.fromARGB(255, 21, 101, 192),
      elevation: 0,
      bottom: TabBar(
        controller: _tabController,
        labelColor: const Color.fromARGB(255, 21, 101, 192),
        unselectedLabelColor: Colors.grey,
        tabs: const [
          Tab(text: 'Single User'),
          Tab(text: 'Bulk Upload'),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        // Sidebar
        _buildDesktopSidebar(),
        // Main Content
        Expanded(
          child: Column(
            children: [
              _buildDesktopTopBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildSingleUserTab(), _buildBulkUploadTab()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopSidebar() {
    return Container(
      width: 260,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.blue[100],
                    child: const Icon(
                      Icons.person_add,
                      size: 40,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Add Users',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color.fromARGB(255, 21, 101, 192),
                    ),
                  ),
                  Text(
                    widget.schoolName,
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _buildSidebarItem(Icons.person_add, 'Single User', 0),
                  _buildSidebarItem(Icons.upload_file, 'Bulk Upload', 1),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebarItem(IconData icon, String title, int index) {
    final isSelected = _tabController.index == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? Colors.blue[700] : Colors.grey),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.blue[700] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.bold : null,
        ),
      ),
      selected: isSelected,
      onTap: () => _tabController.animateTo(index),
    );
  }

  Widget _buildDesktopTopBar() {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: Colors.white,
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(
              Icons.arrow_back,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
            onPressed: () {
              Navigator.of(context).pop();
            },
            tooltip: 'Back to Dashboard',
          ),
          Text(
            _tabController.index == 0 ? 'Add Single User' : 'Bulk Upload Users',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_selectedRole != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Adding ${_selectedRole!.toUpperCase()}S',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildMobileTabletLayout() {
    return Column(
      children: [
        if (_isTablet) _buildTabletTopBar(),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [_buildSingleUserTab(), _buildBulkUploadTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildTabletTopBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          Text(
            'Add Users - ${widget.schoolName}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromARGB(255, 21, 101, 192),
            ),
          ),
          const Spacer(),
          if (_selectedRole != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'Adding ${_selectedRole!.toUpperCase()}S',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSingleUserTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isDesktop) ...[
            Text(
              'Add Single User',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedRole == null) ...[
            _buildRoleSelection(),
          ] else ...[
            _buildUserForm(),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.person_add,
                  size: 64,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select User Type to Add',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose whether you want to add a teacher, student, or driver',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _buildRoleCard(
                        'Teacher',
                        Icons.school,
                        Colors.orange,
                        'Add teaching staff',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildRoleCard(
                        'Student',
                        Icons.person,
                        Colors.blue,
                        'Add students',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildRoleCard(
                        'Driver',
                        Icons.directions_bus,
                        Colors.green,
                        'Add bus drivers',
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

  Widget _buildRoleCard(
    String title,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedRole = title.toLowerCase();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            if (!_isDesktop) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedRole = null;
                  });
                },
              ),
            ],
            Expanded(
              child: Text(
                'Add ${_selectedRole!.toUpperCase()}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
              ),
            ),
            if (_isDesktop) ...[
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedRole = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Change Role'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // School Info Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.school, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.schoolName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text('School Code: ${widget.schoolCode}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Form Fields
        _buildFormFields(),

        // Error Message
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(_errorMessage!),
        ],

        // Action Buttons
        const SizedBox(height: 24),
        _buildActionButtons(),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      children: [
        // Username/ID Field
        TextField(
          controller: _selectedRole == 'student'
              ? _studentIdController
              : _usernameController,
          decoration: InputDecoration(
            labelText: _selectedRole == 'student'
                ? 'Student ID (Username) *'
                : _selectedRole == 'driver'
                    ? 'Driver ID (Username) *'
                    : 'Teacher ID (Username) *',
            hintText: 'Enter ID/Username',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.person),
          ),
        ),
        const SizedBox(height: 16),

        // Full Name Field (Now Required)
        TextField(
          controller: _fullNameController,
          decoration: const InputDecoration(
            labelText: 'Full Name *',
            hintText: 'Enter full name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.badge),
          ),
        ),
        const SizedBox(height: 16),

        // Password Field
        TextField(
          controller: _passwordController,
          decoration: const InputDecoration(
            labelText: 'Password *',
            hintText: 'Set a password (min 6 chars)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),

        // Common Optional Fields
        TextField(
          controller: _mobileController,
          decoration: const InputDecoration(
            labelText: 'Mobile Number (Optional)',
            hintText: 'Enter mobile number',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.phone),
          ),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _gmailController,
          decoration: const InputDecoration(
            labelText: 'Gmail (Optional)',
            hintText: 'Enter gmail address',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 16),

        // Role Specific Fields
        if (_selectedRole == 'teacher') ...[
          TextField(
            controller: _subjectController,
            decoration: const InputDecoration(
              labelText: 'Subject (Optional)',
              hintText: 'Enter subject taught',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.subject),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _classTeacherForController,
            decoration: const InputDecoration(
              labelText: 'Class Teacher For (Optional)',
              hintText: 'Enter class (e.g., 5A)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.class_),
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_selectedRole == 'student') ...[
          // Class Name Field with Dropdown for available grades
          DropdownButtonFormField<String>(
            value: _selectedClassName,
            decoration: const InputDecoration(
              labelText: 'Class Name *',
              hintText: 'Select class name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.school),
            ),
            items: _availableGrades.map((String value) {
              return DropdownMenuItem<String>(value: value, child: Text(value));
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                _selectedClassName = newValue;
                // Reset section when class name changes
                _selectedSection = null;
              });
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please select a class name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Section Field with Dropdown for available sections for selected class
          // FIXED: Show only available sections for the selected class
          if (_selectedClassName != null &&
              _gradeSections.containsKey(_selectedClassName))
            DropdownButtonFormField<String>(
              value: _selectedSection,
              decoration: const InputDecoration(
                labelText: 'Section *',
                hintText: 'Select section',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _gradeSections[_selectedClassName]!.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  _selectedSection = newValue;
                });
              },
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a section';
                }
                return null;
              },
            ),
          const SizedBox(height: 16),

          TextField(
            controller: _rollNumberController,
            decoration: const InputDecoration(
              labelText: 'Roll Number (Optional)',
              hintText: 'Enter roll number',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.format_list_numbered),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _parentNameController,
            decoration: const InputDecoration(
              labelText: 'Parent/Guardian Name (Optional)',
              hintText: 'Enter parent/guardian name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.family_restroom),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _parentMobileController,
            decoration: const InputDecoration(
              labelText: 'Parent/Guardian Mobile (Optional)',
              hintText: 'Enter parent/guardian mobile',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_android),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
        ],

        // Status Field
        DropdownButtonFormField<String>(
          value: _status,
          decoration: const InputDecoration(
            labelText: 'Status',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.star_rate),
          ),
          items: ['active', 'inactive'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value[0].toUpperCase() + value.substring(1)),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() {
              _status = newValue;
            });
          },
        ),
      ],
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[100]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        if (!_isDesktop) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedRole = null;
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Change Role'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createUser,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 21, 101, 192),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create User',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ] else ...[
          const Expanded(flex: 2, child: SizedBox()),
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedRole = null;
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Change Role'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _createUser,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 21, 101, 192),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Create User',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBulkUploadTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: _isDesktop ? 32 : 16,
        vertical: _isDesktop ? 24 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isDesktop) ...[
            Text(
              'Bulk Upload Users',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color.fromARGB(255, 21, 101, 192),
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (_selectedRole == null) ...[
            _buildBulkRoleSelection(),
          ] else ...[
            _buildBulkUploadForm(),
          ],
        ],
      ),
    );
  }

  Widget _buildBulkRoleSelection() {
    return Column(
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Icon(
                  Icons.upload_file,
                  size: 64,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Select User Type to Upload',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color.fromARGB(255, 21, 101, 192),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose whether you want to upload teachers or students in bulk',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _buildBulkRoleCard(
                        'Teacher',
                        Icons.upload_file,
                        Colors.orange,
                        'Upload multiple teachers',
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBulkRoleCard(
                        'Student',
                        Icons.upload_file,
                        Colors.blue,
                        'Upload multiple students',
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

  Widget _buildBulkRoleCard(
    String title,
    IconData icon,
    Color color,
    String subtitle,
  ) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedRole = title.toLowerCase();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 32, color: color),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBulkUploadForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with back button
        Row(
          children: [
            if (!_isDesktop) ...[
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _selectedRole = null;
                  });
                },
              ),
            ],
            Expanded(
              child: Text(
                'Upload ${_selectedRole!.toUpperCase()}S',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 21, 101, 192),
                ),
              ),
            ),
            if (_isDesktop) ...[
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedRole = null;
                  });
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('Change Role'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        // School Info Card
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.school, color: Colors.blue[700]),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.schoolName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text('School Code: ${widget.schoolCode}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Template Download Section
        _buildTemplateDownloadSection(),
        const SizedBox(height: 24),

        // File Upload Section
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_upload,
                  size: 64,
                  color: _selectedFile != null ? Colors.blue : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  _selectedFile?.name ?? 'No file selected',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _selectedFile != null ? Colors.blue : Colors.grey,
                  ),
                ),
                if (_selectedFile != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Size: ${(_selectedFile!.size / 1024).toStringAsFixed(1)} KB',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Select CSV File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 255, 255, 255),
                  ),
                ),
              ],
            ),
          ),
        ),

        // CSV Format Example
        const SizedBox(height: 24),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Template Includes:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                const Text(
                  '• Pre-filled headers with required fields marked (*)',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• Clean format with no sample data',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  '• Role must be exactly "${_selectedRole}"',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• Status values must be "active" or "inactive"',
                  style: TextStyle(fontSize: 14),
                ),
                if (_selectedRole == 'student') ...[
                  const SizedBox(height: 4),
                  const Text(
                    '• Class name must match available classes exactly',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '• Section must match available sections for the class',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
                const SizedBox(height: 12),
                const Text(
                  'Instructions:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text(
                  '1. Fill in your data starting from row 2\n'
                  '2. Keep the header row unchanged\n'
                  '3. Save as CSV file before uploading\n'
                  '4. Ensure role and class values match exactly',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),

        // Error Message
        if (_errorMessage != null) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(_errorMessage!),
        ],

        // Action Buttons
        const SizedBox(height: 24),
        _buildBulkActionButtons(),
      ],
    );
  }

  Widget _buildBulkActionButtons() {
    return Row(
      children: [
        if (!_isDesktop) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedRole = null;
                  _selectedFile = null;
                  _showBulkPreview = false;
                  _validUsersForBulk.clear();
                  _bulkValidationErrors.clear();
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Change Role'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _isLoading ? null : _validateBulkUsers,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 21, 101, 192),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Validate & Preview',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ] else ...[
          const Expanded(flex: 2, child: SizedBox()),
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedRole = null;
                  _selectedFile = null;
                  _showBulkPreview = false;
                  _validUsersForBulk.clear();
                  _bulkValidationErrors.clear();
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Change Role'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 1,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _validateBulkUsers,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 21, 101, 192),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Validate & Preview',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
