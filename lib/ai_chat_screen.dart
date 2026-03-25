// ai_chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class AiChatScreen extends StatefulWidget {
  final String userId;
  final String schoolCode;
  final String schoolName;
  final String studentName;
  final String? studentClassId;
  final int studentLevel;

  const AiChatScreen({
    super.key,
    required this.userId,
    required this.schoolCode,
    required this.schoolName,
    required this.studentName,
    this.studentClassId,
    required this.studentLevel,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with TickerProviderStateMixin {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _showSidebar = false;
  List<ChatSession> _chatHistory = [];
  bool _isLoadingHistory = false;
  int _remainingQuestions = 10;
  DateTime? _lastResetDate;
  bool _hasUserSentMessage = false;
  String? _currentSessionId;
  bool _sidebarCollapsed = true;
  Map<String, bool> _pinnedSessions = {};

  late AnimationController _typingAnimationController;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Enhanced color scheme for beauty
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _cardColor = Color(0xFFFFFFFF);
  static const Color _primaryColor = Color(0xFF4F46E5);
  static const Color _primaryLight = Color(0xFF6366F1);
  static const Color _secondaryColor = Color(0xFF8B5CF6);
  static const Color _accentColor = Color(0xFF06B6D4);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textColor = Color(0xFF0F172A);
  static const Color _textSecondaryColor = Color(0xFF64748B);
  static const Color _userMessageBg = Color(0xFF4F46E5);
  static const Color _aiMessageBg = Color(0xFFF1F5F9);
  static const Color _warningColor = Color(0xFFEAB308);
  static const Color _successColor = Color(0xFF059669);
  static const Color _selectedColor = Color(0xFFF0F9FF);
  static const Color _shadowColor = Color(0x1A000000);
  static const Color _codeBg = Color(0xFFF8FAFC);

  static const String _apiKey = 'AIzaSyA814r7S0eV2xx97LjWANdkjzf54_LUfAc';
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  @override
  void initState() {
    super.initState();
    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _loadDailyLimit();
    _loadChatHistory();
    _addWelcomeMessage();
  }

  void _addWelcomeMessage() {
    if (_messages.isEmpty) {
      setState(() {
        _messages.add(
          ChatMessage(
            content:
                '''👋 **Hello ${widget.studentName}!** I'm your AI learning assistant.

I'm here to help you with:
• **Math** problems and concepts
• **Science** explanations  
• **History** and social studies
• **Language** and grammar
• **Homework** help
• **Study** strategies

Feel free to ask me anything about your studies! What would you like to learn today?''',
            isUser: false,
            timestamp: DateTime.now(),
          ),
        );
      });
    }
  }

  Future<void> _loadDailyLimit() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final usageDoc = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('ai_usage')
          .doc('${widget.userId}_${DateFormat('yyyy-MM-dd').format(today)}')
          .get();

      if (usageDoc.exists) {
        final data = usageDoc.data() ?? {};
        setState(() {
          _remainingQuestions = 10 - (data['question_count'] as int? ?? 0);
          _lastResetDate = (data['date'] as Timestamp?)?.toDate();
        });
      } else {
        setState(() {
          _remainingQuestions = 10;
          _lastResetDate = today;
        });
      }
    } catch (e) {
      debugPrint('Error loading daily limit: $e');
      setState(() => _remainingQuestions = 10);
    }
  }

  Future<void> _incrementQuestionCount() async {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final docId =
          '${widget.userId}_${DateFormat('yyyy-MM-dd').format(today)}';

      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('ai_usage')
          .doc(docId)
          .set({
            'student_id': widget.userId,
            'school_code': widget.schoolCode,
            'date': today,
            'question_count': FieldValue.increment(1),
            'last_question_time': Timestamp.now(),
          }, SetOptions(merge: true));

      if (mounted) {
        setState(() => _remainingQuestions--);
      }
    } catch (e) {
      debugPrint('Error incrementing question count: $e');
    }
  }

  Future<void> _loadChatHistory() async {
    setState(() => _isLoadingHistory = true);

    try {
      final historySnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('ai_chats')
          .where('student_id', isEqualTo: widget.userId)
          .orderBy('timestamp', descending: true)
          .limit(20)
          .get()
          .catchError((error) {
            debugPrint('Index error, falling back: $error');
            return _loadChatHistoryFallback();
          });

      if (historySnapshot is QuerySnapshot) {
        _processChatHistory(historySnapshot);
      }
    } catch (e) {
      debugPrint('Error loading chat history: $e');
      await _loadChatHistoryFallback();
    } finally {
      if (mounted) {
        setState(() => _isLoadingHistory = false);
      }
    }
  }

  Future<QuerySnapshot> _loadChatHistoryFallback() async {
    try {
      final historySnapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('ai_chats')
          .where('student_id', isEqualTo: widget.userId)
          .get();
      final sessions = <ChatSession>[];

      for (var doc in historySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final messagesList = data['messages'] as List<dynamic>? ?? [];
        final messages = messagesList
            .map(
              (msg) => ChatMessage(
                content:
                    (msg as Map<String, dynamic>?)?['content'] as String? ?? '',
                isUser: (msg?['role'] as String?) == 'user',
                timestamp:
                    (msg?['timestamp'] as Timestamp?)?.toDate() ??
                    DateTime.now(),
              ),
            )
            .toList();

        final isPinned = data['pinned'] as bool? ?? false;
        _pinnedSessions[doc.id] = isPinned;

        sessions.add(
          ChatSession(
            id: doc.id,
            title: data['title'] as String? ?? 'Conversation',
            timestamp:
                (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
            messages: messages,
          ),
        );
      }

      sessions.sort((a, b) {
        final aPinned = _pinnedSessions[a.id] ?? false;
        final bPinned = _pinnedSessions[b.id] ?? false;
        if (aPinned && !bPinned) return -1;
        if (!aPinned && bPinned) return 1;
        return b.timestamp.compareTo(a.timestamp);
      });

      if (mounted) {
        setState(() => _chatHistory = sessions.take(20).toList());
      }
      return historySnapshot;
    } catch (e) {
      debugPrint('Fallback error: $e');
      if (mounted) {
        setState(() => _chatHistory = []);
      }
      rethrow;
    }
  }

  void _processChatHistory(QuerySnapshot historySnapshot) {
    final sessions = <ChatSession>[];
    for (var doc in historySnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>? ?? {};
      final messagesList = data['messages'] as List<dynamic>? ?? [];
      final messages = messagesList.map((msg) {
        final msgMap = msg as Map<String, dynamic>? ?? {};
        return ChatMessage(
          content: msgMap['content'] as String? ?? '',
          isUser: (msgMap['role'] as String?) == 'user',
          timestamp:
              (msgMap['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
        );
      }).toList();

      final isPinned = data['pinned'] as bool? ?? false;
      _pinnedSessions[doc.id] = isPinned;

      sessions.add(
        ChatSession(
          id: doc.id,
          title: data['title'] as String? ?? 'Conversation',
          timestamp:
              (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
          messages: messages,
        ),
      );
    }

    sessions.sort((a, b) {
      final aPinned = _pinnedSessions[a.id] ?? false;
      final bPinned = _pinnedSessions[b.id] ?? false;
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return b.timestamp.compareTo(a.timestamp);
    });

    if (mounted) {
      setState(() => _chatHistory = sessions);
    }
  }

  Future<void> _saveChatToHistory(
    String title,
    List<ChatMessage> messages,
  ) async {
    try {
      final messagesToSave = messages
          .where((msg) => !_isWelcomeMessage(msg.content))
          .toList();
      if (messagesToSave.isEmpty) return;

      final sessionRef = _currentSessionId == null
          ? FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolCode)
                .collection('ai_chats')
                .doc()
          : FirebaseFirestore.instance
                .collection('schools')
                .doc(widget.schoolCode)
                .collection('ai_chats')
                .doc(_currentSessionId!);

      await sessionRef.set({
        'id': sessionRef.id,
        'student_id': widget.userId,
        'student_name': widget.studentName,
        'school_code': widget.schoolCode,
        'title': title,
        'timestamp': Timestamp.now(),
        'messages': messagesToSave
            .map(
              (msg) => {
                'role': msg.isUser ? 'user' : 'model',
                'content': msg.content,
                'timestamp': Timestamp.fromDate(msg.timestamp),
              },
            )
            .toList(),
        'class_id': widget.studentClassId,
        'student_level': widget.studentLevel,
      });

      if (_currentSessionId == null && mounted) {
        setState(() => _currentSessionId = sessionRef.id);
      }

      await _loadChatHistory();
    } catch (e) {
      debugPrint('Error saving chat: $e');
    }
  }

  bool _isWelcomeMessage(String content) =>
      content.contains('👋') &&
      content.contains("I'm your AI learning assistant");

  String _buildSystemPrompt() {
    return '''You are an AI tutor helping a student from ${widget.schoolName}.
Student Name: ${widget.studentName}
Student Level: ${widget.studentLevel}/10 (performance level)
Current Date: ${DateFormat('MMMM dd, yyyy').format(DateTime.now())}

CRITICAL INSTRUCTIONS:
1. You MUST ONLY answer questions related to education, studies, problem-solving, doubts clarification, academic growth, and syllabus topics.
2. If the student asks anything outside of these topics (e.g., movies, actors, sports, entertainment, or irrelevant casual chat), you MUST firmly and politely warn them to stay on educational topics and state that you are an academic assistant not here for those subjects.
3. Provide clear, educational explanations. Break down complex topics into simple terms.
4. Use rich Markdown formatting (bullet points, headers, bold text, numbered lists) for structured readability.
5. For code, use proper ```language blocks.
6. Be helpful, engaging, but strictly educational.''';
  }

  List<Map<String, dynamic>> _buildChatHistoryForApi() {
    return _messages
        .where((msg) => !_isWelcomeMessage(msg.content))
        .map(
          (msg) => {
            'role': msg.isUser ? 'user' : 'model',
            'parts': [
              {'text': msg.content},
            ],
          },
        )
        .toList();
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isLoading) return;

    if (_remainingQuestions <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Daily limit reached. Try again after 12 AM.'),
          backgroundColor: _warningColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    final userMessage = _messageController.text.trim();
    _messageController.clear();
    _focusNode.unfocus();

    if (!_hasUserSentMessage) {
      if (mounted) {
        setState(() {
          _hasUserSentMessage = true;
          _messages = _messages
              .where((msg) => !_isWelcomeMessage(msg.content))
              .toList();
        });
      }
    }

    if (mounted) {
      setState(() {
        _messages.add(
          ChatMessage(
            content: userMessage,
            isUser: true,
            timestamp: DateTime.now(),
          ),
        );
        _isLoading = true;
      });
      _scrollToBottom();
    }

    try {
      final historyForApi = _buildChatHistoryForApi();
      final response = await http
          .post(
            Uri.parse('$_geminiUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              "systemInstruction": {
                "parts": [
                  {"text": _buildSystemPrompt()},
                ],
              },
              "contents": historyForApi,
              "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
              },
              "safetySettings": [
                {
                  "category": "HARM_CATEGORY_HARASSMENT",
                  "threshold": "BLOCK_MEDIUM_AND_ABOVE",
                },
                {
                  "category": "HARM_CATEGORY_HATE_SPEECH",
                  "threshold": "BLOCK_MEDIUM_AND_ABOVE",
                },
                {
                  "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
                  "threshold": "BLOCK_MEDIUM_AND_ABOVE",
                },
                {
                  "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
                  "threshold": "BLOCK_MEDIUM_AND_ABOVE",
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final candidates = jsonResponse['candidates'] as List<dynamic>? ?? [];
        if (candidates.isEmpty) {
          throw Exception('No candidates in response');
        }
        final candidate = candidates[0] as Map<String, dynamic>? ?? {};
        final content = candidate['content'] as Map<String, dynamic>? ?? {};
        final parts = content['parts'] as List<dynamic>? ?? [];
        if (parts.isEmpty) {
          throw Exception('No parts in content');
        }
        final aiText =
            parts[0]['text'] as String? ??
            'Sorry, I could not generate a response.';

        await _typeResponse(aiText);

        if (mounted) {
          final firstUserMessage = _messages
              .firstWhere(
                (m) => m.isUser && !_isWelcomeMessage(m.content),
                orElse: () => ChatMessage(
                  content: 'Untitled',
                  isUser: true,
                  timestamp: DateTime.now(),
                ),
              )
              .content;
          final title = firstUserMessage.length > 30
              ? '${firstUserMessage.substring(0, 30)}...'
              : firstUserMessage;
          await _saveChatToHistory(title, _messages);
          await _incrementQuestionCount();
        }
      } else {
        throw http.ClientException(
          'Failed: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        setState(() {
          _messages.add(
            ChatMessage(
              content:
                  'Sorry, I encountered an error. Please try again. (Details: $e)',
              isUser: false,
              timestamp: DateTime.now(),
            ),
          );
          _isLoading = false;
        });
        _scrollToBottom();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network or API error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  Future<void> _typeResponse(String fullText) async {
    if (fullText.isEmpty || !mounted) return;

    final isLongOrCode = fullText.length > 2000 || fullText.contains('```');
    setState(() {
      _messages.add(
        ChatMessage(content: '', isUser: false, timestamp: DateTime.now()),
      );
      _isLoading = false;
    });
    _scrollToBottom();

    if (isLongOrCode) {
      if (mounted) {
        setState(() => _messages.last.content = fullText);
      }
      _scrollToBottom();
      return;
    }

    // Gradual typing for short responses
    const int typingSpeedMs = 10; // ~100 chars/sec
    String current = '';
    for (int i = 0; i < fullText.length; i++) {
      if (!mounted) return;
      current += fullText[i];
      setState(() => _messages.last.content = current);
      _scrollToBottom();
      await Future.delayed(Duration(milliseconds: typingSpeedMs));
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _loadChatSession(ChatSession session) {
    if (mounted) {
      setState(() {
        _messages = List<ChatMessage>.from(session.messages);
        _hasUserSentMessage = session.messages.any((m) => m.isUser);
        _showSidebar = false;
        _currentSessionId = session.id;
      });
      _scrollToBottom();
    }
  }

  void _startNewChat() {
    if (_messages.isNotEmpty && _messages.any((m) => m.isUser)) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text('Start New Chat'),
          content: const Text(
            'Are you sure? Current conversation will be cleared.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _clearCurrentChat();
              },
              style: FilledButton.styleFrom(backgroundColor: _primaryColor),
              child: const Text('New Chat'),
            ),
          ],
        ),
      );
    } else {
      _clearCurrentChat();
    }
  }

  void _clearCurrentChat() {
    if (mounted) {
      setState(() {
        _messages.clear();
        _hasUserSentMessage = false;
        _currentSessionId = null;
        _showSidebar = false;
      });
      _addWelcomeMessage();
      _scrollToBottom();
    }
  }

  Future<void> _deleteChatSession(ChatSession session) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Chat'),
        content: Text('Delete "${session.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseFirestore.instance
                    .collection('schools')
                    .doc(widget.schoolCode)
                    .collection('ai_chats')
                    .doc(session.id)
                    .delete();
                if (mounted) {
                  setState(() {
                    _chatHistory.removeWhere((s) => s.id == session.id);
                    _pinnedSessions.remove(session.id);
                  });
                  if (_currentSessionId == session.id) _clearCurrentChat();

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Chat deleted'),
                      backgroundColor: _successColor,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to delete: $e'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameChatSession(ChatSession session) async {
    final controller = TextEditingController(text: session.title);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename Chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Enter new title',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _primaryColor, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                try {
                  await FirebaseFirestore.instance
                      .collection('schools')
                      .doc(widget.schoolCode)
                      .collection('ai_chats')
                      .doc(session.id)
                      .update({
                        'title': newTitle,
                        'last_modified': Timestamp.now(),
                      });

                  if (mounted) {
                    setState(() {
                      final index = _chatHistory.indexWhere(
                        (s) => s.id == session.id,
                      );
                      if (index != -1) {
                        _chatHistory[index] = ChatSession(
                          id: session.id,
                          title: newTitle,
                          timestamp: session.timestamp,
                          messages: session.messages,
                        );
                      }
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Chat renamed'),
                        backgroundColor: _successColor,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  }
                  Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to rename: $e'),
                        backgroundColor: Colors.red,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePinChatSession(ChatSession session) async {
    try {
      final isCurrentlyPinned = _pinnedSessions[session.id] ?? false;
      await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolCode)
          .collection('ai_chats')
          .doc(session.id)
          .update({
            'pinned': !isCurrentlyPinned,
            'last_modified': Timestamp.now(),
          });

      if (mounted) {
        setState(() {
          _pinnedSessions[session.id] = !isCurrentlyPinned;
          _chatHistory.sort((a, b) {
            final aPinned = _pinnedSessions[a.id] ?? false;
            final bPinned = _pinnedSessions[b.id] ?? false;
            if (aPinned && !bPinned) return -1;
            if (!aPinned && bPinned) return 1;
            return b.timestamp.compareTo(a.timestamp);
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCurrentlyPinned ? 'Chat unpinned' : 'Chat pinned'),
            backgroundColor: _successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to pin/unpin: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 1024;
    final isTablet = screenWidth >= 768 && screenWidth < 1024;
    final safePadding = MediaQuery.of(context).padding;
    final layoutWidth = isDesktop
        ? 300.0
        : (isTablet ? 350.0 : screenWidth * 0.85);

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: isDesktop
          ? _buildDesktopLayout()
          : GestureDetector(
              onTap: () => _focusNode.unfocus(),
              child: Column(
                children: [
                  Container(
                    height: 60 + safePadding.top,
                    padding: EdgeInsets.only(top: safePadding.top),
                    decoration: BoxDecoration(
                      color: _cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: _shadowColor,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: _buildAppBar(isDesktop),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            Expanded(child: _buildChatMessages()),
                            _buildMessageInput(),
                          ],
                        ),
                        if (_showSidebar)
                          Positioned.fill(
                            child: Container(
                              color: Colors.black.withOpacity(0.5),
                              child: Row(
                                children: [
                                  Container(
                                    width: layoutWidth,
                                    height: double.infinity,
                                    decoration: BoxDecoration(
                                      color: _cardColor,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 20,
                                        ),
                                      ],
                                    ),
                                    child: _buildSidebarContent(isDesktop),
                                  ),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() => _showSidebar = false);
                                        _focusNode.unfocus();
                                      },
                                      child: Container(
                                        color: Colors.transparent,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        if (_sidebarCollapsed) _buildCollapsedSidebar(),
        if (!_sidebarCollapsed)
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: _cardColor,
              border: Border(right: BorderSide(color: _borderColor)),
              boxShadow: [
                BoxShadow(
                  color: _shadowColor,
                  blurRadius: 8,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: _buildSidebarContent(true),
          ),
        Expanded(
          child: GestureDetector(
            onTap: () => _focusNode.unfocus(),
            child: Column(
              children: [
                _buildAppBar(true),
                Expanded(child: _buildChatMessages()),
                _buildMessageInput(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedSidebar() {
    return Container(
      width: 64,
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border(right: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.menu, color: _primaryColor, size: 24),
            ),
            onPressed: () => setState(() => _sidebarCollapsed = false),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _startNewChat,
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_primaryColor, _primaryLight],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                  tooltip: 'New Chat',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, _secondaryColor],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.studentName.isNotEmpty
                      ? widget.studentName[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent(bool isDesktop) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _borderColor)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: _textColor, size: 22),
                onPressed: () => setState(
                  () => isDesktop
                      ? _sidebarCollapsed = true
                      : _showSidebar = false,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Chat History',
                style: TextStyle(
                  color: _textColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: _textColor, size: 22),
                onPressed: _loadChatHistory,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, _primaryLight],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _primaryColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ElevatedButton.icon(
              onPressed: _startNewChat,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                elevation: 0,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add, size: 22),
              label: const Text(
                'New Chat',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
        Expanded(
          child: _isLoadingHistory
              ? const Center(
                  child: CircularProgressIndicator(
                    color: _primaryColor,
                    strokeWidth: 3,
                  ),
                )
              : _chatHistory.isEmpty
              ? _buildEmptyHistory()
              : _buildHistoryList(isDesktop),
        ),
        _buildUserInfo(),
      ],
    );
  }

  Widget _buildEmptyHistory() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _borderColor.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.chat_bubble_outline,
              size: 56,
              color: _textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No chat history yet',
            style: TextStyle(
              color: _textSecondaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Start a new conversation',
            style: TextStyle(color: _textSecondaryColor, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(bool isDesktop) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _chatHistory.length,
      itemBuilder: (context, index) {
        final session = _chatHistory[index];
        final isSelected = _currentSessionId == session.id;
        final isPinned = _pinnedSessions[session.id] ?? false;

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                _loadChatSession(session);
                if (!isDesktop) setState(() => _showSidebar = false);
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? _selectedColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? _primaryColor : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  leading: _buildSessionIcon(isSelected, isPinned),
                  title: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? _primaryColor : _textColor,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      DateFormat('MMM dd, hh:mm a').format(session.timestamp),
                      style: TextStyle(
                        color: isSelected
                            ? _primaryColor.withOpacity(0.7)
                            : _textSecondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  trailing: _buildSessionMenu(session, isPinned),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSessionIcon(bool isSelected, bool isPinned) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: isSelected
            ? const LinearGradient(colors: [_primaryColor, _primaryLight])
            : null,
        color: isSelected ? null : _borderColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(
              Icons.chat_bubble_outline,
              color: isSelected ? Colors.white : _textSecondaryColor,
              size: isPinned ? 18 : 20,
            ),
          ),
          if (isPinned)
            Positioned(
              right: 4,
              top: 4,
              child: Icon(
                Icons.push_pin,
                color: isSelected ? Colors.white : _primaryColor,
                size: 14,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionMenu(ChatSession session, bool isPinned) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: _textSecondaryColor, size: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _renameChatSession(session);
            break;
          case 'pin':
            await _togglePinChatSession(session);
            break;
          case 'delete':
            _deleteChatSession(session);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              Icon(Icons.edit, size: 20, color: _textColor),
              const SizedBox(width: 12),
              Text('Rename', style: TextStyle(color: _textColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'pin',
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                size: 20,
                color: isPinned ? _primaryColor : _textColor,
              ),
              const SizedBox(width: 12),
              Text(
                isPinned ? 'Unpin' : 'Pin',
                style: TextStyle(color: _textColor),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_primaryColor, _secondaryColor],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: Text(
                widget.studentName.isNotEmpty
                    ? widget.studentName[0].toUpperCase()
                    : 'S',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.studentName,
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Level ${widget.studentLevel}',
                  style: const TextStyle(
                    color: _textSecondaryColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(bool isDesktop) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          if (isDesktop || !_sidebarCollapsed)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: _textColor),
              onPressed: () => Navigator.of(context).pop(),
            ),
          if (!isDesktop && _sidebarCollapsed)
            IconButton(
              icon: const Icon(Icons.menu, color: _textColor),
              onPressed: () => setState(() => _showSidebar = true),
            ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _primaryColor.withOpacity(0.15),
                  _accentColor.withOpacity(0.15),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.auto_awesome,
              color: _primaryColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'AI Assistant',
            style: TextStyle(
              color: _textColor,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _remainingQuestions > 3
                    ? [_primaryColor, _primaryLight]
                    : [_warningColor, const Color(0xFFFBBF24)],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color:
                      (_remainingQuestions > 3 ? _primaryColor : _warningColor)
                          .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Colors.white, size: 18),
                const SizedBox(width: 6),
                Text(
                  '$_remainingQuestions',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessages() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_backgroundColor, _backgroundColor.withOpacity(0.9)],
        ),
      ),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        itemCount: _messages.length + (_isLoading ? 1 : 0),
        itemBuilder: (context, index) => index < _messages.length
            ? _buildMessageBubble(_messages[index], index)
            : _buildTypingIndicator(),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message, int index) {
    final isUser = message.isUser;
    final isLongUserMessage = isUser && message.content.length > 500;
    return Padding(
      padding: EdgeInsets.only(bottom: index == _messages.length - 1 ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isUser)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(right: 12, top: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_secondaryColor, _accentColor],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _secondaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(Icons.smart_toy, size: 22, color: Colors.white),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              decoration: BoxDecoration(
                color: isUser ? _userMessageBg : _aiMessageBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isUser ? 20 : 6),
                  topRight: Radius.circular(isUser ? 6 : 20),
                  bottomLeft: const Radius.circular(20),
                  bottomRight: const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isUser ? 'You' : 'AI Assistant',
                        style: TextStyle(
                          color: isUser
                              ? Colors.white.withOpacity(0.95)
                              : _primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        DateFormat('hh:mm a').format(message.timestamp),
                        style: TextStyle(
                          color: isUser
                              ? Colors.white.withOpacity(0.7)
                              : _textSecondaryColor,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isLongUserMessage)
                    _buildCodeBlock(message.content, isUser)
                  else if (isUser)
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.6,
                      ),
                      softWrap: true,
                    )
                  else
                    MarkdownBody(
                      data: message.content,
                      selectable: true,
                      styleSheet: _buildMarkdownStyleSheet(isUser),
                    ),
                ],
              ),
            ),
          ),
          if (isUser)
            Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.only(left: 12, top: 4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_primaryColor, _primaryLight],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  widget.studentName.isNotEmpty
                      ? widget.studentName[0].toUpperCase()
                      : 'S',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCodeBlock(String content, bool isUser) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 400),
      decoration: BoxDecoration(
        color: isUser ? Colors.black.withOpacity(0.3) : _codeBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isUser ? Colors.white.withOpacity(0.2) : _borderColor,
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: Text(
            content,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: isUser ? Colors.white : _textColor,
              height: 1.4,
            ),
            softWrap: false,
          ),
        ),
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(bool isUser) {
    final textColor = isUser ? Colors.white : _textColor;
    return MarkdownStyleSheet(
      p: TextStyle(fontSize: 15, color: textColor, height: 1.6),
      pPadding: const EdgeInsets.only(bottom: 12),
      strong: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
      code: TextStyle(
        backgroundColor: isUser
            ? Colors.white.withOpacity(0.2)
            : const Color(0xFFF1F5F9),
        fontFamily: 'monospace',
        fontSize: 14,
        color: isUser ? Colors.white : const Color(0xFF0F172A),
        fontWeight: FontWeight.w500,
      ),
      codeblockPadding: const EdgeInsets.all(16),
      codeblockDecoration: BoxDecoration(
        color: isUser ? Colors.black.withOpacity(0.3) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isUser ? Colors.white.withOpacity(0.2) : _borderColor,
          width: 1,
        ),
      ),
      blockquoteDecoration: BoxDecoration(
        color: isUser
            ? Colors.white.withOpacity(0.15)
            : const Color(0xFFF1F5F9),
        border: Border(
          left: BorderSide(
            color: isUser ? Colors.white : _primaryColor,
            width: 4,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(16),
      h1: TextStyle(
        color: textColor,
        fontSize: 24,
        fontWeight: FontWeight.w800,
        height: 1.4,
      ),
      h1Padding: const EdgeInsets.only(top: 24, bottom: 12),
      h2: TextStyle(
        color: textColor,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      h2Padding: const EdgeInsets.only(top: 20, bottom: 10),
      h3: TextStyle(
        color: textColor,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
      h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
      listBullet: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      listIndent: 24,
      blockSpacing: 16,
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(right: 12, top: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_secondaryColor, _accentColor],
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _secondaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.smart_toy, size: 22, color: Colors.white),
          ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.8,
            ),
            decoration: BoxDecoration(
              color: _aiMessageBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: _shadowColor,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Assistant',
                  style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    3,
                    (index) => AnimatedBuilder(
                      animation: _typingAnimationController,
                      builder: (context, child) {
                        final delay = index * 0.2;
                        final value = (_typingAnimationController.value - delay)
                            .clamp(0.0, 1.0);
                        final opacity = (math.sin(
                          value * math.pi,
                        )).clamp(0.3, 1.0);
                        final scale = 0.8 + (math.sin(value * math.pi) * 0.2);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  _primaryColor.withOpacity(opacity),
                                  _accentColor.withOpacity(opacity),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    final screenHeight = MediaQuery.of(context).size.height;
    return Container(
      padding: EdgeInsets.all(screenHeight > 800 ? 20 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: _shadowColor.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              constraints: const BoxConstraints(maxHeight: 200),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _focusNode,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 15,
                        height: 1.5,
                      ),
                      decoration: InputDecoration(
                        hintText: _remainingQuestions > 0
                            ? 'Ask me anything...'
                            : 'Daily limit reached',
                        hintStyle: TextStyle(
                          color: _remainingQuestions > 0
                              ? _textSecondaryColor
                              : _warningColor,
                          fontSize: 15,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 8),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: _remainingQuestions > 0
                            ? const LinearGradient(
                                colors: [_primaryColor, _primaryLight],
                              )
                            : null,
                        color: _remainingQuestions > 0
                            ? null
                            : _borderColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: _remainingQuestions > 0
                            ? [
                                BoxShadow(
                                  color: _primaryColor.withOpacity(0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.send_rounded,
                          color: _remainingQuestions > 0
                              ? Colors.white
                              : _textSecondaryColor,
                          size: 22,
                        ),
                        onPressed: _remainingQuestions > 0
                            ? _sendMessage
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _typingAnimationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }
}

class ChatMessage {
  String content;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.content,
    required this.isUser,
    required this.timestamp,
  });
}

class ChatSession {
  final String id;
  final String title;
  final DateTime timestamp;
  final List<ChatMessage> messages;

  ChatSession({
    required this.id,
    required this.title,
    required this.timestamp,
    required this.messages,
  });
}
