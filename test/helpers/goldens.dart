import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the app's bundled fonts so goldens show real text, not Ahem boxes.
Future<void> loadAppFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('Inter', ['assets/fonts/Inter-Variable.ttf']);
  await load('Rajdhani', [
    'assets/fonts/Rajdhani-Medium.ttf',
    'assets/fonts/Rajdhani-SemiBold.ttf',
    'assets/fonts/Rajdhani-Bold.ttf',
  ]);
  await load('Orbitron', ['assets/fonts/Orbitron-Variable.ttf']);
}

/// Accepts up to [tolerance] (fraction of pixels) of difference, so GPU
/// anti-aliasing noise does not fail a golden. Install in `setUpAll`.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile, {this.tolerance = 0.005});

  final double tolerance;

  static void install({double tolerance = 0.005}) {
    final base = (goldenFileComparator as LocalFileComparator).basedir;
    goldenFileComparator = TolerantGoldenComparator(base.resolve('golden_test.dart'), tolerance: tolerance);
  }

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(imageBytes, await getGoldenBytes(golden));
    if (result.passed || result.diffPercent <= tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}
