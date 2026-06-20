import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

enum TipoMovimiento { entrada, salida }

enum FiltroMovimiento { todos, entradas, salidas, alertas }

class SalidasScreen extends StatefulWidget {
  const SalidasScreen({super.key});

  @override
  State<SalidasScreen> createState() => _SalidasScreenState();
}

class _SalidasScreenState extends State<SalidasScreen> {
  static const Color _azul = Color(0xFF0F2A66);
  static const Color _verde = Color(0xFF0F9D58);
  static const Color _rojo = Color(0xFFD93025);
  static const Color _amarillo = Color(0xFFF9AB00);
  static const String _snapshotKey = 'stock_snapshot_productos';
  static const String _movimientosKey = 'stock_movimientos_detectados';

  final TextEditingController _busquedaController = TextEditingController();
  final List<Map<String, dynamic>> _productos = [];
  final List<_Movimiento> _movimientos = [];
  bool _cargando = true;
  bool _guardandoVenta = false;
  String _busqueda = '';
  FiltroMovimiento _filtro = FiltroMovimiento.todos;

  @override
  void initState() {
    super.initState();
    _obtenerProductos();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _productosCriticos {
    return _productos.where((producto) {
      final stock = _stockProducto(producto);
      final minimo = _stockMinimo(producto);
      return stock <= minimo;
    }).toList()..sort((a, b) => _stockProducto(a).compareTo(_stockProducto(b)));
  }

  List<_Movimiento> get _movimientosFiltrados {
    final filtroTexto = _busqueda.trim().toLowerCase();
    final movimientos = _movimientos.where((movimiento) {
      final coincideTexto =
          filtroTexto.isEmpty ||
          movimiento.producto.toLowerCase().contains(filtroTexto) ||
          movimiento.codigo.toLowerCase().contains(filtroTexto);

      if (!coincideTexto) return false;
      if (_filtro == FiltroMovimiento.entradas) {
        return movimiento.tipo == TipoMovimiento.entrada;
      }
      if (_filtro == FiltroMovimiento.salidas) {
        return movimiento.tipo == TipoMovimiento.salida;
      }
      return true;
    }).toList();

    movimientos.sort((a, b) => b.fecha.compareTo(a.fecha));
    return movimientos;
  }

  int get _totalEntradas {
    return _movimientos
        .where((movimiento) => movimiento.tipo == TipoMovimiento.entrada)
        .fold<int>(0, (total, movimiento) => total + movimiento.cantidad);
  }

  int get _totalSalidas {
    return _movimientos
        .where((movimiento) => movimiento.tipo == TipoMovimiento.salida)
        .fold<int>(0, (total, movimiento) => total + movimiento.cantidad);
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

  String _nombreProducto(Map<String, dynamic> producto) {
    return producto['nombre']?.toString().trim().isNotEmpty == true
        ? producto['nombre'].toString().trim()
        : 'Sin nombre';
  }

  String _codigoProducto(Map<String, dynamic> producto) {
    return producto['codigo']?.toString().trim().isNotEmpty == true
        ? producto['codigo'].toString().trim()
        : producto['id']?.toString() ?? 'Sin codigo';
  }

  String _idProducto(Map<String, dynamic> producto) {
    final id = producto['id']?.toString().trim();
    if (id != null && id.isNotEmpty) return id;
    return _codigoProducto(producto);
  }

  Map<String, dynamic> _datosProductoConStock(
    Map<String, dynamic> producto,
    int nuevoStock,
  ) {
    return {
      'nombre': _nombreProducto(producto),
      'codigo': _codigoProducto(producto),
      'descripcion': producto['descripcion']?.toString() ?? '',
      'stock': nuevoStock,
      'cantidad': nuevoStock,
      'precio': double.tryParse(producto['precio']?.toString() ?? '') ?? 0.0,
      'categoria': producto['categoria']?.toString().trim().isNotEmpty == true
          ? producto['categoria'].toString().trim()
          : 'General',
      'categoria_id': producto['categoria_id'],
      'imagen': producto['imagen']?.toString() ?? '',
      'stock_minimo':
          int.tryParse(producto['stock_minimo']?.toString() ?? '') ?? 0,
    };
  }

  Future<void> _obtenerProductos() async {
    setState(() => _cargando = true);

    try {
      final response = await http.get(Uri.parse(ApiConfig.productosUrl));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final productos = <Map<String, dynamic>>[];

        if (data is List) {
          productos.addAll(
            List<Map<String, dynamic>>.from(
              data.map((item) => Map<String, dynamic>.from(item as Map)),
            ),
          );
        }

        final movimientosNuevos = await _detectarMovimientos(productos);

        setState(() {
          _productos
            ..clear()
            ..addAll(productos);
          _movimientos
            ..insertAll(0, movimientosNuevos)
            ..sort((a, b) => b.fecha.compareTo(a.fecha));
          if (_movimientos.length > 60) {
            _movimientos.removeRange(60, _movimientos.length);
          }
          _cargando = false;
        });

        await _guardarMovimientos();
        await _guardarSnapshot(productos);

        if (movimientosNuevos.any((movimiento) => movimiento.alertaBaja)) {
          _mostrarAvisoInventario();
        }
      } else {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar productos: ${response.statusCode}'),
          ),
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

  Future<List<_Movimiento>> _detectarMovimientos(
    List<Map<String, dynamic>> productos,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final movimientosGuardados = prefs.getString(_movimientosKey);
    final snapshotGuardado = prefs.getString(_snapshotKey);

    _movimientos
      ..clear()
      ..addAll(_leerMovimientos(movimientosGuardados));

    final stockAnterior = <String, int>{};
    if (snapshotGuardado != null && snapshotGuardado.trim().isNotEmpty) {
      final data = jsonDecode(snapshotGuardado);
      if (data is Map) {
        data.forEach((key, value) {
          stockAnterior[key.toString()] = int.tryParse(value.toString()) ?? 0;
        });
      }
    }

    final ahora = DateTime.now();
    final detectados = <_Movimiento>[];

    for (final producto in productos) {
      final id = _idProducto(producto);
      final actual = _stockProducto(producto);
      final minimo = _stockMinimo(producto);

      if (!stockAnterior.containsKey(id)) {
        if (actual <= 0) continue;
        detectados.add(
          _Movimiento(
            producto: _nombreProducto(producto),
            codigo: _codigoProducto(producto),
            cantidad: actual,
            stockFinal: actual,
            stockMinimo: minimo,
            tipo: TipoMovimiento.entrada,
            fecha: ahora,
            alertaBaja: false,
          ),
        );
        continue;
      }

      final anterior = stockAnterior[id] ?? 0;
      final diferencia = actual - anterior;

      if (diferencia == 0) continue;

      final tipo = diferencia > 0
          ? TipoMovimiento.entrada
          : TipoMovimiento.salida;
      final cantidad = diferencia.abs();

      detectados.add(
        _Movimiento(
          producto: _nombreProducto(producto),
          codigo: _codigoProducto(producto),
          cantidad: cantidad,
          stockFinal: actual,
          stockMinimo: minimo,
          tipo: tipo,
          fecha: ahora,
          alertaBaja: tipo == TipoMovimiento.salida && actual <= minimo,
        ),
      );
    }

    return detectados;
  }

  List<_Movimiento> _leerMovimientos(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((item) => _Movimiento.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _guardarMovimientos() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _movimientos.map((movimiento) => movimiento.toJson()).toList();
    await prefs.setString(_movimientosKey, jsonEncode(data));
  }

  Future<void> _guardarSnapshot(List<Map<String, dynamic>> productos) async {
    final prefs = await SharedPreferences.getInstance();
    final snapshot = <String, int>{};
    for (final producto in productos) {
      snapshot[_idProducto(producto)] = _stockProducto(producto);
    }
    await prefs.setString(_snapshotKey, jsonEncode(snapshot));
  }

  void _mostrarAvisoInventario() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: _rojo,
        content: Text('Revise inventario: hay productos con baja unidad.'),
      ),
    );
  }

  Future<void> _registrarVenta() async {
    if (_productos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Primero carga o agrega productos al inventario.'),
        ),
      );
      return;
    }

