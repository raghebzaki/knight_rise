import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

/// Whether the process runs with MSIX package identity.
abstract interface class PackageIdentity {
  /// True when installed from an MSIX package (identity granted by Windows).
  bool get isPackaged;
}

/// A fixed answer, for tests and platforms without package identity.
class FixedPackageIdentity implements PackageIdentity {
  const FixedPackageIdentity({required this.isPackaged});

  @override
  final bool isPackaged;
}

/// `GetCurrentPackageFullName` (kernel32). Windows only: constructed and
/// queried solely by the Windows launch-at-login implementation.
class FfiPackageIdentity implements PackageIdentity {
  const FfiPackageIdentity();

  /// `APPMODEL_ERROR_NO_PACKAGE`: the process has no package identity.
  static const noPackage = 15700;

  /// Classifies a `GetCurrentPackageFullName` result: any code other than
  /// [noPackage] (`ERROR_SUCCESS`, or `ERROR_INSUFFICIENT_BUFFER` for the
  /// zero-length probe) means the process is packaged.
  @visibleForTesting
  static bool isPackagedResult(int code) => code != noPackage;

  /// The identity cannot change during the process lifetime.
  static bool? _cached;

  @override
  bool get isPackaged => _cached ??= _query();

  static bool _query() {
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getName = kernel32
          .lookupFunction<
            Int32 Function(Pointer<Uint32>, Pointer<Utf16>),
            int Function(Pointer<Uint32>, Pointer<Utf16>)
          >('GetCurrentPackageFullName');
      final length = calloc<Uint32>();
      try {
        // A zero-length buffer: ERROR_INSUFFICIENT_BUFFER when packaged.
        return isPackagedResult(getName(length, nullptr));
      } finally {
        calloc.free(length);
      }
    } on Object catch (e) {
      debugPrint('[package-identity] GetCurrentPackageFullName failed: $e');
      return false;
    }
  }
}
