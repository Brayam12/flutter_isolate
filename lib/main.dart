// ignore_for_file: depend_on_referenced_packages, avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:html' as html;

void main() {
  runApp(const MyApp());
}

String convertJsonToCsv(String jsonString) {
  try {
    final List<dynamic> jsonList = jsonDecode(jsonString);
    if (jsonList.isEmpty) return '';

    // Verificar si es una lista de mapas
    if (jsonList.first is! Map) {
      throw FormatException('El JSON no tiene el formato esperado (List<Map>)');
    }

    final headers = (jsonList.first as Map).keys;
    final csvBuffer = StringBuffer();
    csvBuffer.writeln(headers.join(','));

    for (var item in jsonList) {
      final row = headers.map((key) {
        final value = item[key];
        return '"${value?.toString().replaceAll('"', '""') ?? ''}"';
      }).join(',');
      csvBuffer.writeln(row);
    }

    return csvBuffer.toString();
  } catch (e) {
    throw FormatException('Error al convertir JSON a CSV: $e');
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String? _jsonContent;
  String? _csvContent;
  String? _csvFilePath;
  bool _loading = false;

  Future<String> convertInIsolate(String jsonString) async {
    if (kIsWeb) {
      return convertJsonToCsv(jsonString);
    } else {
      final p = ReceivePort();
      try {
        await Isolate.spawn(_isolateEntry, [p.sendPort, jsonString]);
        final result = await p.first as String;
        if (result.startsWith('ERROR:')) {
          throw Exception(result);
        }
        return result;
      } catch (e) {
        throw Exception('Error en el isolate: $e');
      }
    }
  }

  static void _isolateEntry(List<dynamic> args) {
    final SendPort sendPort = args[0];
    final String jsonString = args[1];
    try {
      final csv = convertJsonToCsv(jsonString);
      sendPort.send(csv);
    } catch (e) {
      sendPort.send('ERROR: $e');
    }
  }

  Future<void> pickJsonFile() async {
    setState(() {
      _loading = true;
      _jsonContent = null;
      _csvContent = null;
      _csvFilePath = null;
    });
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) return;

      if (kIsWeb) {
        final bytes = result.files.first.bytes!;
        _jsonContent = utf8.decode(bytes);
      } else {
        final path = result.files.single.path!;
        _jsonContent = await File(path).readAsString();
      }

      setState(() {});
    } catch (e) {
      _showError('Error al cargar JSON: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> convertAndSaveCsv() async {
    if (_jsonContent == null || _jsonContent!.isEmpty) {
      _showError('No hay contenido JSON para convertir');
      return;
    }

    setState(() => _loading = true);

    try {
      final csv = await convertInIsolate(_jsonContent!);
      
      if (kIsWeb) {
        _downloadWebCsv(csv);
        _csvFilePath = 'Descargado en tu navegador';
      } else {
        _csvFilePath = await _saveMobileCsv(csv);
      }

      setState(() {
        _csvContent = csv;
      });

      _showSuccess(kIsWeb 
          ? 'CSV descargado automáticamente' 
          : 'CSV guardado en: $_csvFilePath');
    } catch (e) {
      _showError('Error al convertir: ${e.toString()}');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _downloadWebCsv(String csv) {
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.Url.revokeObjectUrl(url);
  }

  Future<String> _saveMobileCsv(String csv) async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/output_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsString(csv);
    return path;
  }

  Future<void> shareCsv() async {
    if (_csvFilePath == null || (!kIsWeb && !File(_csvFilePath!).existsSync())) {
      _showError('Archivo CSV no disponible');
      return;
    }
    await Share.shareXFiles([XFile(_csvFilePath!)], text: 'CSV generado');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Conversor JSON a CSV'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildActionButtons(),
              const SizedBox(height: 20),
              _buildJsonPreview(),
              if (_csvContent != null) _buildSuccessSection(),
              if (_loading) const Center(child: CircularProgressIndicator()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.upload_file),
          label: const Text('Cargar JSON'),
          onPressed: _loading ? null : pickJsonFile,
        ),
        ElevatedButton.icon(
          icon: const Icon(Icons.transform),
          label: const Text('Convertir a CSV'),
          onPressed: (_jsonContent == null || _loading) 
              ? null 
              : () => convertAndSaveCsv(),
        ),
        if (_csvFilePath != null && !kIsWeb)
          ElevatedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Compartir'),
            onPressed: _loading ? null : shareCsv,
          ),
      ],
    );
  }

  Widget _buildJsonPreview() {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: SingleChildScrollView(
            child: Text(
              _jsonContent ?? 'Selecciona un archivo JSON...',
              style: const TextStyle(fontFamily: 'RobotoMono'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessSection() {
    return Column(
      children: [
        const SizedBox(height: 20),
        const Text(
          '✓ Conversión exitosa',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        if (_csvFilePath != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              _csvFilePath!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}