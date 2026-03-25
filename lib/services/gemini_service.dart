import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class GeminiService {
  static const String _apiKey = 'AIzaSyA814r7S0eV2xx97LjWANdkjzf54_LUfAc';
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  static Future<String> generateContent(String prompt) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_geminiUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              "contents": [
                {
                  "parts": [
                    {"text": prompt}
                  ]
                }
              ],
              "generationConfig": {
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 8192,
              },
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(response.body);
        final candidates = jsonResponse['candidates'] as List<dynamic>? ?? [];
        if (candidates.isEmpty) return 'No response generated.';
        
        final parts = candidates[0]['content']['parts'] as List<dynamic>? ?? [];
        if (parts.isEmpty) return 'No content in response.';
        
        return parts[0]['text'] as String;
      } else {
        throw Exception('Failed to generate content: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Gemini Error: $e');
      throw Exception('Failed to connect to AI service.');
    }
  }

  static Future<List<Map<String, dynamic>>> generateQuizQuestions({
    required String topic,
    required String gradeLevel,
    required String difficulty,
    required int count,
    required String type, // 'multiple_choice', 'fill_blank', 'match_following'
  }) async {
    String prompt;
    
    if (type == 'multiple_choice') {
      prompt = '''
      Generate $count multiple choice questions for a quiz about "$topic".
      Target Audience: Grade $gradeLevel students.
      Difficulty: $difficulty.
      
      Return ONLY a raw JSON array (no markdown code blocks, no backticks).
      Format:
      [
        {
          "questionText": "Question string",
          "options": ["Option A", "Option B", "Option C", "Option D"],
          "correctAnswerIndex": 0 // integer 0-3
        }
      ]
      ''';
    } else if (type == 'fill_blank') {
       prompt = '''
      Generate $count fill-in-the-blank questions for a quiz about "$topic".
      Target Audience: Grade $gradeLevel students.
      Difficulty: $difficulty.
      
      Return ONLY a raw JSON array (no markdown code blocks, no backticks).
      Format:
      [
        {
          "questionText": "The capital of France is ______.",
          "correctAnswer": "Paris"
        }
      ]
      ''';
    } else if (type == 'match_following') {
       prompt = '''
      Generate $count match the following questions for a quiz about "$topic".
      Target Audience: Grade $gradeLevel students.
      Difficulty: $difficulty.
      
      Return ONLY a raw JSON array (no markdown code blocks, no backticks).
      Format:
      [
        {
          "questionText": "Match the following related to $topic",
          "pairs": [
            {"left": "Item 1", "right": "Match 1"},
            {"left": "Item 2", "right": "Match 2"},
            {"left": "Item 3", "right": "Match 3"},
            {"left": "Item 4", "right": "Match 4"}
          ]
        }
      ]
      ''';
    } else if (type == 'true_false') {
      prompt = '''
      Generate $count true or false questions for a quiz about "$topic".
      Target Audience: Grade $gradeLevel students.
      Difficulty: $difficulty.
      
      Return ONLY a raw JSON array (no markdown code blocks, no backticks).
      Format:
      [
        {
          "questionText": "Question statement that is either true or false",
          "correctAnswer": true // boolean true or false
        }
      ]
      ''';
    } else if (type == 'ordering') {
      prompt = '''
      Generate $count ordering/sequencing questions for a quiz about "$topic".
      Target Audience: Grade $gradeLevel students.
      Difficulty: $difficulty.
      
      Return ONLY a raw JSON array (no markdown code blocks, no backticks).
      Format:
      [
        {
          "questionText": "Arrange the following in correct order...",
          "correctOrder": ["First Item", "Second Item", "Third Item", "Fourth Item"] 
        }
      ]
      ''';
    } else {
      return [];
    }

    try {
      String rawContent = await generateContent(prompt);
      
      // Clean up markdown if Gemini adds it despite instructions
      rawContent = rawContent.replaceAll('```json', '').replaceAll('```', '').trim();
      
      final List<dynamic> jsonList = json.decode(rawContent);
      return List<Map<String, dynamic>>.from(jsonList);
    } catch (e) {
      debugPrint('Error parsing AI quiz: $e');
      throw Exception('Failed to generate valid quiz questions.');
    }
  }
}