    final productosDisponibles =
        _productos
            .where(
              (producto) =>
                  _stockProducto(producto) > 0 &&
                  _idProducto(producto).isNotEmpty,
            )
            .toList()
          ..sort((a, b) => _nombreProducto(a).compareTo(_nombreProducto(b)));

    if (productosDisponibles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay productos con stock disponible para vender.'),
        ),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    Map<String, dynamic> productoSeleccionado = productosDisponibles.first;
    int cantidadVendida = 1;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final stockActual = _stockProducto(productoSeleccionado);

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              contentPadding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              title: const Row(
                children: [
                  Icon(Icons.point_of_sale_outlined, color: _azul),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registrar venta',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _idProducto(productoSeleccionado),
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Producto vendido',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                      items: productosDisponibles.map((producto) {
                        final id = _idProducto(producto);
                        final nombre = _nombreProducto(producto);
                        final stock = _stockProducto(producto);
                        return DropdownMenuItem(
                          value: id,
                          child: Text(
                            '$nombre - Stock $stock',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (id) {
                        if (id == null) return;
                        setDialogState(() {
                          productoSeleccionado = productosDisponibles
                              .firstWhere(
                                (producto) => _idProducto(producto) == id,
                              );
                          cantidadVendida = 1;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: cantidadVendida.toString(),
                      key: ValueKey(_idProducto(productoSeleccionado)),
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Cantidad vendida',
                        helperText: 'Disponible: $stockActual unidades',
                        prefixIcon: const Icon(
                          Icons.remove_shopping_cart_outlined,
                        ),
                      ),
                      validator: (value) {
                        final cantidad = int.tryParse(value?.trim() ?? '');
                        if (cantidad == null || cantidad <= 0) {
                          return 'Ingresa una cantidad valida';
                        }
                        if (cantidad > stockActual) {
                          return 'No puedes vender mas de $stockActual';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        cantidadVendida = int.parse(value!.trim());
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;
                    formKey.currentState!.save();
                    Navigator.pop(context, true);
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('Vender'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted) return;

    if (confirmar != true) return;

    final id = productoSeleccionado['id']?.toString().trim();
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Este producto no tiene ID para actualizarlo.'),
        ),
      );
      return;
    }

    final stockActual = _stockProducto(productoSeleccionado);
    final nuevoStock = stockActual - cantidadVendida;

    setState(() => _guardandoVenta = true);
    try {
      final response = await http.put(
        Uri.parse('${ApiConfig.productosUrl}/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(
          _datosProductoConStock(productoSeleccionado, nuevoStock),
        ),
      );

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _obtenerProductos();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Venta registrada: $cantidadVendida unidad${cantidadVendida == 1 ? '' : 'es'} de ${_nombreProducto(productoSeleccionado)}.',
            ),
          ),
        );
      } else {
        final mensajeError = response.body.trim().isNotEmpty
            ? response.body.trim()
            : 'Error ${response.statusCode}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo registrar la venta: $mensajeError'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo registrar la venta: $e')),
      );
    } finally {
      if (mounted) setState(() => _guardandoVenta = false);
    }
  }

