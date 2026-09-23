import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_import_validator.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PdfImportValidator', () {
    test('recognizes PDF names case-insensitively and ignores query strings', () {
      expect(PdfImportValidator.isPdfName('document.PDF'), isTrue);
      expect(
        PdfImportValidator.isPdfName('https://example.test/file.pdf?download=1'),
        isTrue,
      );
      expect(PdfImportValidator.isPdfName('document.pdf.txt'), isFalse);
    });

    test('validates signature, MIME type, size, and SHA-256', () async {
      final bytes = utf8.encode('%PDF-1.7\nvalid test document');
      final file = XFile.fromData(
        bytes,
        name: 'sample.pdf',
        mimeType: 'application/pdf',
      );

      final metadata = await PdfImportValidator.validateFile(file);

      expect(metadata.size, bytes.length);
      expect(
        metadata.sha256,
        '9260151371056588d1d4eb733b7d9a76cea400bc4ac4cec6f0b4a69319cceeb3',
      );
    });

    test('rejects a renamed non-PDF', () async {
      final file = XFile.fromData(
        utf8.encode('not a PDF'),
        name: 'renamed.pdf',
        mimeType: 'application/pdf',
      );

      expect(
        () => PdfImportValidator.validateFile(file),
        throwsA(isA<PdfImportException>()),
      );
    });

    test('rejects an oversized file', () async {
      final file = XFile.fromData(
        utf8.encode('%PDF-1.7'),
        name: 'large.pdf',
        mimeType: 'application/pdf',
      );

      expect(
        () => PdfImportValidator.validateFile(file, maximumBytes: 4),
        throwsA(isA<PdfImportException>()),
      );
    });

    test('rejects an empty file', () async {
      final file = XFile.fromData(
        Uint8List(0),
        name: 'empty.pdf',
        mimeType: 'application/pdf',
      );

      expect(
        () => PdfImportValidator.validateFile(file),
        throwsA(isA<PdfImportException>()),
      );
    });
  });
}
