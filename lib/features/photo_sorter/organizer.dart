import 'package:path/path.dart' as p;
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/secure_metadata_store.dart';
import 'rename_plan.dart';
import 'organizer_catalog.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

String organizerAddress(String root, String path, {String? uri}) {
  if (!root.startsWith('content://')) {
    return Uri.file(
      p.posix.normalize(
        p.posix.join(root, path.replaceFirst(RegExp(r'^/+'), '')),
      ),
    ).toString();
  }
  final value = Uri.parse(uri ?? root);
  final parts = value.pathSegments;
  final direct = parts.indexOf('document');
  if (direct >= 0 && uri != null) {
    return '${value.authority}:${parts[direct + 1]}';
  }
  final tree = parts.indexOf('tree');
  if (tree < 0 || tree + 1 >= parts.length) {
    throw const FormatException('Invalid selected folder');
  }
  final id = parts[tree + 1];
  return '${value.authority}:$id${path.isEmpty ? '' : '${id.endsWith(':') ? '' : '/'}${path.replaceFirst(RegExp(r'^/+'), '')}'}';
}

// Persistent data is deliberately separate from transient thumbnail/UI state.
// All paths, labels, reviews and staged decisions use verified protected records.
enum ReviewState { unreviewed, keep, sortLater, deleteCandidate }

class OrganizerFolder {
  const OrganizerFolder(this.root, this.path, this.name);
  final String root, path, name;
  Map<String, dynamic> toJson() => {'root': root, 'path': path, 'name': name};
  factory OrganizerFolder.fromJson(Map<String, dynamic> json) {
    final root = json['root'] as String;
    final path = json['path'] as String;
    final name = json['name'] as String;
    if (root.isEmpty ||
        root.length > 8192 ||
        path.length > 8192 ||
        name.trim().isEmpty ||
        name.length > 80) {
      throw const FormatException('Invalid organizer destination');
    }
    return OrganizerFolder(root, path, name);
  }
}

class PhotoReview {
  const PhotoReview({
    this.state = ReviewState.unreviewed,
    this.rating = 0,
    this.tags = const [],
  });
  final ReviewState state;
  final int rating;
  final List<String> tags;
  Map<String, dynamic> toJson() => {
    'state': state.name,
    'rating': rating,
    'tags': tags,
  };
  factory PhotoReview.fromJson(Map<String, dynamic> json) {
    final state = ReviewState.values.byName(json['state'] as String);
    final rating = json['rating'] as int;
    final tags = List<String>.from(json['tags'] as List);
    if (rating < 0 ||
        rating > 5 ||
        tags.length > 20 ||
        tags.any(
          (s) => s.isEmpty || s.length > 40 || s.codeUnits.any((c) => c < 32),
        )) {
      throw const FormatException('Invalid photo review');
    }
    return PhotoReview(
      state: state,
      rating: rating,
      tags: List.unmodifiable(tags),
    );
  }
}

