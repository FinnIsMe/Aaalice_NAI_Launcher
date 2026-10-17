import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_logger.dart';

class VolcengineTranslator {
  VolcengineTranslator._();

  static final VolcengineTranslator instance = VolcengineTranslator._();

  static const String _service = "translate";
  static const String _region = "cn-north-1";
  static const String _host = "open.volcengineapi.com";
  static const String _action = "TranslateText";
  static const String _version = "2020-06-01";
  static const String _contentType = "application/json";

  final Dio _dio = Dio();
  final Map<String, String> _cache = {};
  bool _cacheLoaded = false;
  File? _cacheFile;

  String? getCached(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    _ensureCacheLoaded();
    return _cache[clean.toLowerCase()];
  }

  String? _accessKeyId;
  String? _secretAccessKey;

  void _ensureCredentialsLoaded() {
    if (_accessKeyId != null && _secretAccessKey != null) return;

    // 1. Try environment variables
    final envAk = Platform.environment['VOLC_ACCESS_KEY_ID'];
    final envSk = Platform.environment['VOLC_SECRET_ACCESS_KEY'];
    if (envAk != null &&
        envAk.isNotEmpty &&
        envSk != null &&
        envSk.isNotEmpty) {
      _accessKeyId = envAk;
      _secretAccessKey = envSk;
      return;
    }

    // 2. Try loading from E:\dsh workspace\manga-image-translator\.env
    for (final envPath in [
      r'E:\dsh workspace\manga-image-translator\.env',
      p.join(Directory.current.path, '.env'),
    ]) {
      final f = File(envPath);
      if (f.existsSync()) {
        try {
          final lines = f.readAsLinesSync();
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('VOLC_ACCESS_KEY_ID=')) {
              _accessKeyId = trimmed.substring('VOLC_ACCESS_KEY_ID='.length).trim();
            } else if (trimmed.startsWith('VOLC_SECRET_ACCESS_KEY=')) {
              _secretAccessKey =
                  trimmed.substring('VOLC_SECRET_ACCESS_KEY='.length).trim();
            }
          }
          if (_accessKeyId != null && _secretAccessKey != null) return;
        } catch (_) {}
      }
    }

    // 3. Fallback to runtime-decoded credentials
    try {
      _accessKeyId = utf8.decode(
        base64Decode('QUtMVE1HWTJaV00yTXpJeVlURmhOR1ZtTUdFeU5XVmhaV0poWlRoaE5EZGtNek0='),
      );
      _secretAccessKey = utf8.decode(
        base64Decode('VFRKVmVscFVWVE5PZW1NMVdUSlplazVIUlRKUFYwVXpXbGROZWsxSFRtcGFSRmw1VDFkYWJFMXFhdz09'),
      );
    } catch (e) {
      AppLogger.w('Failed to decode Volcengine credentials: $e', 'VolcengineTranslator');
    }
  }

  void _ensureCacheLoaded() {
    if (_cacheLoaded) return;
    _cacheLoaded = true;
    try {
      final cachePath = _resolveProjectCachePath();
      _cacheFile = File(cachePath);
      if (_cacheFile!.existsSync()) {
        final content = _cacheFile!.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final decoded = jsonDecode(content);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              _cache[entry.key.toString().toLowerCase()] =
                  entry.value.toString();
            }
          }
        }
      }
    } catch (e) {
      AppLogger.w(
        'Failed to load Volcengine translation cache: $e',
        'VolcengineTranslator',
      );
    }
  }

  void _persistCache() {
    try {
      if (_cacheFile == null) {
        _cacheFile = File(_resolveProjectCachePath());
      }
      final parentDir = _cacheFile!.parent;
      if (!parentDir.existsSync()) {
        parentDir.createSync(recursive: true);
      }
      _cacheFile!.writeAsStringSync(jsonEncode(_cache), flush: true);
    } catch (e) {
      AppLogger.w(
        'Failed to save Volcengine translation cache: $e',
        'VolcengineTranslator',
      );
    }
  }

  static String _resolveProjectCachePath() {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    String baseDir = Directory.current.path;
    if (!exeDir.toLowerCase().contains('flutter') &&
        !exeDir.toLowerCase().contains('dart-sdk') &&
        !exeDir.toUpperCase().startsWith('C:')) {
      baseDir = exeDir;
    } else if (baseDir.toUpperCase().startsWith('C:')) {
      for (final candidate in [
        r'D:\AI\nai\NAI_Launcher_Windows_4.3.0+45_Portable',
        r'D:\AI\nai\Aaalice_NAI_Launcher-main',
        r'D:\AI\nai',
        r'D:\',
        r'E:\',
      ]) {
        if (Directory(candidate).existsSync()) {
          baseDir = candidate;
          break;
        }
      }
    }
    final cacheDir = Directory(p.join(baseDir, 'cache'));
    if (!cacheDir.existsSync()) {
      try {
        cacheDir.createSync(recursive: true);
      } catch (_) {}
    }
    return p.join(cacheDir.path, 'volcengine_translations.json');
  }

  List<int> _hmacSha256(List<int> key, String content) {
    return Hmac(sha256, key).convert(utf8.encode(content)).bytes;
  }

  String _hashSha256(String content) {
    return sha256.convert(utf8.encode(content)).toString();
  }

  Map<String, String> _buildSignedHeaders(
    String body,
    Map<String, dynamic> queryParams,
  ) {
    _ensureCredentialsLoaded();
    final ak = _accessKeyId ?? '';
    final sk = _secretAccessKey ?? '';

    final now = DateTime.now().toUtc();
    final xDate = DateFormat("yyyyMMdd'T'HHmmss'Z'").format(now);
    final shortXDate = xDate.substring(0, 8);
    final xContentSha256 = _hashSha256(body);

    final allQuery = {
      'Action': _action,
      'Version': _version,
      ...queryParams,
    };

    final sortedKeys = allQuery.keys.toList()..sort();
    final queryBuffer = StringBuffer();
    for (var i = 0; i < sortedKeys.length; i++) {
      final k = sortedKeys[i];
      final v = allQuery[k];
      if (i > 0) queryBuffer.write('&');
      queryBuffer.write(Uri.encodeQueryComponent(k));
      queryBuffer.write('=');
      queryBuffer.write(Uri.encodeQueryComponent(v.toString()));
    }
    final normQuery = queryBuffer.toString().replaceAll('+', '%20');

    const signedHeadersStr = 'content-type;host;x-content-sha256;x-date';
    final canonicalHeaders = [
      'content-type:$_contentType',
      'host:$_host',
      'x-content-sha256:$xContentSha256',
      'x-date:$xDate',
    ].join('\n');

    final canonicalRequest = [
      'POST',
      '/',
      normQuery,
      canonicalHeaders,
      '',
      signedHeadersStr,
      xContentSha256,
    ].join('\n');

    final hashedCanonicalRequest = _hashSha256(canonicalRequest);
    final credentialScope = '$shortXDate/$_region/$_service/request';
    final stringToSign = [
      'HMAC-SHA256',
      xDate,
      credentialScope,
      hashedCanonicalRequest,
    ].join('\n');

    final kDate = _hmacSha256(utf8.encode(sk), shortXDate);
    final kRegion = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, _service);
    final kSigning = _hmacSha256(kService, 'request');
    final signature =
        Hmac(sha256, kSigning).convert(utf8.encode(stringToSign)).toString();

    final authorization =
        'HMAC-SHA256 Credential=$ak/$credentialScope, SignedHeaders=$signedHeadersStr, Signature=$signature';

    return {
      'Host': _host,
      'X-Content-Sha256': xContentSha256,
      'X-Date': xDate,
      'Content-Type': _contentType,
      'Authorization': authorization,
    };
  }

  Future<String?> translate(String text, {String targetLang = 'zh'}) async {
    final clean = text.trim();
    if (clean.isEmpty) return null;
    _ensureCacheLoaded();

    final cacheKey = clean.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final requestBody = jsonEncode({
        'TargetLanguage': targetLang,
        'TextList': [clean],
      });

      final headers = _buildSignedHeaders(requestBody, {});
      final url = 'https://$_host/?Action=$_action&Version=$_version';

      final response = await _dio.post(
        url,
        data: requestBody,
        options: Options(
          headers: headers,
          responseType: ResponseType.json,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final data = response.data;
      if (data is Map) {
        final list = data['TranslationList'];
        if (list is List && list.isNotEmpty) {
          final first = list.first;
          if (first is Map && first['Translation'] != null) {
            final translated = first['Translation'].toString().trim();
            if (translated.isNotEmpty) {
              _cache[cacheKey] = translated;
              _persistCache();
              return translated;
            }
          }
        }
      }
    } catch (e) {
      AppLogger.w(
        'Volcengine translation request failed for "$clean": $e',
        'VolcengineTranslator',
      );
    }
    return null;
  }
}
