import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();

  factory AuthService() {
    return _instance;
  }

  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Usuario actual
  User? get currentUser => _auth.currentUser;

  // Stream de autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Registrar usuario
  Future<bool> registrar(String email, String contrasena) async {
    try {
      await _auth.createUserWithEmailAndPassword(
        email: email,
        password: contrasena,
      );
      return true;
    } catch (e) {
      print('Error al registrar: $e');
      return false;
    }
  }

  // Iniciar sesión
  Future<bool> iniciarSesion(String email, String contrasena) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: contrasena,
      );
      return true;
    } catch (e) {
      print('Error al iniciar sesión: $e');
      return false;
    }
  }

  // Cerrar sesión
  Future<void> cerrarSesion() async {
    await _auth.signOut();
  }

  // Verificar si usuario está autenticado
  bool estaAutenticado() {
    return _auth.currentUser != null;
  }

  // Obtener email del usuario actual
  String? obtenerEmail() {
    return _auth.currentUser?.email;
  }

  // Cambiar contraseña
  Future<bool> cambiarContrasena(String nuevaContrasena) async {
    try {
      await _auth.currentUser?.updatePassword(nuevaContrasena);
      return true;
    } catch (e) {
      print('Error al cambiar contraseña: $e');
      return false;
    }
  }

  // Restablecer contraseña
  Future<bool> restablecerContrasena(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return true;
    } catch (e) {
      print('Error al restablecer contraseña: $e');
      return false;
    }
  }
}