class OrganizerState {
  OrganizerState({
    this.revision = 0,
    this.selected,
    List<OrganizerFolder> destinations = const [],
    Map<String, Map<String, dynamic>> decisions = const {},
    Map<String, PhotoReview> reviews = const {},
    Map<String, Map<String, dynamic>> fingerprints = const {},
    List<Map<String, dynamic>> previousReviews = const [],
  }) : destinations = List.of(destinations),
       decisions = Map.from(decisions),
       reviews = Map.from(reviews),
       fingerprints = Map.from(fingerprints),
       previousReviews = List.of(previousReviews);
  int revision;
  String? selected;
  final List<OrganizerFolder> destinations;
  final Map<String, Map<String, dynamic>> decisions;
  final Map<String, PhotoReview> reviews;
  final Map<String, Map<String, dynamic>> fingerprints;
  final List<Map<String, dynamic>> previousReviews;
  Map<String, dynamic> toJson() => {
    'version': 2,
    'revision': revision,
    'selected': selected,
    'destinations': destinations.map((d) => d.toJson()).toList(),
    'decisions': decisions,
    'fingerprints': fingerprints,
    'previousReviews': previousReviews,
    'reviews': reviews.map((key, value) => MapEntry(key, value.toJson())),
  };
  OrganizerState clone() => OrganizerState.fromJson(toJson());
  factory OrganizerState.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 && json['version'] != 2) {
      throw const FormatException('Unsupported organizer data version');
    }
    final destinations = (json['destinations'] as List)
        .map(
          (d) => OrganizerFolder.fromJson(Map<String, dynamic>.from(d as Map)),
        )
        .toList();
    final decisions = (json['decisions'] as Map).map(
      (k, v) => MapEntry(k as String, Map<String, dynamic>.from(v as Map)),
    );
    final reviews = (json['reviews'] as Map).map(
      (k, v) => MapEntry(
        k as String,
        PhotoReview.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    );
    final fingerprints = Map<String, dynamic>.from(
      (json['fingerprints'] as Map?) ?? {},
    ).map((k, v) => MapEntry(k, Map<String, dynamic>.from(v as Map)));
    void validateBinding(Map<String, dynamic> value) {
      if (value['identity'] is! String ||
          (value['pending'] != null && value['pending'] is! bool) ||
          (json['version'] == 1 && value['pending'] == true) ||
          (value['pending'] == true
              ? value['sha256'] != null
              : value['sha256'] is! String ||
                    !RegExp(
                      r'^[0-9a-f]{64}$',
                    ).hasMatch(value['sha256'] as String)) ||
          value['size'] is! int ||
          (value['size'] as int) < 0 ||
          value['modified'] is! int) {
        throw const FormatException('Invalid media identity');
      }
    }

    for (final value in fingerprints.values) {
      validateBinding(value);
    }
    final previousReviews = ((json['previousReviews'] as List?) ?? const [])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList();
    if (previousReviews.length > 200) {
      throw const FormatException('Review candidate limit exceeded');
    }
    for (final entry in previousReviews) {
      if (entry['path'] is! String || entry['binding'] is! Map) {
        throw const FormatException('Invalid previous review');
      }
      validateBinding(Map<String, dynamic>.from(entry['binding'] as Map));
      PhotoReview.fromJson(Map<String, dynamic>.from(entry['review'] as Map));
    }
    if (destinations.length > 9 ||
        decisions.length > 200 ||
        reviews.length > 5000) {
      throw const FormatException('Organizer record limit exceeded');
    }
    for (final d in decisions.values) {
      OrganizerFolder.fromJson(Map<String, dynamic>.from(d['folder'] as Map));
      if (d['move'] is! bool ||
          d['name'] is! String ||
          d['version'] is! Map ||
          (d['jobId'] != null && d['jobId'] is! String)) {
        throw const FormatException('Invalid staged decision');
      }
    }
    return OrganizerState(
      revision: (json['revision'] as int?) ?? 0,
      selected: json['selected'] as String?,
      destinations: destinations,
      decisions: decisions,
      reviews: reviews,
      fingerprints: fingerprints,
      previousReviews: previousReviews,
    );
  }
}

class OrganizerRepository {
  OrganizerRepository({SecureMetadataStore Function(String key)? store})
    : _store =
          store ?? ((key) => SecureMetadataStore(key: key, expectMap: true));
  final SecureMetadataStore Function(String key) _store;
  OrganizerCatalog get catalog =>
      OrganizerCatalog(_store('private_metadata_organizer_collections_v1'));

  Future<List<MediaReference>> searchReviewed(CollectionFilter filter) async {
    final value = await _store('private_metadata_organizer_index_v1').read();
    if (value == null) return [];
    final index = jsonDecode(value) as Map;
    if (index['version'] != 1 || index['sessions'] is! Map) {
      throw const FormatException('Invalid organizer index');
    }
    final output = <String, MediaReference>{};
    for (final entry in (index['sessions'] as Map).entries) {
      if (entry.key is! String ||
          !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(entry.key as String)) {
        throw const FormatException('Invalid organizer session identity');
      }
      final location = entry.value as Map;
      final state = await load(
        'private_metadata_organizer_session_${entry.key}',
      );
      for (final review in state.reviews.entries) {
        if (!filter.matches(
          path: review.key,
          state: review.value.state.name,
          rating: review.value.rating,
          tags: review.value.tags,
        )) {
          continue;
        }
        final fingerprint = state.fingerprints[review.key];
        if (fingerprint == null) continue;
        final reference = MediaReference.fromJson({
          ...fingerprint,
          if (fingerprint['pending'] == true) 'sha256': '',
          'root': location['root'],
          'path': review.key,
        });
        output[reference.key] = reference;
      }
    }
    return output.values.toList();
  }

  static const _uiKey = 'private_metadata_organizer_ui_v1';
  static bool _buttonLabels(String? value) {
    if (value == null) return true;
    final json = jsonDecode(value) as Map;
    if (json['version'] != 1 ||
        json['showButtonLabels'] is! bool ||
        (json['confirmDeletion'] != null && json['confirmDeletion'] is! bool)) {
      throw const FormatException('Invalid organizer display preference');
    }
    return json['showButtonLabels'] as bool;
  }

  Future<bool> loadButtonLabels() async =>
      _buttonLabels(await _store(_uiKey).read());

