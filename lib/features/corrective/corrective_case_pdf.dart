import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'corrective_pdf_download_stub.dart'
    if (dart.library.js_interop) 'corrective_pdf_download_web.dart';
import 'corrective_repository.dart';
import 'corrective_widgets.dart';

Future<void> exportCorrectiveCase(CorrectiveDetail detail) async {
  final bytes = await createCorrectiveCasePdf(detail);
  downloadCorrectivePdf('Uni360-${detail.incident.reference}.pdf', bytes);
}

Future<Uint8List> createCorrectiveCasePdf(CorrectiveDetail detail) async {
  final caseFile = detail.incident;
  final pdf = pw.Document(title: 'Uni360 ${caseFile.reference}');
  const ink = PdfColor.fromInt(0xff17324b);
  const teal = PdfColor.fromInt(0xff117568);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      header: (_) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 18),
        child: pw.Text(
          'UNI360 / CAMPUS OPERATIONS',
          style: pw.TextStyle(
            fontSize: 11,
            color: teal,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${caseFile.reference}  |  Page ${context.pageNumber}',
          style: const pw.TextStyle(color: ink, fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.Text(
          'Corrective maintenance case',
          style: pw.TextStyle(
            fontSize: 24,
            color: ink,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          '${caseFile.reference}  |  ${caseFile.statusLabel}  |  ${caseFile.urgency} priority',
        ),
        pw.SizedBox(height: 18),
        pw.Text(
          caseFile.title,
          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text('Facility  ${caseFile.facility}'),
        pw.Text('Location  ${caseFile.location}'),
        pw.Text('Category  ${caseFile.category}'),
        pw.Text('Reported by  ${caseFile.reporter}'),
        pw.Text('Submitted  ${correctiveTime(caseFile.created)}'),
        if (caseFile.worker case final technician?)
          pw.Text('Technician  $technician'),
        if (caseFile.resolved case final resolved?)
          pw.Text('Resolved  ${correctiveTime(resolved)}'),
        pw.SizedBox(height: 12),
        pw.Text(
          'Reporter description',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Paragraph(text: caseFile.description),
        if (caseFile.photoAssessment case final assessment?) ...[
          pw.Text(
            'Photo analysis',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(text: assessment),
          if (caseFile.photoCategory case final category?)
            pw.Text('Photo category  $category'),
          if (caseFile.photoPriority case final priority?)
            pw.Text('Photo priority  $priority'),
        ],
        pw.Header(level: 1, text: 'Repair and verification'),
        if (detail.visits.isEmpty)
          pw.Text('No completed visit has been recorded.'),
        for (final visit in detail.visits) ...[
          pw.Text('Visit ${visit['attempt']}'),
          if (visit['started_at'] case final String started)
            pw.Text('Started  ${correctiveTime(DateTime.parse(started))}'),
          if (visit['submitted_at'] case final String submitted)
            pw.Text(
              'Evidence submitted  ${correctiveTime(DateTime.parse(submitted))}',
            ),
          if (visit['notes'] case final String notes) pw.Paragraph(text: notes),
        ],
        pw.Text(
          'Evidence on file  ${caseFile.reportPhoto == null ? 0 : 1} report photo, ${detail.photos.length} completion photos',
        ),
        pw.Header(level: 1, text: 'Case history'),
        for (final event in detail.events.reversed) ...[
          pw.Text(
            '${correctiveTime(DateTime.parse(event['occurred_at'] as String))}  |  ${event['event']}',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          if ((event['note'] as String).isNotEmpty)
            pw.Paragraph(text: event['note'] as String),
          pw.SizedBox(height: 4),
        ],
      ],
    ),
  );
  return pdf.save();
}
