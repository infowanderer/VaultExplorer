import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

bool validOrganizerName(String name) =>
    name.trim().isNotEmpty &&
    name != '.' &&
    name != '..' &&
    utf8.encode(name).length <= 240 &&
    !name.endsWith('.') &&
    !name.endsWith(' ') &&
    !name.contains(RegExp(r'[\/\\:*?"<>|\x00-\x1f]'));

class RenameInput {
  const RenameInput(this.path, this.modified);
  final String path;
  final int modified;
}

class RenameRow {
  const RenameRow(this.path, this.name, {this.error});
  final String path, name;
  final String? error;
  bool get unchanged => p.posix.basename(path) == name;
}

/// A deterministic preview only: no file reads, persistence or filesystem writes.
List<RenameRow> buildRenamePlan(
  List<RenameInput> files,
  String template, {
  int start = 1,
  int step = 1,
}) {
  if (files.isEmpty ||
      files.length > 200 ||
      files.map((f) => f.path).toSet().length != files.length) {
    throw const FormatException('Choose between 1 and 200 photographs.');
  }
  if (template.isEmpty ||
      template.length > 500 ||
      start < 0 ||
      start > 999999999 ||
      step < 1 ||
      step > 999999) {
    throw const FormatException(
      'Use a template, a non-negative counter and a positive step.',
    );
  }
  final token = RegExp(r'\{([^{}]+)\}');
  final leftovers = template.replaceAll(token, '');
  if (leftovers.contains('{') || leftovers.contains('}')) {
    throw const FormatException(
      'Close each template token with a matching brace.',
    );
  }
  final results = <RenameRow>[];
  for (var i = 0; i < files.length; i++) {
    final file = files[i];
    final base = p.posix.basename(file.path);
    final extension = p.posix.extension(base);
    final name = template.replaceAllMapped(token, (match) {
      final key = match[1]!;
      if (key == 'name') return p.posix.basenameWithoutExtension(base);
      if (key == 'ext') {
        return extension.startsWith('.') ? extension.substring(1) : extension;
      }
      if (key == 'counter') return '${start + i * step}';
      if (key.startsWith('counter:') &&
          RegExp(r'^counter:0?[1-9]$').hasMatch(key)) {
        return '${start + i * step}'.padLeft(int.parse(key.substring(8)), '0');
      }
      if (key.startsWith('modified:')) {
        final format = key.substring(9);
        if (!RegExp(r'^[yMdHms_\-]{1,32}$').hasMatch(format)) {
          throw const FormatException(
            'Modified-date tokens support y M d H m s, hyphens and underscores.',
          );
        }
        return DateFormat(format, 'en_US').format(
          DateTime.fromMillisecondsSinceEpoch(file.modified, isUtc: true),
        );
      }
      throw FormatException('Unknown template token: {$key}');
    });
    results.add(
      RenameRow(
        file.path,
        name,
        error: validOrganizerName(name) ? null : 'Invalid output filename',
      ),
    );
  }
  final names = <String, int>{};
  for (final row in results) {
    names.update(row.name.toLowerCase(), (n) => n + 1, ifAbsent: () => 1);
  }
  return [
    for (final row in results)
      RenameRow(
        row.path,
        row.name,
        error:
            row.error ??
            (names[row.name.toLowerCase()]! > 1
                ? 'Duplicate output name in this batch'
                : null),
      ),
  ];
}
