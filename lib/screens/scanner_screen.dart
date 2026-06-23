import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  static const String _snapshotKey = 'stock_snapshot_productos';
  static const String _movimientosKey = 'stock_movimientos_detectados';
  static const Color _azul = Color(0xFF0F2A66);
  static const Color _verde = Color(0xFF0F9D58);
  static const Color _rojo = Color(0xFFD93025);

  final MobileScannerController _scannerController = MobileScannerController();
  final List<_VentaItem> _carrito = [];
  String _estado = 'Escanea productos para armar la venta';
  bool _procesandoEscaneo = false;
  bool _finalizandoVenta = false;

  int get _totalUnidades {
    return _carrito.fold<int>(0, (total, item) => total + item.cantidad);
  }

  double get _totalVenta {
    return _carrito.fold<double>(0, (total, item) => total + item.subtotal);
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _procesarCodigo(String codigo) async {
    final codigoLimpio = codigo.trim();
    if (codigoLimpio.isEmpty || _procesandoEscaneo || _finalizandoVenta) return;

    setState(() {
      _estado = 'Buscando $codigoLimpio...';
      _procesandoEscaneo = true;
    });

    try {
      await _scannerController.stop();
    } catch (_) {
      // La venta puede seguir aunque la camara ya este pausada.
    }

    final resultado = await _agregarProductoPorCodigo(codigoLimpio);

    if (!mounted) return;

    setState(() => _procesandoEscaneo = false);

    try {
      await _scannerController.start();
    } catch (_) {
      // Si la camara no reanuda, el usuario puede salir y volver a entrar.
    }

    if (!mounted || resultado == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: resultado.exito ? _verde : _rojo,
        content: Text(resultado.mensaje),
      ),
    );
  }

  int _stockProducto(Map<String, dynamic> producto) {
    return int.tryParse(
          producto['stock']?.toString() ??
              producto['cantidad']?.toString() ??
              '',
        ) ??
        0;
  }

  int _stockMinimo(Map<String, dynamic> producto) {
    final minimo =
        int.tryParse(producto['stock_minimo']?.toString() ?? '') ?? 0;
    return minimo > 0 ? minimo : 5;
  }

  double _precioProducto(Map<String, dynamic> producto) {
    return double.tryParse(producto['precio']?.toString() ?? '') ?? 0.0;
  }

  String _nombreProducto(Map<String, dynamic> producto) {
    return producto['nombre']?.toString().trim().isNotEmpty == true
        ? producto['nombre'].toString().trim()
        : 'Sin nombre';
  }

  String _codigoProducto(Map<String, dynamic> producto) {
    final codigo = producto['codigo']?.toString().trim();
    if (codigo != null && codigo.isNotEmpty) return codigo;
    final id = _idProducto(producto);
    return id.isNotEmpty ? id : 'Sin codigo';
  }

  String _idProducto(Map<String, dynamic> producto) {
    const posiblesIds = ['id', '_id', 'id_producto', 'producto_id'];
    for (final campo in posiblesIds) {
      final id = producto[campo]?.toString().trim();
      if (id != null && id.isNotEmpty && id != 'null') return id;
    }
    return '';
  }

  String _moneda(double valor) {
    return '\$${valor.toStringAsFixed(2)}';
  }

  Map<String, dynamic> _datosProductoConStock(_VentaItem item, int nuevoStock) {
    final producto = item.producto;
    return {
      'nombre': item.nombre,
      'codigo': item.codigo,
      'descripcion': producto['descripcion']?.toString() ?? '',
      'stock': nuevoStock,
      'cantidad': nuevoStock,
      'precio': item.precio,
      'categoria': producto['categoria']?.toString().trim().isNotEmpty == true
          ? producto['categoria'].toString().trim()
          : 'General',
      'categoria_id': producto['categoria_id'],
      'imagen': producto['imagen']?.toString() ?? '',
      'stock_minimo': _stockMinimo(producto),
    };
  }

  Future<_ResultadoEscaneo?> _agregarProductoPorCodigo(String codigo) async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.productosUrl));
      if (response.statusCode != 200) {
        setState(() => _estado = 'No se pudo consultar inventario');
        return _ResultadoEscaneo(
          exito: false,
          mensaje: 'No se pudo consultar productos: ${response.statusCode}',
        );
      }

      final productos = _leerProductos(response.body);
      final producto = productos.cast<Map<String, dynamic>?>().firstWhere(
        (item) =>
            item != null &&
            (_codigoProducto(item) == codigo || _idProducto(item) == codigo),
        orElse: () => null,
      );

      if (producto == null) {
        final guardado = await _mostrarFormularioProducto(codigo);
        if (!mounted) return null;

        if (guardado == true) {
          setState(
            () =>
                _estado = 'Producto nuevo registrado. Escanealo para venderlo.',
          );
          return const _ResultadoEscaneo(
            exito: true,
            mensaje: 'Producto agregado correctamente.',
          );
        }
        setState(() => _estado = 'Escanea productos para armar la venta');
        return null;
      }

      final stockDisponible = _stockProducto(producto);
      final nombre = _nombreProducto(producto);
      if (stockDisponible <= 0) {
        setState(() => _estado = '$nombre esta sin stock');
        return _ResultadoEscaneo(
          exito: false,
          mensaje: 'No hay unidades disponibles de $nombre.',
        );
      }

      final codigoProducto = _codigoProducto(producto);
      final index = _carrito.indexWhere(
        (item) => item.codigo == codigoProducto,
      );
      final cantidadActual = index == -1 ? 0 : _carrito[index].cantidad;

      if (cantidadActual >= stockDisponible) {
        setState(() => _estado = 'No hay mas unidades disponibles de $nombre');
        return _ResultadoEscaneo(
          exito: false,
          mensaje: 'Ya agregaste todo el stock disponible de $nombre.',
        );
      }

      final disponibleParaAgregar = stockDisponible - cantidadActual;
      final cantidadAgregar = await _pedirCantidadVenta(
        nombre: nombre,
        precio: _precioProducto(producto),
        disponible: disponibleParaAgregar,
        enCarrito: cantidadActual,
      );

      if (!mounted) return null;

      if (cantidadAgregar == null) {
        setState(() => _estado = 'Escanea productos para armar la venta');
        return null;
      }

      setState(() {
        if (index == -1) {
          _carrito.add(
            _VentaItem(
              producto: producto,
              id: _idProducto(producto),
              codigo: codigoProducto,
              nombre: nombre,
              precio: _precioProducto(producto),
              stockActual: stockDisponible,
              cantidad: cantidadAgregar,
            ),
          );
        } else {
          _carrito[index] = _carrito[index].copyWith(
            cantidad: cantidadActual + cantidadAgregar,
          );
        }
        _estado = 'Agregado: $cantidadAgregar de $nombre';
      });

      return _ResultadoEscaneo(
        exito: true,
        mensaje: '$cantidadAgregar de $nombre agregado a la venta.',
      );
    } catch (e) {
      if (!mounted) return null;
      setState(() => _estado = 'No se pudo procesar el escaneo');
      return _ResultadoEscaneo(
        exito: false,
        mensaje: 'No se pudo procesar el escaneo: $e',
      );
    }
  }

  Future<int?> _pedirCantidadVenta({
    required String nombre,
    required double precio,
    required int disponible,
    required int enCarrito,
  }) async {
    final formKey = GlobalKey<FormState>();
    int cantidad = 1;

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          title: const Row(
            children: [
              Icon(Icons.add_shopping_cart_outlined, color: _azul),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Cantidad a vender',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nombre,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Precio: ${_moneda(precio)} | Disponible: $disponible',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (enCarrito > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ya hay $enCarrito en esta venta.',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 14),
                TextFormField(
                  initialValue: '1',
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Unidades',
                    prefixIcon: Icon(Icons.numbers),
                  ),
                  validator: (value) {
                    final numero = int.tryParse(value?.trim() ?? '');
                    if (numero == null || numero <= 0) {
                      return 'Ingresa una cantidad valida';
                    }
                    if (numero > disponible) {
                      return 'Solo puedes agregar hasta $disponible';
                    }
                    return null;
                  },
                  onSaved: (value) => cantidad = int.parse(value!.trim()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                Navigator.pop(context, cantidad);
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ],
        );
      },
    );
  }

  List<Map<String, dynamic>> _leerProductos(String body) {
    final data = jsonDecode(body);
    if (data is! List) return [];

    return data.whereType<Map>().map((item) {
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  Future<void> _finalizarVenta() async {
    if (_carrito.isEmpty || _finalizandoVenta) return;

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finalizar venta'),
        content: Text(
          'Se venderan $_totalUnidades unidades por un total de ${_moneda(_totalVenta)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Cobrar'),
          ),
        ],
      ),
    );

    if (!mounted || confirmar != true) return;

    setState(() {
      _finalizandoVenta = true;
      _estado = 'Guardando venta...';
    });

    final vendidos = List<_VentaItem>.from(_carrito);
    final totalVendido = _totalVenta;

    try {
      for (final item in vendidos) {
        if (item.id.trim().isEmpty) {
          throw Exception(
            'El producto ${item.nombre} no tiene ID para actualizar stock.',
          );
        }

        final nuevoStock = item.stockActual - item.cantidad;
        final response = await http.put(
          Uri.parse('${ApiConfig.productosUrl}/${item.id}'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(_datosProductoConStock(item, nuevoStock)),
        );

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final mensajeError = response.body.trim().isNotEmpty
              ? response.body.trim()
              : 'Error ${response.statusCode}';
          throw Exception(
            'No se pudo actualizar ${item.nombre}: $mensajeError',
          );
        }
      }

      await _guardarSalidasLocales(vendidos);

      if (!mounted) return;
      setState(() {
        _carrito.clear();
        _estado = 'Venta finalizada. Escanea la siguiente venta.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _verde,
          content: Text('Venta guardada por ${_moneda(totalVendido)}.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _estado = 'No se pudo guardar la venta');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(backgroundColor: _rojo, content: Text('$e')));
    } finally {
      if (mounted) setState(() => _finalizandoVenta = false);
    }
  }

  Future<void> _guardarSalidasLocales(List<_VentaItem> vendidos) async {
    final prefs = await SharedPreferences.getInstance();
    final movimientos = _leerMovimientosLocales(
      prefs.getString(_movimientosKey),
    );
    final snapshot = _leerSnapshotLocal(prefs.getString(_snapshotKey));
    final ahora = DateTime.now().toIso8601String();

    for (final item in vendidos) {
      final stockFinal = item.stockActual - item.cantidad;
      movimientos.insert(0, {
        'producto': item.nombre,
        'codigo': item.codigo,
        'cantidad': item.cantidad,
        'stockFinal': stockFinal,
        'stockMinimo': _stockMinimo(item.producto),
        'tipo': 'salida',
        'fecha': ahora,
        'alertaBaja': stockFinal <= _stockMinimo(item.producto),
      });
      snapshot[item.id] = stockFinal;
    }

    if (movimientos.length > 60) {
      movimientos.removeRange(60, movimientos.length);
    }

    await prefs.setString(_movimientosKey, jsonEncode(movimientos));
    await prefs.setString(_snapshotKey, jsonEncode(snapshot));
  }

  List<Map<String, dynamic>> _leerMovimientosLocales(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, int> _leerSnapshotLocal(String? raw) {
    final snapshot = <String, int>{};
    if (raw == null || raw.trim().isEmpty) return snapshot;

    try {
      final data = jsonDecode(raw);
      if (data is Map) {
        data.forEach((key, value) {
          snapshot[key.toString()] = int.tryParse(value.toString()) ?? 0;
        });
      }
    } catch (_) {
      return {};
    }

    return snapshot;
  }

  void _quitarItem(_VentaItem item) {
    setState(() {
      if (item.cantidad <= 1) {
        _carrito.removeWhere((actual) => actual.codigo == item.codigo);
      } else {
        final index = _carrito.indexWhere(
          (actual) => actual.codigo == item.codigo,
        );
        if (index != -1) {
          _carrito[index] = item.copyWith(cantidad: item.cantidad - 1);
        }
      }
      _estado = _carrito.isEmpty
          ? 'Escanea productos para armar la venta'
          : _estado;
    });
  }

  void _limpiarVenta() {
    if (_carrito.isEmpty) return;
    setState(() {
      _carrito.clear();
      _estado = 'Venta cancelada. Escanea productos para armar otra venta.';
    });
  }

  Future<bool?> _mostrarFormularioProducto(String codigoEscaneado) async {
    final formKey = GlobalKey<FormState>();
    String nombre = '';
    String categoria = '';
    int cantidad = 0;
    double precio = 0.0;
    String descripcion = '';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
          title: const Row(
            children: [
              Icon(Icons.qr_code_scanner, color: _azul),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Registrar producto',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
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
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Ingresa un nombre'
                        : null,
                    onSaved: (value) => nombre = value!.trim(),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: categoria,
                    decoration: const InputDecoration(
                      labelText: 'Categoria (opcional)',
                    ),
                    onSaved: (value) => categoria = value?.trim() ?? '',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa una cantidad';
                      }
                      final numero = int.tryParse(value.trim());
                      if (numero == null || numero < 0) {
                        return 'Cantidad invalida';
                      }
                      return null;
                    },
                    onSaved: (value) => cantidad = int.parse(value!.trim()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Precio'),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Ingresa un precio';
                      }
                      final numero = double.tryParse(value.trim());
                      if (numero == null || numero < 0) {
                        return 'Precio invalido';
                      }
                      return null;
                    },
                    onSaved: (value) => precio = double.parse(value!.trim()),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: codigoEscaneado,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Codigo de barras',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: descripcion,
                    decoration: const InputDecoration(
                      labelText: 'Descripcion (opcional)',
                    ),
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

                final datosProducto = {
                  'nombre': nombre,
                  'codigo': codigoEscaneado,
                  'descripcion': descripcion,
                  'stock': cantidad,
                  'precio': double.parse(precio.toStringAsFixed(2)),
                  'categoria': categoria.trim().isNotEmpty
                      ? categoria.trim()
                      : 'General',
                  'categoria_id': null,
                  'imagen': '',
                  'stock_minimo': 0,
                };

                try {
                  final response = await http.post(
                    Uri.parse(ApiConfig.productosUrl),
                    headers: {'Content-Type': 'application/json'},
                    body: jsonEncode(datosProducto),
                  );

                  final exito =
                      response.statusCode >= 200 && response.statusCode < 300;

                  if (!context.mounted) return;

                  if (exito) {
                    Navigator.pop(context, true);
                  } else {
                    final mensajeError = response.body.trim().isNotEmpty
                        ? response.body.trim()
                        : 'Error ${response.statusCode}';
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'No se pudo guardar el producto: $mensajeError',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('No se pudo guardar el producto: $e'),
                    ),
                  );
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResumenVenta() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: const BoxDecoration(color: Colors.white),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total ${_moneda(_totalVenta)}',
                    style: const TextStyle(
                      color: _azul,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '$_totalUnidades unidades en venta',
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cancelar venta',
              onPressed: _carrito.isEmpty || _finalizandoVenta
                  ? null
                  : _limpiarVenta,
              icon: const Icon(Icons.delete_outline),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _carrito.isEmpty || _finalizandoVenta
                  ? null
                  : _finalizarVenta,
              icon: _finalizandoVenta
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.payments_outlined),
              label: Text(_finalizandoVenta ? 'Guardando' : 'Finalizar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCarrito() {
    if (_carrito.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Text(
            'Pasa cada producto por el escaner para agregarlo a la venta.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: _carrito.length,
      itemBuilder: (context, index) {
        final item = _carrito[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _azul.withValues(alpha: 0.12),
              child: Text(
                item.cantidad.toString(),
                style: const TextStyle(
                  color: _azul,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            title: Text(
              item.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${_moneda(item.precio)} c/u | Codigo ${item.codigo}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _moneda(item.subtotal),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                IconButton(
                  tooltip: 'Quitar uno',
                  onPressed: _finalizandoVenta ? null : () => _quitarItem(item),
                  icon: const Icon(Icons.remove_circle_outline, color: _rojo),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Venta por escaner'),
        backgroundColor: _azul,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          SizedBox(
            height: 260,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: (capture) {
                    if (capture.barcodes.isEmpty) return;

                    final codigo = capture.barcodes.first.rawValue;
                    if (codigo != null) {
                      _procesarCodigo(codigo);
                    }
                  },
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.68),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _estado,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _buildResumenVenta(),
          Expanded(child: _buildCarrito()),
        ],
      ),
    );
  }
}

class _VentaItem {
  final Map<String, dynamic> producto;
  final String id;
  final String codigo;
  final String nombre;
  final double precio;
  final int stockActual;
  final int cantidad;

  const _VentaItem({
    required this.producto,
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.precio,
    required this.stockActual,
    required this.cantidad,
  });

  double get subtotal => precio * cantidad;

  _VentaItem copyWith({int? cantidad}) {
    return _VentaItem(
      producto: producto,
      id: id,
      codigo: codigo,
      nombre: nombre,
      precio: precio,
      stockActual: stockActual,
      cantidad: cantidad ?? this.cantidad,
    );
  }
}

class _ResultadoEscaneo {
  final bool exito;
  final String mensaje;

  const _ResultadoEscaneo({required this.exito, required this.mensaje});
}
