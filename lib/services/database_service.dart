import 'package:firebase_database/firebase_database.dart';
import '../models/producto.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  final FirebaseDatabase _db = FirebaseDatabase.instance;
  late DatabaseReference _productosRef;

  void initialize() {
    _productosRef = _db.ref().child('productos');
  }

  // Obtener todos los productos
  Future<List<Producto>> obtenerProductos() async {
    try {
      final DataSnapshot snapshot = await _productosRef.get();
      if (snapshot.exists && snapshot.value is Map) {
        final Map<dynamic, dynamic> productos =
            Map<dynamic, dynamic>.from(snapshot.value as Map);

        return productos.entries.map((entry) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          return Producto.fromJson({
            ...data,
            'id': entry.key.toString(),
          });
        }).toList();
      }
      return [];
    } catch (e) {
      print('Error al obtener productos: $e');
      return [];
    }
  }

  // Obtener un producto por ID
  Future<Producto?> obtenerProducto(String id) async {
    try {
      final DataSnapshot snapshot = await _productosRef.child(id).get();
      if (snapshot.exists) {
        return Producto.fromJson(snapshot.value as Map<dynamic, dynamic>);
      }
      return null;
    } catch (e) {
      print('Error al obtener producto: $e');
      return null;
    }
  }

  // Crear un nuevo producto
  Future<bool> crearProducto(Producto producto) async {
    try {
      final ref = (producto.id.trim().isNotEmpty)
          ? _productosRef.child(producto.id)
          : _productosRef.push();
      final data = producto.toJson();

      data['id'] = ref.key ?? producto.id;
      await ref.set(data);
      return true;
    } catch (e) {
      print('Error al crear producto: $e');
      return false;
    }
  }

  // Actualizar un producto
  Future<bool> actualizarProducto(String id, Map<String, dynamic> datos) async {
    try {
      await _productosRef.child(id).update(datos);
      return true;
    } catch (e) {
      print('Error al actualizar producto: $e');
      return false;
    }
  }

  // Eliminar un producto
  Future<bool> eliminarProducto(String id) async {
    try {
      await _productosRef.child(id).remove();
      return true;
    } catch (e) {
      print('Error al eliminar producto: $e');
      return false;
    }
  }

  // Escuchar cambios en productos en tiempo real
  Stream<List<Producto>> obtenerProductosStream() {
    return _productosRef.onValue.map((event) {
      if (event.snapshot.exists && event.snapshot.value is Map) {
        final Map<dynamic, dynamic> productos =
            Map<dynamic, dynamic>.from(event.snapshot.value as Map);

        return productos.entries.map((entry) {
          final data = Map<String, dynamic>.from(entry.value as Map);
          return Producto.fromJson({
            ...data,
            'id': entry.key.toString(),
          });
        }).toList();
      }
      return [];
    });
  }

  // Actualizar cantidad de producto (para entradas/salidas)
  Future<bool> actualizarCantidad(
      String id, int nuevaCantidad) async {
    try {
      await _productosRef.child(id).update({'cantidad': nuevaCantidad});
      return true;
    } catch (e) {
      print('Error al actualizar cantidad: $e');
      return false;
    }
  }
}
