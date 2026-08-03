import '../utils/doc_format.dart';

class RecentFile {
  const RecentFile({
    this.id,
    required this.name,
    required this.path,
    required this.format,
    required this.sizeBytes,
    required this.lastOpened,
  });

  final int? id;
  final String name;
  final String path;
  final DocFormat format;
  final int sizeBytes;
  final DateTime lastOpened;

  RecentFile copyWith({
    int? id,
    String? name,
    String? path,
    DocFormat? format,
    int? sizeBytes,
    DateTime? lastOpened,
  }) {
    return RecentFile(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      format: format ?? this.format,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      lastOpened: lastOpened ?? this.lastOpened,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'name': name,
      'path': path,
      'format': format.storageKey,
      'size': sizeBytes,
      'lastOpened': lastOpened.millisecondsSinceEpoch,
    };
  }

  factory RecentFile.fromMap(Map<String, Object?> map) {
    return RecentFile(
      id: map['id'] as int?,
      name: map['name'] as String,
      path: map['path'] as String,
      format: DocFormat.fromStorageKey(map['format'] as String),
      sizeBytes: (map['size'] as int?) ?? 0,
      lastOpened:
          DateTime.fromMillisecondsSinceEpoch((map['lastOpened'] as int?) ?? 0),
    );
  }
}
