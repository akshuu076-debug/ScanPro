import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ScanProApp());
}

const Color brand = Color(0xFF078DA8);
const Color brandDark = Color(0xFF075D73);

class ScanProApp extends StatelessWidget {
  const ScanProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScanPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: brand),
        scaffoldBackgroundColor: const Color(0xFFF5F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F8FA),
          foregroundColor: Color(0xFF142C3A),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const ScanProHome(),
    );
  }
}

class ScanDocument {
  final String path;
  final String name;
  final DateTime createdAt;
  final int bytes;

  const ScanDocument({
    required this.path,
    required this.name,
    required this.createdAt,
    required this.bytes,
  });
}

class ScanProHome extends StatefulWidget {
  const ScanProHome({super.key});

  @override
  State<ScanProHome> createState() => _ScanProHomeState();
}

class _ScanProHomeState extends State<ScanProHome> {
  final ImagePicker _picker = ImagePicker();
  int _tab = 0;
  bool _busy = false;
  List<ScanDocument> _documents = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  Future<Directory> _docsDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory('${root.path}/ScanPro');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _loadDocuments() async {
    try {
      final dir = await _docsDirectory();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList()
        ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      final items = <ScanDocument>[];
      for (final file in files) {
        final stat = await file.stat();
        items.add(ScanDocument(
          path: file.path,
          name: file.uri.pathSegments.isEmpty
              ? 'Document.pdf'
              : Uri.decodeComponent(file.uri.pathSegments.last),
          createdAt: stat.modified,
          bytes: stat.size,
        ));
      }
      if (mounted) setState(() => _documents = items);
    } catch (_) {
      _message('Could not load documents. Please reopen the app and try again.');
    }
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _scanWithCamera() async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
        maxWidth: 2400,
      );
      if (photo != null) await _createPdfFromImages([photo.path]);
    } catch (e) {
      _message('Camera could not be opened. Check camera permission and try again.');
    }
  }

  Future<void> _importImages() async {
    try {
      final photos = await _picker.pickMultiImage(
        imageQuality: 92,
        maxWidth: 2400,
      );
      if (photos.isNotEmpty) {
        await _createPdfFromImages(photos.map((e) => e.path).toList());
      }
    } catch (e) {
      _message('Could not import images. Please try again.');
    }
  }

  Future<void> _importPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: false,
      );
      if (result == null || result.files.single.path == null) return;
      final source = File(result.files.single.path!);
      final dir = await _docsDirectory();
      final name = _safeName(result.files.single.name);
      final destination = await _uniqueFile(dir, name);
      await source.copy(destination.path);
      await _loadDocuments();
      _message('PDF imported into ScanPro.');
      await _openDocument(destination.path);
    } catch (e) {
      _message('PDF import failed. The selected file may be unavailable.');
    }
  }

  String _safeName(String name) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty) clean = 'Scan_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    if (!clean.toLowerCase().endsWith('.pdf')) clean = '$clean.pdf';
    return clean;
  }

  Future<File> _uniqueFile(Directory dir, String name) async {
    final safe = _safeName(name);
    var output = File('${dir.path}/$safe');
    if (!await output.exists()) return output;
    final dot = safe.toLowerCase().lastIndexOf('.pdf');
    final stem = dot >= 0 ? safe.substring(0, dot) : safe;
    var n = 2;
    while (await output.exists()) {
      output = File('${dir.path}/${stem}_$n.pdf');
      n++;
    }
    return output;
  }

  Future<void> _createPdfFromImages(List<String> paths) async {
    if (paths.isEmpty) return;
    setState(() => _busy = true);
    try {
      final document = pw.Document();
      var addedPages = 0;
      for (final path in paths) {
        final file = File(path);
        if (!await file.exists()) continue;
        final Uint8List bytes = await file.readAsBytes();
        final image = pw.MemoryImage(bytes);
        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(22),
            build: (context) => pw.Center(
              child: pw.Image(image, fit: pw.BoxFit.contain),
            ),
          ),
        );
        addedPages++;
      }
      if (addedPages == 0) {
        _message('No readable images were selected.');
        return;
      }
      final dir = await _docsDirectory();
      final defaultName = 'Scan_${DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now())}.pdf';
      final output = await _uniqueFile(dir, defaultName);
      await output.writeAsBytes(await document.save(), flush: true);
      await _loadDocuments();
      _message('PDF created successfully.');
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('PDF ready'),
            content: Text('${output.uri.pathSegments.last}\n${paths.length} image(s) added.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Done'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openDocument(output.path);
                },
                child: const Text('Open PDF'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _message('PDF creation failed. Try smaller images or check available storage.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDocument(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      _message('This file is no longer available.');
      await _loadDocuments();
      return;
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _message('No compatible PDF viewer was found on this device.');
    }
  }

  Future<void> _shareDocument(ScanDocument doc) async {
    try {
      await Share.shareXFiles([XFile(doc.path)], text: 'Shared from ScanPro');
    } catch (_) {
      _message('Could not share this document.');
    }
  }

  Future<void> _renameDocument(ScanDocument doc) async {
    final controller = TextEditingController(text: doc.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''));
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename PDF'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'File name', suffixText: '.pdf'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    try {
      final dir = await _docsDirectory();
      final target = await _uniqueFile(dir, _safeName('$name.pdf'));
      await File(doc.path).rename(target.path);
      await _loadDocuments();
      _message('Document renamed.');
    } catch (_) {
      _message('Rename failed. Check the file name and try again.');
    }
  }

  Future<void> _deleteDocument(ScanDocument doc) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text('“${doc.name}” will be removed from ScanPro.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await File(doc.path).delete();
      await _loadDocuments();
      _message('Document deleted.');
    } catch (_) {
      _message('Could not delete this file.');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _showTools() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Quick tools', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('Available now'),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.image_outlined)),
                title: const Text('Images to PDF'),
                subtitle: const Text('Convert one or more images into a PDF'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importImages();
                },
              ),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_outlined)),
                title: const Text('Import and open PDF'),
                subtitle: const Text('Copy a PDF into your ScanPro library'),
                onTap: () {
                  Navigator.pop(ctx);
                  _importPdf();
                },
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.construction_outlined),
                title: Text('More PDF tools coming next'),
                subtitle: Text('Merge, split, compress, OCR and page editing are not implemented in this starter build.'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeBody() {
    return RefreshIndicator(
      onRefresh: _loadDocuments,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [brand, brandDark]),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.document_scanner_outlined, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ScanPro', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    Text('PDF Scanner & Document Manager', style: TextStyle(color: Colors.black54, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Search documents',
                onPressed: () => setState(() => _tab = 1),
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [brand, brandDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Turn paper into PDF', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Scan, save and share documents on your device.', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: brandDark, padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _busy ? null : _scanWithCamera,
                    icon: const Icon(Icons.document_scanner),
                    label: const Text('Scan document', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(color: Colors.white, backgroundColor: Colors.white30),
                  const SizedBox(height: 5),
                  const Text('Creating PDF…', style: TextStyle(color: Colors.white)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _actionCard(Icons.photo_library_outlined, 'Import images', 'Images → PDF', _importImages)),
              const SizedBox(width: 12),
              Expanded(child: _actionCard(Icons.picture_as_pdf_outlined, 'Import PDF', 'Open a PDF', _importPdf)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              const Expanded(child: Text('Recent documents', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => setState(() => _tab = 1), child: const Text('View all')),
            ],
          ),
          if (_documents.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: const Column(
                children: [
                  Icon(Icons.folder_open_outlined, size: 42, color: brand),
                  SizedBox(height: 10),
                  Text('No documents yet', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Scan a page or import images to create your first PDF.', textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                ],
              ),
            )
          else
            ..._documents.take(4).map(_documentTile),
          const SizedBox(height: 24),
          const Text('Quick tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: .85,
            children: [
              _toolTile(Icons.image_outlined, 'Images\\nto PDF', _importImages),
              _toolTile(Icons.file_open_outlined, 'Import\\nPDF', _importPdf),
              _toolTile(Icons.merge_type, 'Merge\\nPDF', _showTools),
              _toolTile(Icons.compress, 'Compress\\nPDF', _showTools),
              _toolTile(Icons.call_split, 'Split\\nPDF', _showTools),
              _toolTile(Icons.text_fields, 'OCR / Text', _showTools),
              _toolTile(Icons.rotate_right, 'Rotate\\nPages', _showTools),
              _toolTile(Icons.more_horiz, 'More tools', _showTools),
            ],
          ),
          const SizedBox(height: 16),
          const Center(child: Text('Private by design • Files stay on your device', style: TextStyle(color: Colors.black54, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _actionCard(IconData icon, String title, String subtitle, VoidCallback action) {
    return InkWell(
      onTap: _busy ? null : action,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: brand, size: 26),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }

  Widget _toolTile(IconData icon, String title, VoidCallback action) {
    return InkWell(
      onTap: action,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: brand, size: 24),
          const SizedBox(height: 7),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _documentTile(ScanDocument doc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => _openDocument(doc.path),
        leading: Container(
          width: 44,
          height: 48,
          decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.picture_as_pdf, color: Colors.red, size: 28),
        ),
        title: Text(doc.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${_formatBytes(doc.bytes)} • ${DateFormat('dd MMM yyyy, h:mm a').format(doc.createdAt)}'),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'open') _openDocument(doc.path);
            if (value == 'share') _shareDocument(doc);
            if (value == 'rename') _renameDocument(doc);
            if (value == 'delete') _deleteDocument(doc);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'open', child: Text('Open')),
            PopupMenuItem(value: 'share', child: Text('Share')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Widget _documentsBody() {
    final filtered = _documents.where((d) => d.name.toLowerCase().contains(_search.toLowerCase())).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search documents',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.folder_open, size: 48, color: brand),
                    const SizedBox(height: 10),
                    Text(_search.isEmpty ? 'No saved PDFs yet' : 'No matching documents'),
                  ]),
                )
              : RefreshIndicator(
                  onRefresh: _loadDocuments,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) => _documentTile(filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _settingsBody() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('Settings', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Card(child: Column(children: [
          const ListTile(leading: Icon(Icons.shield_outlined, color: brand), title: Text('Privacy'), subtitle: Text('ScanPro stores generated PDFs in app-private storage.')),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.storage_outlined, color: brand),
            title: const Text('Saved documents'),
            subtitle: Text('${_documents.length} PDF file(s) • ${_formatBytes(_documents.fold<int>(0, (sum, d) => sum + d.bytes))}'),
            onTap: _loadDocuments,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined, color: brand),
            title: const Text('Refresh document list'),
            onTap: _loadDocuments,
          ),
          const Divider(height: 1),
          const ListTile(
            leading: Icon(Icons.info_outline, color: brand),
            title: Text('About ScanPro'),
            subtitle: Text('Starter build • Offline-first core workflow'),
          ),
        ])),
        const SizedBox(height: 12),
        const Text('This starter version does not yet include automatic edge detection, perspective correction, OCR, PDF merge/split, or compression. These require additional implementation and testing.', style: TextStyle(color: Colors.black54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['ScanPro', 'Documents', 'Tools', 'Settings'];
    return Scaffold(
      appBar: _tab == 0
          ? null
          : AppBar(
              title: Text(titles[_tab]),
              actions: [
                if (_tab == 1)
                  IconButton(onPressed: _loadDocuments, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
              ],
            ),
      body: IndexedStack(
        index: _tab == 0 ? 0 : _tab == 1 ? 1 : _tab == 2 ? 2 : 3,
        children: [
          _homeBody(),
          _documentsBody(),
          _toolsPage(),
          _settingsBody(),
        ],
      ),
      floatingActionButton: _tab == 1
          ? FloatingActionButton(
              onPressed: _scanWithCamera,
              backgroundColor: brand,
              foregroundColor: Colors.white,
              tooltip: 'Scan document',
              child: const Icon(Icons.document_scanner),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) {
          if (value == 2) {
            setState(() => _tab = value);
          } else {
            setState(() => _tab = value);
          }
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.folder_outlined), selectedIcon: Icon(Icons.folder), label: 'Documents'),
          NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _toolsPage() {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const Text('PDF tools', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Working tools are marked below. More tools can be added in the next development stage.', style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 16),
        _toolList(Icons.image_outlined, 'Images to PDF', 'Create a PDF from gallery images', _importImages, true),
        _toolList(Icons.file_open_outlined, 'Import PDF', 'Copy a PDF into the local library', _importPdf, true),
        _toolList(Icons.merge_type, 'Merge PDF', 'Combine multiple PDFs', _showTools, false),
        _toolList(Icons.call_split, 'Split PDF', 'Extract page ranges', _showTools, false),
        _toolList(Icons.compress, 'Compress PDF', 'Reduce file size', _showTools, false),
        _toolList(Icons.text_fields, 'OCR / Extract text', 'Recognize printed text', _showTools, false),
        _toolList(Icons.rotate_right, 'Rotate / Reorder pages', 'Edit existing PDF pages', _showTools, false),
        _toolList(Icons.watermark_outlined, 'Watermark / Page numbers', 'Add text overlays', _showTools, false),
      ],
    );
  }

  Widget _toolList(IconData icon, String title, String subtitle, VoidCallback action, bool ready) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: const Color(0xFFE4F6F8), child: Icon(icon, color: brandDark)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: ready
            ? const Icon(Icons.arrow_forward_ios, size: 16)
            : const Text('Next stage', style: TextStyle(fontSize: 11, color: Colors.black54)),
        onTap: action,
      ),
    );
  }
}