  Future<void> saveButtonLabels(bool value) => _store(_uiKey).update((
    previous,
  ) {
    _buttonLabels(previous); // Refuse to replace invalid protected preferences.
    return jsonEncode({
      ...?previous == null
          ? null
          : jsonDecode(previous) as Map<String, dynamic>,
      'version': 1,
      'showButtonLabels': value,
    });
  });
  Future<bool> loadConfirmDeletion() async {
    final value = await _store(_uiKey).read();
    _buttonLabels(value);
    return value == null
        ? true
        : (jsonDecode(value) as Map)['confirmDeletion'] as bool? ?? true;
  }

  Future<void> saveConfirmDeletion(bool value) =>
      _store(_uiKey).update((previous) {
        final labels = _buttonLabels(previous);
        return jsonEncode({
          ...?previous == null
              ? null
              : jsonDecode(previous) as Map<String, dynamic>,
          'version': 1,
          'showButtonLabels': labels,
          'confirmDeletion': value,
        });
      });

  Future<String> sessionKey(String root, String folder) async {
    String? id;
    final random = Random.secure();
    final fresh = base64Url.encode(
      List.generate(18, (_) => random.nextInt(256)),
    );
    await _store('private_metadata_organizer_index_v1').update((previous) {
      final index = previous == null
          ? <String, dynamic>{'version': 1, 'sessions': <String, dynamic>{}}
          : Map<String, dynamic>.from(jsonDecode(previous) as Map);
      if (index['version'] != 1 || index['sessions'] is! Map) {
        throw const FormatException('Invalid organizer index');
      }
      final sessions = Map<String, dynamic>.from(index['sessions'] as Map);
      for (final entry in sessions.entries) {
        if (!RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(entry.key) ||
            entry.value is! Map) {
          throw const FormatException('Invalid session record');
        }
        final item = entry.value as Map;
        if (item['root'] is! String || item['folder'] is! String) {
          throw const FormatException('Invalid session location');
        }
        if (item['root'] == root && item['folder'] == folder) id = entry.key;
      }
      if (id == null) {
        if (sessions.length >= 128) throw StateError('Session limit reached');
        id = fresh;
        sessions[id!] = {'root': root, 'folder': folder};
      }
      index['sessions'] = sessions;
      return jsonEncode(index);
    });
    return 'private_metadata_organizer_session_$id';
  }

  Future<OrganizerState> load(String key) async {
    final value = await _store(key).read();
    return value == null
        ? OrganizerState()
        : OrganizerState.fromJson(
            Map<String, dynamic>.from(jsonDecode(value) as Map),
          );
  }

  Future<void> save(String key, OrganizerState state) async {
    OrganizerState.fromJson(state.toJson());
    final expected = state.revision;
    await _store(key).update((previous) {
      final stored = previous == null
          ? 0
          : OrganizerState.fromJson(
              Map<String, dynamic>.from(jsonDecode(previous) as Map),
            ).revision;
      if (stored != expected) {
        throw StateError(
          'This session changed in another window. Reopen it before saving.',
        );
      }
      return jsonEncode(state.toJson()..['revision'] = expected + 1);
    });
    state.revision = expected + 1;
  }
}

class OrganizerBridge {
  const OrganizerBridge(this._channel);
  final MethodChannel _channel;
  Future<Uint8List?> referenceThumbnail(
    MediaReference reference, {
    int size = 300,
  }) => _channel.invokeMethod<Uint8List>(ChannelMethods.getImageThumbnail, {
    'filePath': reference.root,
    'fileName': reference.path,
    'isLocalStorage': true,
    'targetSize': size,
    'quality': 70,
  });
  Future<String> chooseFolder({String? path, String? treeUri}) async =>
      (await _channel.invokeMethod<String>('organizerChooseFolder', {
        'path': path,
        'treeUri': treeUri,
      }))!;
  Future<Map<String, dynamic>> prepare(Map<String, dynamic> args) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>(
          'organizerPrepare',
          args,
        ))!,
      );
  Future<List<Map<String, dynamic>>> history() async =>
      (await _channel.invokeListMethod<dynamic>('organizerList') ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  Future<Map<String, dynamic>> execute(String id) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>('organizerExecute', {
          'id': id,
        }))!,
      );
  Future<Map<String, dynamic>> reconcile(String id) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>('organizerReconcile', {
          'id': id,
        }))!,
      );
  Future<Map<String, dynamic>> undo(String id) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>('organizerUndo', {
          'id': id,
        }))!,
      );
  Future<void> cancelAll() async {
    await _channel.invokeMethod<bool>('organizerCancel');
  }

  Future<void> cancel(String id) async {
    await _channel.invokeMethod<bool>('organizerCancel', {'id': id});
  }

  Future<List<int>?> progress(String id) =>
      _channel.invokeListMethod<int>('organizerProgress', {'id': id});
  Future<Map<String, dynamic>> fingerprint(String root, String path) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>(
          'organizerFingerprint',
          {
            'source': {'root': root, 'path': path},
          },
        ))!,
      );
  Future<Map<String, dynamic>> inspect(String root, String path) async =>
      Map<String, dynamic>.from(
        (await _channel.invokeMapMethod<String, dynamic>('organizerInspect', {
          'source': {'root': root, 'path': path},
        }))!,
      );
}

