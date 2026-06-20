class Producto {
  String id;
  String nombre;
  String categoria;
  int cantidad;
  double precio;
  String descripcion;
  DateTime fechaCreacion;

  Producto({
    required this.id,
    required this.nombre,
    required this.categoria,
    required this.cantidad,
    required this.precio,
    required this.descripcion,
    required this.fechaCreacion,
  });

  // Convertir a JSON para almacenar en Firebase
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'categoria': categoria,
      'cantidad': cantidad,
      'precio': precio,
      'descripcion': descripcion,
      'fechaCreacion': fechaCreacion.toIso8601String(),
    };
  }

  // Crear desde JSON
  factory Producto.fromJson(Map<dynamic, dynamic> json) {
    return Producto(
      id: json['id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? '',
      categoria: json['categoria']?.toString() ?? '',
      cantidad: int.tryParse(json['cantidad']?.toString() ?? '') ?? 0,
      precio: double.tryParse(json['precio']?.toString() ?? '') ?? 0.0,
      descripcion: json['descripcion']?.toString() ?? '',
      fechaCreacion: json['fechaCreacion'] != null
          ? DateTime.tryParse(json['fechaCreacion'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
