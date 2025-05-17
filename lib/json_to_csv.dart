import 'dart:convert';

String convertJsonToCsv(String jsonString) {
  final List<dynamic> jsonList = jsonDecode(jsonString);
  if (jsonList.isEmpty) return '';

  final headers = jsonList.first.keys;
  final csvBuffer = StringBuffer();
  csvBuffer.writeln(headers.join(','));

  for (var item in jsonList) {
    final row = headers.map((key) => item[key]).join(',');
    csvBuffer.writeln(row);
  }

  return csvBuffer.toString();
}