class OrganizerController extends ChangeNotifier {
  OrganizerController({
    required this.root,
    required this.folder,
    required this.photos,
    OrganizerRepository? repository,
    required this.bridge,
  }) : repository = repository ?? OrganizerRepository();
  final String root, folder;
  final List<String> photos;
  final OrganizerRepository repository;
  final OrganizerBridge bridge;
  OrganizerState state = OrganizerState();
  List<Map<String, dynamic>> jobs = [];
  List<Map<String, dynamic>> _allJobs = [];
  final _received = <String>{};
  bool _receiving = false;
  Set<String> _moved = {};
  final _verifiedReviews = <String>{};
  final reviewWarnings = <String, String>{};
  int _openGeneration = 0;
  int? _verifierGeneration;
  bool get verifyingReviews => _verifierGeneration == _openGeneration;
  String? relocationNotice;
  PhotoReview? reviewFor(String path) =>
      _verifiedReviews.contains(path) ? state.reviews[path] : null;

  String? _key, error, activeJob;
  bool ready = false,
      showButtonLabels = true,
      saving = false,
      running = false,
      disposed = false,
      _stop = false;
  List<int>? progress;
  Timer? _progressTimer;
  bool _polling = false;
  String? get key => _key;
  void changed() {
    if (!disposed) notifyListeners();
  }

  Future<void> open({bool verifyContent = true}) async {
    final generation = ++_openGeneration;
    ready = false;
    error = null;
    _stop = false;
    changed();
    try {
      _key = await repository.sessionKey(root, folder);
      final restored = await repository.load(_key!);
      final labels = await repository.loadButtonLabels();
      if (disposed || generation != _openGeneration) return;
      state = restored;
      showButtonLabels = labels;
      await refreshHistory();
      if (disposed || generation != _openGeneration) return;
      ready = true;
      error = null;
      _verifiedReviews.clear();
      reviewWarnings.clear();
      unawaited(verifySavedReviews(verifyContent: verifyContent));
      unawaited(_recoverIncomingReviews());
    } catch (_) {
      error =
          'Protected organizer data is unavailable. Nothing has been overwritten. Retry after unlocking storage.';
    }
    changed();
  }

  Future<bool> edit(void Function(OrganizerState next) update) async {
    if (!ready || saving || running) return false;
    saving = true;
    error = null;
    changed();
    try {
      final selectedBefore = state.selected;
      final next = state.clone();
      update(next);
      await repository.save(_key!, next);
      if (state.selected != selectedBefore) next.selected = state.selected;
      state = next;
      return true;
    } catch (_) {
      error =
          'Could not save protected organizer data. The last saved decisions are retained; no file operation was started.';
      return false;
    } finally {
      saving = false;
      changed();
    }
  }

  Future<void> addDestination(OrganizerFolder destination) async {
    await edit((next) {
      if (next.destinations.length >= 9 ||
          next.destinations.any(
            (d) => d.name.toLowerCase() == destination.name.toLowerCase(),
          )) {
        throw StateError('Choose a unique destination name');
      }
      next.destinations.add(destination);
    });
  }

  Future<void> setButtonLabels(bool value) async {
    if (!ready || saving || running) return;
    saving = true;
    error = null;
    changed();
    try {
      await repository.saveButtonLabels(value);
      showButtonLabels = value;
    } catch (_) {
      error =
          'Could not save button labels. Your previous setting is retained.';
    } finally {
      saving = false;
      changed();
    }
  }

