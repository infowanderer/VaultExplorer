import 'dart:convert';
import 'dart:math';
import 'package:vaultexplorer/data/services/secure_metadata_store.dart';

/// A location is a reference, never an instruction to relocate or delete media.
class MediaReference {
  const MediaReference({
    required this.root,
    required this.path,
    required this.identity,
    required this.sha256,
    required this.size,
    required this.modified,
    this.pending = false,
  });
  final String root, path, identity, sha256;
  final int size, modified;
  final bool pending;
  String get key => jsonEncode([root, path]);
  Map<String, dynamic> toJson() => {
    'root': root,
    'path': path,
    'identity': identity,
    'sha256': sha256,
    'size': size,
    'modified': modified,
    'pending': pending,
  };
  factory MediaReference.fromJson(Map<String, dynamic> value) {
    final item = MediaReference(
      root: value['root'] as String,
      path: value['path'] as String,
      identity: value['identity'] as String,
      sha256: value['sha256'] as String,
      size: value['size'] as int,
      modified: value['modified'] as int,
      pending: value['pending'] == true,
    );
    if ((value['pending'] != null && value['pending'] is! bool) ||
        item.root.isEmpty ||
        item.root.length > 8192 ||
        item.path.isEmpty ||
        item.path.length > 8192 ||
        item.path.split('/').any((part) => part == '..' || part == '.') ||
        item.path.contains('\u0000') ||
        item.identity.isEmpty ||
        item.identity.length > 8192 ||
        item.size < 0 ||
        (item.pending
            ? item.sha256.isNotEmpty
            : !RegExp(r'^[a-f0-9]{64}$').hasMatch(item.sha256))) {
      throw const FormatException('Invalid collection media reference');
    }
    return item;
  }
  bool matches(Map<String, dynamic> version) =>
      version['identity'] == identity &&
      version['size'] == size &&
      (pending ? version['modified'] == modified : version['sha256'] == sha256);
}

class CollectionFilter {
  const CollectionFilter({
    this.query = '',
    this.reviewState,
    this.minimumRating = 0,
  });
  final String query;
  final String? reviewState;
  final int minimumRating;
  Map<String, dynamic> toJson() => {
    'query': query,
    'reviewState': reviewState,
    'minimumRating': minimumRating,
  };
  factory CollectionFilter.fromJson(Map<String, dynamic> value) {
    final filter = CollectionFilter(
      query: value['query'] as String,
      reviewState: value['reviewState'] as String?,
      minimumRating: value['minimumRating'] as int,
    );
    if (filter.query.length > 500 ||
        filter.minimumRating < 0 ||
        filter.minimumRating > 5 ||
        (filter.reviewState != null &&
            ![
              'unreviewed',
              'keep',
              'sortLater',
              'deleteCandidate',
            ].contains(filter.reviewState))) {
      throw const FormatException('Invalid saved search');
    }
    return filter;
  }
  bool matches({
    required String path,
    required String state,
    required int rating,
    required List<String> tags,
  }) =>
      rating >= minimumRating &&
      (reviewState == null || reviewState == state) &&
      (query.trim().isEmpty ||
          '$path ${tags.join(' ')}'.toLowerCase().contains(
            query.trim().toLowerCase(),
          ));
}

class OrganizerCollection {
  const OrganizerCollection({
    required this.id,
    required this.name,
    this.members = const [],
    this.filter,
  });
  final String id, name;
  final List<MediaReference> members;
  final CollectionFilter? filter;
  bool get isSearch => filter != null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'members': members.map((m) => m.toJson()).toList(),
    'filter': filter?.toJson(),
  };
  factory OrganizerCollection.fromJson(Map<String, dynamic> value) {
    final item = OrganizerCollection(
      id: value['id'] as String,
      name: value['name'] as String,
      members: List.unmodifiable(
        (value['members'] as List).map(
          (m) => MediaReference.fromJson(Map<String, dynamic>.from(m as Map)),
        ),
      ),
      filter: value['filter'] == null
          ? null
          : CollectionFilter.fromJson(
              Map<String, dynamic>.from(value['filter'] as Map),
            ),
    );
    if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(item.id) ||
        !validCollectionName(item.name) ||
        item.members.length > 500 ||
        item.members.map((m) => m.key).toSet().length != item.members.length ||
        (item.filter != null && item.members.isNotEmpty)) {
      throw const FormatException('Invalid collection');
    }
    return item;
  }
}

