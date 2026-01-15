import 'dart:convert';

Map<String, dynamic>? extractJson(String s,[String separator = '']) {
  print('🔍 extractJson: Starting extraction, string length: ${s.length}');
  final index = s.indexOf(separator) + separator.length;
  if (index > s.length) {
    print('❌ extractJson: Separator index out of bounds');
    return null;
  }

  final str = s.substring(index);

  final startIdx = str.indexOf('{');
  var endIdx = str.lastIndexOf('}');

  print('🔍 extractJson: startIdx: $startIdx, endIdx: $endIdx');

  while (true) {
    try {
      var jsonStr = str.substring(startIdx, endIdx + 1);
      print('🔍 extractJson: Attempting to parse JSON (length: ${jsonStr.length})');
      var result = json.decode(jsonStr) as Map<String, dynamic>;
      print('✅ extractJson: Successfully parsed JSON');
      return result;
    } on FormatException catch (e) {
      print('⚠️ extractJson: FormatException: ${e.message}');
      endIdx = str.lastIndexOf('}', endIdx - 1);
      if (endIdx <= startIdx) {
        print('❌ extractJson: Could not find valid JSON');
        return null;
      }
    }
  }
}