  Future<bool> stage(
    List<String> paths,
    OrganizerFolder destination, {
    required bool move,
    String? nextSelected,
    Map<String, String>? outputNames,
    Map<String, Map<String, dynamic>>? expectedVersions,
  }) async {
    if (saving || running || !ready) return false;
    if (move && root.startsWith('content://')) {
      error =
          'This source supports verified copies only. Android cannot provide recoverable Trash for it.';
      changed();
      return false;
    }
    // Capture identity at the decision, not just when Commit is pressed.
    saving = true;
    error = null;
    changed();
    try {
      final selectedBefore = state.selected;
      final next = state.clone();
      for (final path in paths) {
        final version = await bridge.inspect(root, path);
        final expected = expectedVersions?[path];
        if (expectedVersions != null && expected == null) {
          error =
              'Refresh the rename preview before staging all selected files.';
          return false;
        }
        if (expected != null &&
            (version['identity'] != expected['identity'] ||
                version['size'] != expected['size'] ||
                version['modified'] != expected['modified'])) {
          error =
              'A source changed after the rename preview. Refresh the preview before staging.';
          return false;
        }
        final name = outputNames?[path] ?? path.split('/').last;
        if (!validOrganizerName(name)) {
          error = 'The rename preview contains an invalid filename.';
          return false;
        }
        if (move && version['canMove'] == false) {
          error =
              'This source folder supports verified copies only. Stage a copy instead.';
          return false;
        }
        next.decisions[path] = {
          'folder': destination.toJson(),
          'move': move,
          'name': name,
          'version': version,
        };
      }
      if (next.decisions.length > 200) {
        throw StateError('Commit a smaller batch');
      }
      final outputs = <String>{};
      for (final decision in next.decisions.values) {
        final folder = OrganizerFolder.fromJson(
          Map<String, dynamic>.from(decision['folder'] as Map),
        );
        final address = organizerAddress(
          folder.root,
          p.posix.join(folder.path, decision['name'] as String),
        ).toLowerCase();
        if (!outputs.add(address)) {
          error =
              'Two staged photographs have the same destination filename. Change their output names.';
          return false;
        }
      }
      next.selected = nextSelected;
      await repository.save(_key!, next);
      if (state.selected != selectedBefore) next.selected = state.selected;
      state = next;
      return true;
    } catch (_) {
      error =
          'Could not safely stage these files. Check source access, destination and protected storage.';
      return false;
    } finally {
      saving = false;
      changed();
    }
  }

  Future<void> select(String? path) async {
    state.selected = path;
  }

  Future<void> saveSelection() async {
    if (!ready || saving || running) return;
    await edit((next) => next.selected = state.selected);
  }

  Future<void> clearDecision(String path) async {
    await edit((next) => next.decisions.remove(path));
  }

  static bool sameMediaVersion(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) =>
      a['identity'] == b['identity'] &&
      a['size'] == b['size'] &&
      a['modified'] == b['modified'];

  /// Immediate metadata editing does not read an entire multi-gigabyte video.
  /// Identity-only bindings stay at this path until content verification; they
  /// never become automatic relocation matches without a full hash.
  Future<bool> updateReview(
    List<String> paths,
    PhotoReview Function(PhotoReview) update,
  ) async {
    if (!ready || saving || running || disposed || paths.isEmpty) return false;
    saving = true;
    error = null;
    changed();
    try {
      final next = state.clone();
      for (final path in paths) {
        final found = await bridge.inspect(root, path);
        final old = next.fingerprints[path];
        final same = old != null && sameMediaVersion(old, found);
        final previous = next.reviews[path];
        if (!same && old != null && previous != null) {
          next.previousReviews.add({
            'path': path,
            'review': previous.toJson(),
            'binding': Map.of(old),
          });
        }
        final review = update(
          same && previous != null ? previous : const PhotoReview(),
        );
        PhotoReview.fromJson(review.toJson());
        next.reviews[path] = review;
        next.fingerprints[path] = same
            ? Map.of(old)
            : {...found, 'pending': true};
        next.decisions[path]?.remove('jobId');
      }
      await repository.save(_key!, next);
      next.selected = state.selected;
      state = next;
      _verifiedReviews.addAll(paths);
      for (final path in paths) {
        reviewWarnings.remove(path);
      }
      return true;
    } catch (_) {
      error = 'Could not save the review. Previous saved reviews are retained.';
      return false;
    } finally {
      saving = false;
      changed();
    }
  }

  Future<bool> setRating(List<String> paths, int rating) => updateReview(
    paths,
    (old) => PhotoReview(state: old.state, rating: rating, tags: old.tags),
  );
  Future<bool> setTags(List<String> paths, List<String> tags) => updateReview(
    paths,
    (old) => PhotoReview(state: old.state, rating: old.rating, tags: tags),
  );

  Future<bool> review(List<String> paths, PhotoReview review) async {
    if (!ready || saving || running || disposed) return false;
    saving = true;
    error = null;
    changed();
    try {
      final versions = <String, Map<String, dynamic>>{};
      for (final path in paths) {
        versions[path] = await bridge.fingerprint(root, path);
      }
      return await _saveBoundReview(paths, review, versions);
    } catch (_) {
      error =
          'Could not verify these files or save protected review data. The previous review is retained.';
      return false;
    } finally {
      saving = false;
      changed();
    }
  }

