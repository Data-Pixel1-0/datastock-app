import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import '../services/api_config.dart';

class ProductosScreen extends StatefulWidget {
  const ProductosScreen({super.key});

  @override
  State<ProductosScreen> createState() => _ProductosScreenState();
}

class _ProductosScreenState extends State<ProductosScreen> {
  final List<Map<String, dynamic>> _productos = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _obtenerProductos();
  }

  Future<void> _obtenerProductos() async {
    setState(() => _cargando = true);

    try {
      final response = await http.get(Uri.parse(ApiConfig.productosUrl));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _productos.clear();
          if (data is List) {
            _productos.addAll(List<Map<String, dynamic>>.from(
              data.map((item) => Map<String, dynamic>.from(item as Map)),
            ));
          }
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar productos: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo conectar a la API: $e')),
      );
    }
  }

  String _generarCodigoProducto() {
    return 'DS-${DateTime.now().microsecondsSinceEpoch}';
  }

  int _stockProducto(Map<String, dynamic>? producto) {
    if (producto == null) return 0;
    return int.tryParse(
          producto['stock']?.toString() ?? producto['cantidad']?.toString() ?? '',
        ) ??
        0;
  }

  String _codigoProducto(Map<String, dynamic> producto) {
    final codigo = producto['codigo']?.toString().trim();
    if (codigo != null && codigo.isNotEmpty) return codigo;
    return producto['id']?.toString() ?? 'Sin codigo';
  }

  void _mostrarQrProducto(Map<String, dynamic> producto) {
    final nombre = producto['nombre']?.toString() ?? 'Sin nombre';
    final codigo = _codigoProducto(producto);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          nombre,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: QrImageView(
                data: codigo,
                version: QrVersions.auto,
                size: 210,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              codigo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarFormularioProducto({Map<String, dynamic>? producto}) async {
    final formKey = GlobalKey<FormState>();
    String nombre = producto?['nombre']?.toString() ?? '';
    String categoria = producto?['categoria']?.toString() ?? '';
    String codigo = producto == null ? _generarCodigoProducto() : _codigoProducto(producto);
    int cantidad = _stockProducto(producto);
    double precio = double.tryParse(producto?['precio']?.toString() ?? '') ?? 0.0;
    String descripcion = producto?['descripcion']?.toString() ?? '';

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          title: Row(
            children: [
              Icon(
                producto == null ? Icons.add_circle_outline : Icons.edit_note_outlined,
                color: const Color(0xFF0F2A66),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  producto == null ? 'Agregar producto' : 'Editar producto',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    initialValue: nombre,
                    decoration: const InputDecoration(labelText: 'Nombre del producto'),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? 'Ingresa un nombre' : null,
                    onSaved: (value) => nombre = value!.trim(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: categoria,
                    decoration: const InputDecoration(labelText: 'Categoría (opcional)'),
                    onSaved: (value) => categoria = value?.trim() ?? '',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: cantidad == 0 ? '' : cantidad.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Ingresa una cantidad';
                      return int.tryParse(value) == null ? 'Cantidad inválida' : null;
                    },
                    onSaved: (value) => cantidad = int.parse(value!.trim()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: precio == 0 ? '' : precio.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Ingresa un precio';
                      return double.tryParse(value) == null ? 'Precio inválido' : null;
                    },
                    onSaved: (value) => precio = double.parse(value!.trim()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: codigo,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Codigo QR unico',
                      prefixIcon: Icon(Icons.qr_code_2),
                    ),
                    onSaved: (value) => codigo = value?.trim() ?? '',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: QrImageView(
                      data: codigo,
                      version: QrVersions.auto,
                      size: 150,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: descripcion,
                    decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
                    maxLines: 2,
                    onSaved: (value) => descripcion = value?.trim() ?? '',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();

                final codigoFinal = codigo.trim().isNotEmpty ? codigo.trim() : _generarCodigoProducto();

                final datosProducto = {
                  'nombre': nombre,
                  'codigo': codigoFinal,
                  'descripcion': descripcion,
                  'stock': cantidad,
                  'precio': double.parse(precio.toStringAsFixed(2)),
                  'categoria': categoria.trim().isNotEmpty ? categoria.trim() : 'General',
                  'categoria_id': null,
                  'imagen': '',
                  'stock_minimo': 0,
                };

                bool exito = false;
                try {
                  final response = producto == null
                      ? await http.post(
                          Uri.parse(ApiConfig.productosUrl),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(datosProducto),
                        )
                      : await http.put(
                          Uri.parse('${ApiConfig.productosUrl}/${producto['id']}'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode(datosProducto),
                        );

                  exito = response.statusCode >= 200 && response.statusCode < 300;

                  if (!exito) {
                    final mensajeError = response.body.trim().isNotEmpty
                        ? response.body.trim()
                        : 'Error ${response.statusCode}';
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No se pudo guardar el producto: $mensajeError')),
                    );
                  }
                } catch (e) {
                  exito = false;
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('No se pudo guardar el producto: $e')),
                  );
                }

                if (!context.mounted) return;
                Navigator.pop(context, exito);
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _obtenerProductos();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(producto == null ? 'Producto agregado correctamente' : 'Producto actualizado correctamente')),
      );
    }
  }

  Future<void> _eliminarProducto(Map<String, dynamic> producto) async {
    final nombre = producto['nombre']?.toString() ?? 'este producto';
    final id = producto['id']?.toString() ?? '';

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Deseas eliminar "$nombre" de la base de datos?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmar != true) return;

    try {
      final response = await http.delete(Uri.parse('${ApiConfig.productosUrl}/$id'));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _obtenerProductos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto eliminado correctamente')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar el producto: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar el producto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        backgroundColor: const Color(0xFF0F2A66),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _obtenerProductos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _productos.isEmpty
              ? const Center(child: Text('No hay productos registrados'))
              : RefreshIndicator(
                  onRefresh: _obtenerProductos,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _productos.length,
                    itemBuilder: (context, index) {
                      final producto = _productos[index];
                      final nombre = producto['nombre']?.toString() ?? 'Sin nombre';
                      final categoria = producto['categoria']?.toString() ?? '';
                      final cantidad = _stockProducto(producto);
                      final precio = double.tryParse(producto['precio']?.toString() ?? '') ?? 0.0;
                      final descripcion = producto['descripcion']?.toString() ?? '';
                      final codigo = _codigoProducto(producto);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      nombre,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: () => _mostrarFormularioProducto(producto: producto),
                                    icon: const Icon(Icons.edit_outlined, color: Color(0xFF0F2A66)),
                                  ),
                                  IconButton(
                                    tooltip: 'Ver QR',
                                    onPressed: () => _mostrarQrProducto(producto),
                                    icon: const Icon(Icons.qr_code_2, color: Color(0xFF0F9D58)),
                                  ),
                                  IconButton(
                                    tooltip: 'Eliminar',
                                    onPressed: () => _eliminarProducto(producto),
                                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                                  ),
                                ],
                              ),
                              if (categoria.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0F2A66).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      categoria,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF0F2A66),
                                      ),
                                    ),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text('Codigo QR: $codigo'),
                              const SizedBox(height: 4),
                              Text('Cantidad disponible: $cantidad'),
                              const SizedBox(height: 4),
                              Text('Precio: \$${double.tryParse(precio.toString())?.toStringAsFixed(2) ?? precio.toString()}'),
                              if (descripcion.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  descripcion,
                                  style: const TextStyle(color: Colors.black54),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _mostrarFormularioProducto(),
        backgroundColor: const Color(0xFF0F2A66),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Agregar producto'),
      ),
    );
  }
}
