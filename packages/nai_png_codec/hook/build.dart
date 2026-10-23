import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    try {
      await CBuilder.library(
        name: 'nai_png_codec',
        assetName: 'nai_png_codec.dart',
        sources: [
          'src/nai_png_codec.c',
          'src/vendor/libspng/spng.c',
          'src/vendor/miniz/miniz.c',
          'src/vendor/miniz/miniz_tdef.c',
          'src/vendor/miniz/miniz_tinfl.c',
        ],
        includes: ['src', 'src/vendor/libspng', 'src/vendor/miniz'],
        defines: {
          'SPNG_STATIC': null,
          'SPNG_USE_MINIZ': null,
          'MINIZ_NO_ARCHIVE_APIS': null,
          'MINIZ_NO_STDIO': null,
          'MINIZ_NO_TIME': null,
        },
      ).run(input: input, output: output);
    } catch (e) {
      final fallbackDll =
          File('D:/AI/nai/NAI_Launcher_Windows_4.3.0+45_Portable/nai_png_codec.dll');
      if (fallbackDll.existsSync()) {
        final targetFile =
            File.fromUri(input.outputDirectory.resolve('nai_png_codec.dll'));
        await targetFile.parent.create(recursive: true);
        await fallbackDll.copy(targetFile.path);
        output.assets.code.add(
          CodeAsset(
            package: input.packageName,
            name: 'nai_png_codec.dart',
            file: targetFile.uri,
            linkMode: DynamicLoadingBundled(),
          ),
        );
      } else {
        rethrow;
      }
    }
  });
}
