import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cross_file/cross_file.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';

const int maxPdfImportBytes = 200 * 1024 * 1024;

class PdfImportException implements Exception {
  const PdfImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PdfImportMetadata {
  const PdfImportMetadata({
    required this.sha256,
    required this.size,
  });

  final String sha256;
  final int size;
}

class PdfImportValidator {
  const PdfImportValidator._();

  static bool isPdfName(String name) {
    final path = Uri.tryParse(name)?.path ?? name;
    return path.toLowerCase().endsWith('.pdf');
  }

  static Future<PdfImportMetadata> validateFile(
    XFile file, {
    int maximumBytes = maxPdfImportBytes,
  }) async {
    final size = await file.length();
    if (size == 0) {
      throw const PdfImportException('The PDF is empty.');
    }
    if (size > maximumBytes) {
      throw PdfImportException(
        'The PDF exceeds the ${maximumBytes ~/ (1024 * 1024)} MB import limit.',
      );
    }
    if (file.mimeType != null &&
        file.mimeType != 'application/pdf' &&
        file.mimeType != 'application/x-pdf' &&
        file.mimeType != 'application/octet-stream') {
      throw PdfImportException('The selected file is not a PDF.');
    }
    if (!isPdfName(file.name)) {
      throw const PdfImportException(
        'The selected file does not have a .pdf extension.',
      );
    }

    final bytes = await file.openRead(0, 1024).fold<List<int>>(
          <int>[],
          (result, chunk) => result..addAll(chunk),
        );
    if (!_hasPdfSignature(bytes)) {
      throw const PdfImportException(
        'The selected file does not contain a valid PDF signature.',
      );
    }

    final digest = await sha256.bind(file.openRead()).first;
    return PdfImportMetadata(
      sha256: digest.toString(),
      size: size,
    );
  }

  static Future<XFile> downloadNetworkPdf(
    Uri uri,
    String originalFilename, {
    int maximumBytes = maxPdfImportBytes,
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const PdfImportException('PDF network URLs must use HTTP or HTTPS.');
    }
    final client = http.Client();
    File? temporaryFile;
    IOSink? sink;
    var completed = false;
    try {
      final request = http.Request('GET', uri)..followRedirects = true;
      final response = await client.send(request).timeout(
            const Duration(seconds: 30),
          );
      if (response.statusCode != HttpStatus.ok) {
        throw PdfImportException(
          'The PDF download failed with HTTP ${response.statusCode}.',
        );
      }
      if (response.contentLength != null &&
          response.contentLength! > maximumBytes) {
        throw PdfImportException(
          'The PDF exceeds the ${maximumBytes ~/ (1024 * 1024)} MB import limit.',
        );
      }
      final mimeType = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (mimeType != null &&
          mimeType.isNotEmpty &&
          mimeType != 'application/pdf' &&
          mimeType != 'application/x-pdf' &&
          mimeType != 'application/octet-stream') {
        throw const PdfImportException('The downloaded file is not a PDF.');
      }

      temporaryFile = File(
        '${Directory.systemTemp.path}/appflowy_pdf_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      sink = temporaryFile.openWrite();
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw PdfImportException(
            'The PDF exceeds the ${maximumBytes ~/ (1024 * 1024)} MB import limit.',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      completed = true;
      return XFile(
        temporaryFile.path,
        name: originalFilename,
        mimeType: mimeType == null || mimeType.isEmpty
            ? 'application/octet-stream'
            : mimeType,
      );
    } finally {
      await sink?.close();
      client.close();
      if (!completed && temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
    }
  }

  static Future<PdfImportMetadata> validateAndParse(
    XFile file, {
    int maximumBytes = maxPdfImportBytes,
  }) async {
    final metadata = await validateFile(
      file,
      maximumBytes: maximumBytes,
    );
    final document = file.path.isEmpty
        ? await PdfDocument.openData(
            await file.readAsBytes(),
            sourceName: file.name,
            useProgressiveLoading: false,
          )
        : await PdfDocument.openFile(
            file.path,
            useProgressiveLoading: false,
          );
    try {
      if (document.pages.isEmpty) {
        throw const PdfImportException('The PDF has no pages.');
      }
    } finally {
      await document.dispose();
    }
    return metadata;
  }

  static bool _hasPdfSignature(List<int> bytes) {
    const signature = [37, 80, 68, 70, 45];
    if (bytes.length < signature.length) return false;
    for (var offset = 0; offset <= bytes.length - signature.length; offset++) {
      var matches = true;
      for (var index = 0; index < signature.length; index++) {
        if (bytes[offset + index] != signature[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }
}