  Future<bool> _saveBoundReview(
    List<String> paths,
    PhotoReview review,
    Map<String, Map<String, dynamic>> versions,
  ) async {
    final selectedBefore = state.selected;
    final next = state.clone();
    for (final path in paths) {
      next.reviews[path] = review;
      next.fingerprints[path] = versions[path]!;
      next.decisions[path]?.remove(
        'jobId',
      ); // A fresh preview captures the updated review metadata.
    }
    await repository.save(_key!, next);
    if (state.selected != selectedBefore) next.selected = state.selected;
    state = next;
    _verifiedReviews.addAll(paths);
    for (final path in paths) {
      reviewWarnings.remove(path);
    }
    return true;
  }

  /// Exact filesystem identity AND full content are required for an automatic
  /// within-folder rename match. Hash-only/ambiguous candidates remain unbound.
  Future<void> verifySavedReviews({bool verifyContent = true}) async {
    if (!ready || disposed || running || saving || verifyingReviews) return;
    final generation = _openGeneration;
    _verifierGeneration = generation;
    changed();
    try {
      final bindings = state.fingerprints.entries.toList();
      final missing = bindings
          .where(
            (entry) =>
                !photos.contains(entry.key) && !_moved.contains(entry.key),
          )
          .toList();
      var count = 0;
      for (final entry in bindings.where(
        (entry) => photos.contains(entry.key),
      )) {
        if (disposed ||
            running ||
            saving ||
            _stop ||
            generation != _openGeneration) {
          return;
        }
        try {
          final pending = entry.value['pending'] == true || !verifyContent;
          final found = pending
              ? await bridge.inspect(root, entry.key)
              : await bridge.fingerprint(root, entry.key);
          if (disposed || generation != _openGeneration) return;
          if (pending
              ? sameMediaVersion(found, entry.value)
              : found['identity'] == entry.value['identity'] &&
                    found['sha256'] == entry.value['sha256']) {
            _verifiedReviews.add(entry.key);
            reviewWarnings.remove(entry.key);
          } else {
            _verifiedReviews.remove(entry.key);
            reviewWarnings[entry.key] =
                'File changed; saved review is a candidate, not an identity match.';
          }
        } catch (_) {
          _verifiedReviews.remove(entry.key);
          reviewWarnings[entry.key] =
              'Saved review cannot be verified while storage is unavailable.';
        }
        if (++count % 8 == 0) changed();
      }
      for (final path in state.reviews.keys.where(
        (path) => !state.fingerprints.containsKey(path),
      )) {
        reviewWarnings[path] =
            'Earlier review has no verified identity. Reapply it explicitly if appropriate.';
      }
      if (missing.isEmpty) return;
      if (!verifyContent) {
        return; // Viewer navigation never starts a relocation scan.
      }
      final candidates = <String, List<String>>{};
      for (final path in photos.where(
        (path) => !state.reviews.containsKey(path),
      )) {
        if (disposed ||
            running ||
            saving ||
            _stop ||
            generation != _openGeneration) {
          return;
        }
        try {
          final found = await bridge.inspect(root, path);
          if (disposed || generation != _openGeneration) return;
          candidates
              .putIfAbsent(found['identity'] as String, () => [])
              .add(path);
        } catch (_) {
          // Inaccessible files cannot become automatic identity matches; keep
          // the original review as an unresolved candidate without path logs.
        }
      }
      for (final entry in missing) {
        if (disposed ||
            running ||
            saving ||
            _stop ||
            generation != _openGeneration) {
          return;
        }
        if (entry.value['pending'] == true) {
          reviewWarnings[entry.key] =
              'Saved review retained at its former path. Content verification is required before relocation.';
          continue;
        }
        final identity = entry.value['identity'];
        final oldMatches = missing
            .where((other) => other.value['identity'] == identity)
            .length;
        final newMatches = candidates[identity] ?? const <String>[];
        if (oldMatches != 1 || newMatches.length != 1) {
          reviewWarnings[entry.key] =
              'No unique identity match in this folder. Saved review retained for reconciliation.';
          continue;
        }
        final path = newMatches.single;
        try {
          final found = await bridge.fingerprint(root, path);
          if (disposed || generation != _openGeneration) return;
          if (found['identity'] != identity ||
              found['sha256'] != entry.value['sha256']) {
            continue;
          }
          final note = state.reviews[entry.key];
          if (note == null) continue;
          final migrated = await edit((next) {
            next.reviews.remove(entry.key);
            next.fingerprints.remove(entry.key);
            next.reviews[path] = note;
            next.fingerprints[path] = {...found, 'previousPath': entry.key};
            final decision = next.decisions.remove(entry.key);
            if (decision != null) {
              decision.remove('jobId');
              decision['version'] = found;
              next.decisions[path] = decision;
            }
            if (next.selected == entry.key) next.selected = path;
          });
          if (migrated) {
            _verifiedReviews.add(path);
            reviewWarnings.remove(entry.key);
            relocationNotice =
                'Recovered a review after a verified rename: ${entry.key} → $path. Staged plans must be checked again.';
          }
        } catch (_) {
          reviewWarnings[entry.key] =
              'Rename candidate could not be verified. Nothing was reassigned.';
        }
      }
    } finally {
      if (_verifierGeneration == generation) _verifierGeneration = null;
      changed();
    }
  }

