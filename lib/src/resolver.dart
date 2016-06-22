library coverage.resolver;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// [Resolver] resolves imports with respect to a given environment.
class Resolver {
  final String packageRoot;
  final String sdkRoot;
  final List<String> failed = [];

  Resolver({this.packageRoot, this.sdkRoot});

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(String scriptUri) {
    var uri = Uri.parse(scriptUri);
    if (uri.scheme == 'dart') {
      if (sdkRoot == null) {
        // No sdk-root given, do not resolve dart: URIs.
        return null;
      }
      var filePath;
      if (uri.pathSegments.length > 1) {
        var path = uri.pathSegments[0];
        // Drop patch files, since we don't have their source in the compiled
        // SDK.
        if (path.endsWith('-patch')) {
          failed.add('$uri');
          return null;
        }
        // Canonicalize path. For instance: _collection-dev => _collection_dev.
        path = path.replaceAll('-', '_');
        var pathSegments = [sdkRoot, path]
            ..addAll(uri.pathSegments.sublist(1));
        filePath = p.joinAll(pathSegments);
      } else {
        // Resolve 'dart:something' to be something/something.dart in the SDK.
        var lib = uri.path;
        filePath = p.join(sdkRoot, lib, '$lib.dart');
      }
      return resolveSymbolicLinks(filePath);
    }
    if (uri.scheme == 'package') {
      if (packageRoot == null) {
        // No package-root given, do not resolve package: URIs.
        return null;
      }
      return resolveSymbolicLinks(p.join(packageRoot, uri.path));
    }
    if (uri.scheme == 'file') {
      return resolveSymbolicLinks(p.fromUri(uri));
    }
    // We cannot deal with anything else.
    failed.add('$uri');
    return null;
  }

  /// Returns a canonicalized path, or `null` if the path cannot be resolved.
  String resolveSymbolicLinks(String path) {
    var normalizedPath = p.normalize(path);
    var type = FileSystemEntity.typeSync(normalizedPath, followLinks: true);
    if (type == FileSystemEntityType.NOT_FOUND) return null;
    return new File(normalizedPath).resolveSymbolicLinksSync();
  }
}

/// Bazel URI resolver.
class BazelResolver extends Resolver {
  final List<String> failed = [];
  final String workspacePath;

  /// Creates a Bazel resolver with the specified workspace path, if any.
  BazelResolver({this.workspacePath: ''});

  /// Returns the absolute path wrt. to the given environment or null, if the
  /// import could not be resolved.
  String resolve(String scriptUri) {
    var uri = Uri.parse(scriptUri);
    if (uri.scheme == 'dart') {
      // Ignore the SDK
      return null;
    }
    if (uri.scheme == 'package') {
      // TODO(cbracken) belongs in a Bazel package
      return _resolveBazelPackage(uri.pathSegments);
    }
    if (uri.scheme == 'file') {
      var runfilesPathSegment = '.runfiles/$workspacePath';
      runfilesPathSegment =
          runfilesPathSegment.replaceAll(new RegExp(r'/*$'), '/');
      var runfilesPos = uri.path.indexOf(runfilesPathSegment);
      if (runfilesPos >= 0) {
        int pathStart = runfilesPos + runfilesPathSegment.length;
        return uri.path.substring(pathStart);
      }
      return null;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return _extractHttpPath(uri);
    }
    // We cannot deal with anything else.
    failed.add('$uri');
    return null;
  }

  String _extractHttpPath(Uri uri) {
    int packagesPos = uri.pathSegments.indexOf('packages');
    if (packagesPos >= 0) {
      var workspacePath = uri.pathSegments.sublist(packagesPos + 1);
      return _resolveBazelPackage(workspacePath);
    }
    return uri.pathSegments.join('/');
  }

  String _resolveBazelPackage(List<String> pathSegments) {
    // TODO(cbracken) belongs in a Bazel package
    var packageName = pathSegments[0];
    var pathInPackage = pathSegments.sublist(1).join('/');
    var packagePath;
    if (packageName.contains('.')) {
      packagePath = packageName.replaceAll('.', '/');
    } else {
      packagePath = 'third_party/dart/$packageName';
    }
    return '$packagePath/lib/$pathInPackage';
  }
}

/// Loads the lines of imported resources.
class Loader {
  final List<String> failed = [];

  /// Loads an imported resource and returns a [Future] with a [List] of lines.
  /// Returns [null] if the resource could not be loaded.
  Future<List<String>> load(String path) async {
    try {
      return new File(path).readAsLines();
    } catch (_) {
      failed.add(path);
      return null;
    }
  }
}