  Widget _buildResumen() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_azul, Color(0xFF1746A2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Entrada y salida',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Movimientos detectados segun el cambio de unidades.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ResumenTile(
                    titulo: 'Entradas',
                    valor: '+$_totalEntradas',
                    icono: Icons.south_west_rounded,
                    color: const Color(0xFFB8F7D4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResumenTile(
                    titulo: 'Salidas',
                    valor: '-$_totalSalidas',
                    icono: Icons.north_east_rounded,
                    color: const Color(0xFFFFD0C9),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ResumenTile(
                    titulo: 'Alertas',
                    valor: _productosCriticos.length.toString(),
                    icono: Icons.warning_amber_rounded,
                    color: const Color(0xFFFFE8A3),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControles() {
    return Material(
      elevation: 3,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          children: [
            TextField(
              controller: _busquedaController,
              decoration: InputDecoration(
                hintText: 'Buscar producto o codigo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar',
                        onPressed: () {
                          _busquedaController.clear();
                          setState(() => _busqueda = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onChanged: (value) => setState(() => _busqueda = value),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<FiltroMovimiento>(
                segments: const [
                  ButtonSegment(
                    value: FiltroMovimiento.todos,
                    icon: Icon(Icons.timeline),
                    label: Text('Todo'),
                  ),
                  ButtonSegment(
                    value: FiltroMovimiento.entradas,
                    icon: Icon(Icons.south_west_rounded),
                    label: Text('Entradas'),
                  ),
                  ButtonSegment(
                    value: FiltroMovimiento.salidas,
                    icon: Icon(Icons.north_east_rounded),
                    label: Text('Salidas'),
                  ),
                  ButtonSegment(
                    value: FiltroMovimiento.alertas,
                    icon: Icon(Icons.warning_amber_rounded),
                    label: Text('Alertas'),
                  ),
                ],
                selected: {_filtro},
                onSelectionChanged: (seleccion) {
                  setState(() => _filtro = seleccion.first);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_filtro == FiltroMovimiento.alertas) {
      return _buildListaAlertas();
    }

    final movimientos = _movimientosFiltrados;

    return RefreshIndicator(
      onRefresh: _obtenerProductos,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (_productosCriticos.isNotEmpty) _buildAlertaPrincipal(),
          if (movimientos.isEmpty)
            _buildEstadoVacio()
          else
            ...movimientos.map(_buildMovimientoCard),
        ],
      ),
    );
  }

  Widget _buildListaAlertas() {
    final productos = _productosCriticos.where((producto) {
      final filtroTexto = _busqueda.trim().toLowerCase();
      if (filtroTexto.isEmpty) return true;
      return _nombreProducto(producto).toLowerCase().contains(filtroTexto) ||
          _codigoProducto(producto).toLowerCase().contains(filtroTexto);
    }).toList();

    return RefreshIndicator(
      onRefresh: _obtenerProductos,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (productos.isEmpty)
            const _MensajeVacio(
              icono: Icons.check_circle_outline,
              titulo: 'Inventario tranquilo',
              mensaje: 'No hay productos por debajo del minimo.',
            )
          else
            ...productos.map(_buildAlertaCard),
        ],
      ),
    );
  }

  Widget _buildAlertaPrincipal() {
    final cantidad = _productosCriticos.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFE0A3)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Color(0xFFFFE8A3),
            child: Icon(Icons.warning_amber_rounded, color: Color(0xFF8A5A00)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              cantidad == 1
                  ? 'Revise inventario: 1 producto esta en baja unidad.'
                  : 'Revise inventario: $cantidad productos estan en baja unidad.',
              style: const TextStyle(
                color: Color(0xFF5F4100),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadoVacio() {
    return const _MensajeVacio(
      icono: Icons.timeline,
      titulo: 'Sin movimientos detectados',
      mensaje:
          'Cuando cambie el stock de un producto, aqui aparecera como entrada o salida.',
    );
  }

  Widget _buildMovimientoCard(_Movimiento movimiento) {
    final esEntrada = movimiento.tipo == TipoMovimiento.entrada;
    final color = esEntrada ? _verde : _rojo;
    final icono = esEntrada
        ? Icons.south_west_rounded
        : Icons.north_east_rounded;
    final titulo = esEntrada
        ? 'Entrada ${movimiento.cantidad} unidades de ${movimiento.producto}'
        : 'Salida ${movimiento.cantidad} unidades de ${movimiento.producto}';
    final hora =
        '${movimiento.fecha.hour.toString().padLeft(2, '0')}:${movimiento.fecha.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icono, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$hora  |  Codigo: ${movimiento.codigo}',
                        style: const TextStyle(
                          color: Colors.black54,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  esEntrada
                      ? '+${movimiento.cantidad}'
                      : '-${movimiento.cantidad}',
                  style: TextStyle(
                    color: color,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icono: Icons.inventory_2_outlined,
                  texto: 'Quedan ${movimiento.stockFinal}',
                  color: _azul,
                ),
                if (movimiento.alertaBaja)
                  _InfoChip(
                    icono: Icons.warning_amber_rounded,
                    texto: 'Revise inventario: baja unidad',
                    color: _amarillo,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertaCard(Map<String, dynamic> producto) {
    final nombre = _nombreProducto(producto);
    final codigo = _codigoProducto(producto);
    final stock = _stockProducto(producto);
    final minimo = _stockMinimo(producto);
    final agotado = stock <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 23,
              backgroundColor: (agotado ? _rojo : _amarillo).withValues(
                alpha: 0.14,
              ),
              child: Icon(
                agotado ? Icons.error_outline : Icons.warning_amber_rounded,
                color: agotado ? _rojo : const Color(0xFF8A5A00),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agotado
                        ? 'Sin unidades de $nombre'
                        : 'Revise inventario: baja unidad de $nombre',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Codigo: $codigo',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icono: Icons.inventory_2_outlined,
                        texto: 'Stock $stock',
                        color: agotado ? _rojo : _amarillo,
                      ),
                      _InfoChip(
                        icono: Icons.low_priority,
                        texto: 'Minimo $minimo',
                        color: _azul,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('Entrada y salida'),
        backgroundColor: _azul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _obtenerProductos,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildResumen(),
          _buildControles(),
          Expanded(child: _buildContenido()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _guardandoVenta ? null : _registrarVenta,
        backgroundColor: _rojo,
        foregroundColor: Colors.white,
        icon: _guardandoVenta
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.point_of_sale_outlined),
        label: Text(_guardandoVenta ? 'Guardando' : 'Registrar venta'),
      ),
    );
  }
}

class _ResumenTile extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _ResumenTile({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icono, color: color, size: 20),
          Text(
            valor,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.76),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icono;
  final String texto;
  final Color color;

  const _InfoChip({
    required this.icono,
    required this.texto,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 210),
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MensajeVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;

  const _MensajeVacio({
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Icon(icono, size: 52, color: const Color(0xFF0F2A66)),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _Movimiento {
  final String producto;
  final String codigo;
  final int cantidad;
  final int stockFinal;
  final int stockMinimo;
  final TipoMovimiento tipo;
  final DateTime fecha;
  final bool alertaBaja;

  const _Movimiento({
    required this.producto,
    required this.codigo,
    required this.cantidad,
    required this.stockFinal,
    required this.stockMinimo,
    required this.tipo,
    required this.fecha,
    required this.alertaBaja,
  });

  factory _Movimiento.fromJson(Map<String, dynamic> json) {
    return _Movimiento(
      producto: json['producto']?.toString() ?? 'Sin nombre',
      codigo: json['codigo']?.toString() ?? 'Sin codigo',
      cantidad: int.tryParse(json['cantidad']?.toString() ?? '') ?? 0,
      stockFinal: int.tryParse(json['stockFinal']?.toString() ?? '') ?? 0,
      stockMinimo: int.tryParse(json['stockMinimo']?.toString() ?? '') ?? 5,
      tipo: json['tipo'] == 'salida'
          ? TipoMovimiento.salida
          : TipoMovimiento.entrada,
      fecha:
          DateTime.tryParse(json['fecha']?.toString() ?? '') ?? DateTime.now(),
      alertaBaja: json['alertaBaja'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'producto': producto,
      'codigo': codigo,
      'cantidad': cantidad,
      'stockFinal': stockFinal,
      'stockMinimo': stockMinimo,
      'tipo': tipo == TipoMovimiento.salida ? 'salida' : 'entrada',
      'fecha': fecha.toIso8601String(),
      'alertaBaja': alertaBaja,
    };
  }
}