  Future<void> refreshHistory() async {
    final all = await bridge.history();
    _allJobs = all;
    jobs = all.where((j) {
      final source = j['source'] as Map;
      return source['root'] == root &&
          (source['path'] as String)
                  .split('/')
                  .take((source['path'] as String).split('/').length - 1)
                  .join('/') ==
              folder;
    }).toList();
    _moved = jobs
        .where((j) => j['state'] == 'complete' && j['move'] == true)
        .map((j) => (j['source'] as Map)['path'] as String)
        .toSet();
    jobs.sort(
      (a, b) => ((b['createdAt'] as num?)?.toInt() ?? 0).compareTo(
        (a['createdAt'] as num?)?.toInt() ?? 0,
      ),
    );
    changed();
  }

  Future<void> _recoverIncomingReviews() async {
    if (_receiving || !ready || disposed || running || saving) return;
    _receiving = true;
    final generation = _openGeneration;
    final addresses = <String, List<String>>{};
    for (final path in photos) {
      addresses.putIfAbsent(organizerAddress(root, path), () => []).add(path);
    }
    try {
      for (final job in _allJobs) {
        if (disposed || running || saving) break;
        final id = job['id'] as String;
        if (_received.contains(id) ||
            job['state'] != 'complete' ||
            job['annotation'] is! String ||
            job['created'] is! Map) {
          continue;
        }
        final target = job['created'] as Map;
        final address = organizerAddress(
          target['root'] as String,
          target['path'] as String,
          uri: target['uri'] as String?,
        );
        final matches = addresses[address] ?? const <String>[];
        if (matches.length != 1 || state.reviews.containsKey(matches.single)) {
          continue;
        }
        try {
          final found = await bridge.fingerprint(root, matches.single);
          if (disposed || generation != _openGeneration) return;
          if (found['identity'] != job['createdIdentity'] ||
              found['sha256'] != job['sha256']) {
            continue;
          }
          final note = PhotoReview.fromJson(
            Map<String, dynamic>.from(
              jsonDecode(job['annotation'] as String) as Map,
            ),
          );
          if (!running && !saving) {
            saving = true;
            try {
              if (await _saveBoundReview(matches, note, {
                matches.single: found,
              })) {
                _received.add(id);
              }
            } finally {
              saving = false;
              changed();
            }
          }
        } catch (_) {
          /* Keep the authenticated journal annotation for a later retry. */
        }
      }
    } finally {
      _receiving = false;
    }
  }

  Future<bool> prepare() async {
    if (!ready || running || saving) return false;
    running = true;
    error = null;
    _stop = false;
    changed();
    try {
      final next = state.clone();
      for (final entry in next.decisions.entries) {
        if (_stop) break;
        if (entry.value['jobId'] != null) continue;
        final d = entry.value;
        final binding = next.fingerprints[entry.key];
        if (binding?['pending'] == true &&
            next.reviews.containsKey(entry.key)) {
          final found = await bridge.fingerprint(root, entry.key);
          if (!sameMediaVersion(binding!, found)) {
            throw StateError('Review source changed before transfer');
          }
          next.fingerprints[entry.key] = found;
          _verifiedReviews.add(entry.key);
        }
        final folder = OrganizerFolder.fromJson(
          Map<String, dynamic>.from(d['folder'] as Map),
        );
        final job = await bridge.prepare({
          'source': {'root': root, 'path': entry.key},
          'directory': {'root': folder.root, 'path': folder.path},
          'name': d['name'],
          'move': d['move'],
          'expected': d['version'],
          'annotation': reviewFor(entry.key)?.toJson(),
          'annotationHash': next.fingerprints[entry.key]?['sha256'],
        });
        d['jobId'] = job['id'];
        // Every returned plan already has a protected native journal. Persist the
        // linkage before preparing the next row so a restart cannot hide it.
        await repository.save(_key!, next);
        state = next.clone();
      }
      await refreshHistory();
      return !_stop &&
          state.decisions.isNotEmpty &&
          state.decisions.values.every((d) => d['jobId'] != null);
    } catch (_) {
      error =
          'Preview stopped: a collision, changed source, unavailable storage or unsupported move needs attention. Originals were not moved.';
      return false;
    } finally {
      running = false;
      changed();
    }
  }

