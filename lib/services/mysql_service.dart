import 'package:flutter/foundation.dart';
import 'package:mysql1/mysql1.dart';
import 'db_config.dart';

class MySqlService {
  static final MySqlService _instance = MySqlService._internal();

  factory MySqlService() => _instance;

  MySqlService._internal();

  MySqlConnection? _connection;
  bool _connected = false;

  bool get isConnected => _connected;

  Future<void> connect({
    String? host,
    int? port,
    String? user,
    String? password,
    String? database,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError(
          'MySQL direct connection is not supported on Flutter Web. Use a backend API instead.');
    }

    if (_connected && _connection != null) {
      return;
    }

    final settings = ConnectionSettings(
      host: host ?? DbConfig.host,
      port: port ?? DbConfig.port,
      user: user ?? DbConfig.user,
      password: password ?? DbConfig.password,
      db: database ?? DbConfig.database,
    );

    _connection = await MySqlConnection.connect(settings);
    _connected = true;
  }

  Future<void> close() async {
    if (_connection != null) {
      await _connection!.close();
      _connected = false;
      _connection = null;
    }
  }

  Future<Results> query(String sql, [List<dynamic>? values]) async {
    if (_connection == null) {
      throw StateError('MySQL connection is not established.');
    }
    return await _connection!.query(sql, values ?? []);
  }

  Future<List<Map<String, dynamic>>> selectAll(String table) async {
    final results = await query('SELECT * FROM `$table`');
    return results
        .map((row) => row.fields.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Future<bool> ensureUsersTable() async {
    await query('''
      CREATE TABLE IF NOT EXISTS users (
        id INT AUTO_INCREMENT PRIMARY KEY,
        email VARCHAR(255) NOT NULL UNIQUE,
        password VARCHAR(255) NOT NULL,
        role VARCHAR(50) NOT NULL DEFAULT 'user',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    return true;
  }

  Future<bool> userExists(String email) async {
    await connect();
    final results = await query('SELECT COUNT(*) AS count FROM users WHERE email = ?', [email]);
    final value = results.first['count'];
    final count = value is int ? value : int.tryParse(value.toString()) ?? 0;
    return count > 0;
  }

  Future<bool> validateUser(String email, String password) async {
    await connect();
    final results = await query('SELECT password FROM users WHERE email = ?', [email]);
    if (results.isEmpty) return false;
    final storedPassword = results.first['password'] as String?;
    return storedPassword == password;
  }

  Future<bool> registerUser(String email, String password, String role) async {
    await connect();
    await ensureUsersTable();
    await query('INSERT INTO users (email, password, role) VALUES (?, ?, ?)', [email, password, role]);
    return true;
  }

  Future<bool> execute(String sql, [List<dynamic>? values]) async {
    await query(sql, values);
    return true;
  }
}