bool validCollectionName(String value) =>
    value.trim().isNotEmpty &&
    value.length <= 80 &&
    !value.codeUnits.any((c) => c < 32);

/// Bounded, encrypted collection metadata. No dependency on filesystem operations.
class OrganizerCatalog {
  OrganizerCatalog(this.store);
  final SecureMetadataStore store;
  static List<OrganizerCollection> _parse(String? value) {
    if (value == null) return [];
    final data = jsonDecode(value) as Map;
    if (data['version'] != 1 || data['collections'] is! List) {
      throw const FormatException('Unsupported collection catalog');
    }
    final items = (data['collections'] as List)
        .map(
          (c) =>
              OrganizerCollection.fromJson(Map<String, dynamic>.from(c as Map)),
        )
        .toList();
    if (items.length > 32 ||
        items.map((c) => c.id).toSet().length != items.length ||
        items.map((c) => c.name.toLowerCase()).toSet().length != items.length ||
        items.fold<int>(0, (n, c) => n + c.members.length) > 1000) {
      throw const FormatException('Collection catalog limit exceeded');
    }
    return items;
  }

  Future<List<OrganizerCollection>> list() async =>
      _parse(await store.read())
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  Future<void> _change(void Function(List<OrganizerCollection>) update) =>
      store.update((previous) {
        final items = _parse(previous);
        update(items);
        final next = jsonEncode({
          'version': 1,
          'collections': items.map((c) => c.toJson()).toList(),
        });
        _parse(
          next,
        ); // Verify bounds and identity before protected publication.
        return next;
      });
  Future<String> create(
    String name, {
    List<MediaReference> members = const [],
    CollectionFilter? filter,
  }) async {
    final random = Random.secure();
    final id = base64Url.encode(List.generate(18, (_) => random.nextInt(256)));
    await _change(
      (items) => items.add(
        OrganizerCollection(
          id: id,
          name: name.trim(),
          members: members,
          filter: filter,
        ),
      ),
    );
    return id;
  }

  Future<void> addMembers(String id, List<MediaReference> additions) =>
      _change((items) {
        final i = items.indexWhere((c) => c.id == id);
        if (i < 0 || items[i].isSearch) {
          throw StateError('Choose an existing static collection');
        }
        final old = items[i];
        final members = {
          for (final m in old.members) m.key: m,
          for (final m in additions) m.key: m,
        };
        items[i] = OrganizerCollection(
          id: old.id,
          name: old.name,
          members: members.values.toList(),
        );
      });
  Future<void> rename(String id, String name) => _change((items) {
    final i = items.indexWhere((c) => c.id == id);
    if (i < 0) throw StateError('Collection no longer exists');
    final old = items[i];
    items[i] = OrganizerCollection(
      id: id,
      name: name.trim(),
      members: old.members,
      filter: old.filter,
    );
  });
  Future<void> removeMember(String id, String key) => _change((items) {
    final i = items.indexWhere((c) => c.id == id);
    if (i < 0) throw StateError('Collection no longer exists');
    final old = items[i];
    items[i] = OrganizerCollection(
      id: id,
      name: old.name,
      members: old.members.where((m) => m.key != key).toList(),
      filter: old.filter,
    );
  });
  Future<void> remove(String id) =>
      _change((items) => items.removeWhere((c) => c.id == id));
}