  Future<void> commit() async {
    if (!ready ||
        running ||
        saving ||
        state.decisions.isEmpty ||
        state.decisions.values.any((d) => d['jobId'] == null)) {
      return;
    }
    await runJobs(
      state.decisions.values.map((d) => d['jobId'] as String).toList(),
    );
  }

  Future<void> runJobs(List<String> ids) async {
    if (running || saving || !ready) return;
    running = true;
    _stop = false;
    error = null;
    changed();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      if (_polling || activeJob == null || disposed) return;
      _polling = true;
      try {
        progress = await bridge.progress(activeJob!);
        changed();
      } catch (_) {
        // Progress is advisory. The awaited native result and durable journal
        // determine success; a failed poll must never trigger a file retry.
      } finally {
        _polling = false;
      }
    });
    try {
      for (final id in ids) {
        if (_stop || disposed) break;
        activeJob = id;
        changed();
        final job = await bridge.execute(id);
        if (job['state'] != 'complete') {
          error =
              'Transfer paused. The original and any recorded output are retained. Review history before resuming.';
          break;
        }
        final next = state.clone();
        next.decisions.removeWhere((_, d) => d['jobId'] == id);
        await repository.save(_key!, next);
        state = next;
        final existing = jobs.indexWhere((j) => j['id'] == job['id']);
        if (existing >= 0) {
          jobs[existing] = job;
        } else {
          jobs.add(job);
        }
        _moved = jobs
            .where((j) => j['state'] == 'complete' && j['move'] == true)
            .map((j) => (j['source'] as Map)['path'] as String)
            .toSet();
        changed();
      }
    } catch (_) {
      error =
          'Transfer stopped. Reopen the queue to reconcile the protected operation journal; do not delete partial files.';
    } finally {
      activeJob = null;
      running = false;
      progress = null;
      _progressTimer?.cancel();
      try {
        await refreshHistory();
      } catch (_) {
        error =
            'Protected operation history could not be read. Stop and check storage.';
      }
      changed();
    }
  }

  Future<void> reconcile(String id) async {
    if (running || saving || !ready) return;
    running = true;
    activeJob = id;
    error = null;
    changed();
    try {
      await bridge.reconcile(id);
    } catch (_) {
      error = 'Recovery verification stopped. All recorded files are retained.';
    } finally {
      running = false;
      activeJob = null;
      try {
        await refreshHistory();
      } catch (_) {
        error = 'Protected history is unavailable.';
      }
      changed();
    }
  }

  Future<void> undo(String id) async {
    if (running || saving || !ready) return;
    running = true;
    activeJob = id;
    error = null;
    changed();
    try {
      await bridge.undo(id);
    } catch (_) {
      error =
          'Undo refused or paused: a file changed, a name is occupied, or safe Trash is unavailable. Inspect history; nothing is permanently deleted.';
    } finally {
      activeJob = null;
      running = false;
      try {
        await refreshHistory();
      } catch (_) {
        error =
            'Protected operation history is unavailable. Stop and check storage.';
      }
      changed();
    }
  }

  Future<void> renameDecision(String path, String name) async {
    final valid = validOrganizerName(name);
    if (!valid) {
      error =
          'Choose a filename without path separators or reserved characters.';
      changed();
      return;
    }
    await edit((next) {
      final decision = next.decisions[path];
      if (decision != null) {
        decision['name'] = name;
        decision.remove('jobId');
      }
    });
  }

  void pause() {
    _stop = true;
    final id = activeJob;
    if (id != null) {
      unawaited(bridge.cancel(id).catchError((Object _) {}));
    } else {
      unawaited(bridge.cancelAll().catchError((Object _) {}));
    }
  }

  Set<String> get moved => Set.unmodifiable(_moved);
  bool matches(
    String path,
    String query,
    ReviewState? filter,
    int minimumRating,
  ) {
    final note = reviewFor(path) ?? const PhotoReview();
    return !_moved.contains(path) &&
        (filter == null || note.state == filter) &&
        note.rating >= minimumRating &&
        (query.trim().isEmpty ||
            ('$path ${note.tags.join(' ')}').toLowerCase().contains(
              query.trim().toLowerCase(),
            ));
  }

  @override
  void dispose() {
    pause();
    disposed = true;
    _progressTimer?.cancel();
    super.dispose();
  }
}
