import 'package:flutter/foundation.dart';

class ApiConfig {
  static const String _mobileBaseUrl = 'http://192.168.13.173:3000';
  static const String _webBaseUrl = 'http://localhost:3000';

  static String get baseUrl {
    return kIsWeb ? _webBaseUrl : _mobileBaseUrl;
  }

  static String get productosUrl => '$baseUrl/productos';
  static String get loginUrl => '$baseUrl/login';
  static String get usuariosUrl => '$baseUrl/usuarios';
}
