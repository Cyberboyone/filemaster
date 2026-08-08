import 'dart:io';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../models/recent_file.dart';
import '../providers/recents_provider.dart';
import '../utils/doc_format.dart';
import '../utils/output_utils.dart';
import 'viewer_screen.dart';

/// Scan documents with the camera and save them as a single PDF.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _scanning = false;

  Future<void> _scan() async {
    if (_scanning) return;
    final camera = await Permission.camera.request();
    if (!camera.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required to scan')),
      );
      return;
    }

    setState(() => _scanning = true);
    try {
      final result = await CunningDocumentScanner.getPictures(
        noOfPages: 100,
        scannerSource: ScannerSource.cameraAndGallery,
        asPdf: true,
      );
      if (!mounted) return;
      setState(() => _scanning = false);

      if (result == null || result.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Scan cancelled')));
        return;
      }

      final scanned = File(result.first);
      final saved = await saveOutput(
        await scanned.readAsBytes(),
        timestampedName('Scan', 'pdf'),
      );
      final recent = RecentFile(
        name: p.basename(saved.path),
        path: saved.path,
        format: DocFormat.pdf,
        sizeBytes: await saved.length(),
        lastOpened: DateTime.now(),
      );
      await ref.read(recentsControllerProvider.notifier).recordOpen(recent);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Scan saved as PDF')));
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ViewerScreen(file: recent)));
    } catch (error) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scan failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan to PDF')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.document_scanner_outlined,
              size: 72,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan documents with the camera or import from gallery.\n'
              'Pages are combined into a single PDF.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _scanning ? null : _scan,
              icon: _scanning
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_scanning ? 'Scanning…' : 'Start scanning'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
