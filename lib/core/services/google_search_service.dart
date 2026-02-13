import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:flutter/foundation.dart';

/// Scrapes Google search results for a barcode and returns a cleaned product title.
class GoogleSearchService {
  /// Returns a probable product title or null if not found/blocked.
  static Future<String?> fetchProductTitle(String barcode) async {
    try {
      if (barcode.trim().isEmpty) return null;

      final url = Uri.parse('https://www.google.com/search?q=$barcode&hl=tr');
      final headers = {
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36',
      };

      final response = await http.get(url, headers: headers);
      if (response.statusCode != 200) {
        debugPrint('GoogleSearchService: HTTP ${response.statusCode} for $barcode');
        return null;
      }

      final document = parser.parse(response.body);
      final h3Elements = document.getElementsByTagName('h3');
      debugPrint('GoogleSearchService: found ${h3Elements.length} h3 elements for $barcode');
      if (h3Elements.isEmpty) return null;

      final rawTitle = h3Elements.first.text;
      final cleaned = rawTitle.split('-').first.trim();
      debugPrint('GoogleSearchService: raw="$rawTitle" cleaned="$cleaned"');

      // If the cleaned title still contains the barcode, treat as not found
      if (cleaned.contains(barcode)) return null;

      return cleaned.isNotEmpty ? cleaned : null;
    } catch (e) {
      debugPrint('GoogleSearchService error for $barcode: $e');
      return null;
    }
  }
}
