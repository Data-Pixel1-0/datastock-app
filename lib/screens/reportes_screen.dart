import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_config.dart';

enum VistaReporte { resumen, categorias, alertas }

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen> {
  static const Color _azul = Color(0xFF0F2A66);
  static const Color _verde = Color(0xFF0F9D58);
  static const Color _rojo = Color(0xFFD93025);
  static const Color _amarillo = Color(0xFFF9AB00);
  static const String _movimientosKey = 'stock_movimientos_detectados';

  final List<Map<String, dynamic>> _productos = [];
  final List<_MovimientoReporte> _movimientos = [];
  VistaReporte _vista = VistaReporte.resumen;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarReporte();
  }

  int get _totalProductos => _productos.length;

  int get _totalUnidades {
    return _productos.fold<int>(0, (total, producto) => total + _stockProducto(producto));
  }

  double get _valorInventario {
    return _productos.fold<double>(
      0,
      (total, producto) => total + (_stockProducto(producto) * _precioProducto(producto)),
    );
  }

  List<Map<String, dynamic>> get _productosBajos {
    return _productos.where((producto) {
      return _stockProducto(producto) <= _stockMinimo(producto);
    }).toList()
      ..sort((a, b) => _stockProducto(a).compareTo(_stockProducto(b)));
  }

  List<_CategoriaResumen> get _categorias {
    final data = <String, _CategoriaResumen>{};
    for (final producto in _productos) {
      final categoria = _categoriaProducto(producto);
      final stock = _stockProducto(producto);
      final valor = stock * _precioProducto(producto);
      final actual = data[categoria] ??
          _CategoriaResumen(
            nombre: categoria,
            productos: 0,
            unidades: 0,
            valor: 0,
          );
      data[categoria] = actual.copyWith(
        productos: actual.productos + 1,
        unidades: actual.unidades + stock,
        valor: actual.valor + valor,
      );
    }
    return data.values.toList()..sort((a, b) => b.valor.compareTo(a.valor));
  }

  List<Map<String, dynamic>> get _topValor {
    final productos = List<Map<String, dynamic>>.from(_productos);
    productos.sort((a, b) {
      final valorA = _stockProducto(a) * _precioProducto(a);
      final valorB = _stockProducto(b) * _precioProducto(b);
      return valorB.compareTo(valorA);
    });
    return productos.take(5).toList();
  }

  int get _entradasDetectadas {
    return _movimientos
        .where((movimiento) => movimiento.tipo == 'entrada')
        .fold<int>(0, (total, movimiento) => total + movimiento.cantidad);
  }

  int get _salidasDetectadas {
    return _movimientos
        .where((movimiento) => movimiento.tipo == 'salida')
        .fold<int>(0, (total, movimiento) => total + movimiento.cantidad);
  }

  int _stockProducto(Map<String, dynamic> producto) {
    return int.tryParse(
          producto['stock']?.toString() ?? producto['cantidad']?.toString() ?? '',
        ) ??
        0;
  }

  int _stockMinimo(Map<String, dynamic> producto) {
    final minimo = int.tryParse(producto['stock_minimo']?.toString() ?? '') ?? 0;
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
    return producto['codigo']?.toString().trim().isNotEmpty == true
        ? producto['codigo'].toString().trim()
        : producto['id']?.toString() ?? 'Sin codigo';
  }

  String _categoriaProducto(Map<String, dynamic> producto) {
    return producto['categoria']?.toString().trim().isNotEmpty == true
        ? producto['categoria'].toString().trim()
        : 'General';
  }

  String _moneda(double valor) {
    final texto = valor.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < texto.length; i++) {
      final posicion = texto.length - i;
      buffer.write(texto[i]);
      if (posicion > 1 && posicion % 3 == 1) {
        buffer.write('.');
      }
    }
    return '\$${buffer.toString()}';
  }

  Future<void> _cargarReporte() async {
    setState(() => _cargando = true);

    try {
      final response = await http.get(Uri.parse(ApiConfig.productosUrl));
      final prefs = await SharedPreferences.getInstance();
      final movimientosRaw = prefs.getString(_movimientosKey);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final productos = <Map<String, dynamic>>[];
        if (data is List) {
          productos.addAll(List<Map<String, dynamic>>.from(
            data.map((item) => Map<String, dynamic>.from(item as Map)),
          ));
        }

        setState(() {
          _productos
            ..clear()
            ..addAll(productos);
          _movimientos
            ..clear()
            ..addAll(_leerMovimientos(movimientosRaw));
          _cargando = false;
        });
      } else {
        setState(() => _cargando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar reporte: ${response.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el reporte: $e')),
      );
    }
  }

  List<_MovimientoReporte> _leerMovimientos(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final data = jsonDecode(raw);
      if (data is! List) return [];
      return data
          .whereType<Map>()
          .map((item) => _MovimientoReporte.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _copiarReporte() async {
    final texto = StringBuffer()
      ..writeln('REPORTE DATASTOCK')
      ..writeln('Productos: $_totalProductos')
      ..writeln('Unidades: $_totalUnidades')
      ..writeln('Valor inventario: ${_moneda(_valorInventario)}')
      ..writeln('Productos en baja unidad: ${_productosBajos.length}')
      ..writeln('Entradas detectadas: $_entradasDetectadas')
      ..writeln('Salidas detectadas: $_salidasDetectadas')
      ..writeln('')
      ..writeln('TOP PRODUCTOS POR VALOR');

    for (final producto in _topValor) {
      final nombre = _nombreProducto(producto);
      final stock = _stockProducto(producto);
      final valor = stock * _precioProducto(producto);
      texto.writeln('- $nombre: $stock und | ${_moneda(valor)}');
    }

    await Clipboard.setData(ClipboardData(text: texto.toString()));

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Reporte copiado al portapapeles.')),
    );
  }

  Widget _buildHero() {
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
              'Reportes',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tu inventario resumido, bonito y listo para revisar.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _MetricCard(
                    titulo: 'Valor',
                    valor: _moneda(_valorInventario),
                    icono: Icons.payments_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    titulo: 'Unidades',
                    valor: _totalUnidades.toString(),
                    icono: Icons.inventory_2_outlined,
                    color: const Color(0xFFB8F7D4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MetricCard(
                    titulo: 'Alertas',
                    valor: _productosBajos.length.toString(),
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

  Widget _buildTabs() {
    return Material(
      color: Colors.white,
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<VistaReporte>(
            segments: const [
              ButtonSegment(
                value: VistaReporte.resumen,
                icon: Icon(Icons.dashboard_outlined),
                label: Text('Resumen'),
              ),
              ButtonSegment(
                value: VistaReporte.categorias,
                icon: Icon(Icons.pie_chart_outline),
                label: Text('Categorias'),
              ),
              ButtonSegment(
                value: VistaReporte.alertas,
                icon: Icon(Icons.report_gmailerrorred_outlined),
                label: Text('Alertas'),
              ),
            ],
            selected: {_vista},
            onSelectionChanged: (seleccion) {
              setState(() => _vista = seleccion.first);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_productos.isEmpty) {
      return const _EmptyReport(
        icono: Icons.inventory_2_outlined,
        titulo: 'Sin productos',
        mensaje: 'Agrega productos para generar estadisticas reales.',
      );
    }

    if (_vista == VistaReporte.categorias) return _buildCategorias();
    if (_vista == VistaReporte.alertas) return _buildAlertas();
    return _buildResumen();
  }

  Widget _buildResumen() {
    final maxValor = _topValor.isEmpty
        ? 1.0
        : _topValor
            .map((producto) => _stockProducto(producto) * _precioProducto(producto))
            .reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _cargarReporte,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildPulseCard(),
          const SizedBox(height: 12),
          _SectionCard(
            titulo: 'Top productos por valor',
            icono: Icons.leaderboard_outlined,
            children: _topValor.map((producto) {
              final nombre = _nombreProducto(producto);
              final stock = _stockProducto(producto);
              final valor = stock * _precioProducto(producto);
              return _BarRow(
                titulo: nombre,
                subtitulo: '$stock unidades | ${_codigoProducto(producto)}',
                valor: _moneda(valor),
                progreso: maxValor == 0 ? 0 : valor / maxValor,
                color: _azul,
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          _SectionCard(
            titulo: 'Movimientos detectados',
            icono: Icons.sync_alt,
            children: [
              _MovementLine(
                titulo: 'Entradas',
                valor: '+$_entradasDetectadas unidades',
                icono: Icons.south_west_rounded,
                color: _verde,
              ),
              _MovementLine(
                titulo: 'Salidas',
                valor: '-$_salidasDetectadas unidades',
                icono: Icons.north_east_rounded,
                color: _rojo,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPulseCard() {
    final porcentajeBajo =
        _totalProductos == 0 ? 0.0 : _productosBajos.length / _totalProductos;
    final saludable = _productosBajos.isEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: saludable ? const Color(0xFFEAF7EF) : const Color(0xFFFFF7E0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: saludable ? const Color(0xFFC8ECD7) : const Color(0xFFFFE0A3),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: saludable
                ? _verde.withValues(alpha: 0.13)
                : _amarillo.withValues(alpha: 0.18),
            child: Icon(
              saludable ? Icons.verified_outlined : Icons.warning_amber_rounded,
              color: saludable ? _verde : const Color(0xFF8A5A00),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  saludable ? 'Inventario sano' : 'Inventario necesita revision',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  saludable
                      ? 'No hay productos por debajo del minimo.'
                      : '${_productosBajos.length} productos estan en baja unidad.',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: porcentajeBajo,
                    backgroundColor: Colors.white,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      saludable ? _verde : _amarillo,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorias() {
    final categorias = _categorias;
    final maxValor = categorias.isEmpty
        ? 1.0
        : categorias.map((categoria) => categoria.valor).reduce((a, b) => a > b ? a : b);

    return RefreshIndicator(
      onRefresh: _cargarReporte,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _SectionCard(
            titulo: 'Categorias con mas peso',
            icono: Icons.category_outlined,
            children: categorias.map((categoria) {
              return _BarRow(
                titulo: categoria.nombre,
                subtitulo: '${categoria.productos} productos | ${categoria.unidades} unidades',
                valor: _moneda(categoria.valor),
                progreso: maxValor == 0 ? 0 : categoria.valor / maxValor,
                color: _verde,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertas() {
    final bajos = _productosBajos;
    return RefreshIndicator(
      onRefresh: _cargarReporte,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (bajos.isEmpty)
            const _EmptyReport(
              icono: Icons.check_circle_outline,
              titulo: 'Todo Bien',
              mensaje: 'No hay productos en baja unidad.',
            )
          else
            ...bajos.map(_buildAlertaProducto),
        ],
      ),
    );
  }

  Widget _buildAlertaProducto(Map<String, dynamic> producto) {
    final nombre = _nombreProducto(producto);
    final stock = _stockProducto(producto);
    final minimo = _stockMinimo(producto);
    final agotado = stock <= 0;
    final color = agotado ? _rojo : _amarillo;

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
              backgroundColor: color.withValues(alpha: 0.14),
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
                    agotado ? 'Sin unidades de $nombre' : 'Baja unidad de $nombre',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Codigo: ${_codigoProducto(producto)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoPill(texto: 'Stock $stock', color: color),
                      _InfoPill(texto: 'Minimo $minimo', color: _azul),
                      _InfoPill(
                        texto: _moneda(stock * _precioProducto(producto)),
                        color: _verde,
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
        title: const Text('Reportes'),
        backgroundColor: _azul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Copiar reporte',
            onPressed: _productos.isEmpty ? null : _copiarReporte,
            icon: const Icon(Icons.copy_all_outlined),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargarReporte,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHero(),
          _buildTabs(),
          Expanded(child: _buildContenido()),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _MetricCard({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 86),
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
              fontSize: 19,
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

class _SectionCard extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final List<Widget> children;

  const _SectionCard({
    required this.titulo,
    required this.icono,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, color: const Color(0xFF0F2A66)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String titulo;
  final String subtitulo;
  final String valor;
  final double progreso;
  final Color color;

  const _BarRow({
    required this.titulo,
    required this.subtitulo,
    required this.valor,
    required this.progreso,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final progresoSeguro = progreso.clamp(0.0, 1.0).toDouble();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                valor,
                style: TextStyle(color: color, fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            subtitulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 9,
              value: progresoSeguro,
              backgroundColor: const Color(0xFFE8EEF7),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementLine extends StatelessWidget {
  final String titulo;
  final String valor;
  final IconData icono;
  final Color color;

  const _MovementLine({
    required this.titulo,
    required this.valor,
    required this.icono,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icono, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              titulo,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            valor,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String texto;
  final Color color;

  const _InfoPill({required this.texto, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyReport extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;

  const _EmptyReport({
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 58, color: const Color(0xFF0F2A66)),
              const SizedBox(height: 12),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                mensaje,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriaResumen {
  final String nombre;
  final int productos;
  final int unidades;
  final double valor;

  const _CategoriaResumen({
    required this.nombre,
    required this.productos,
    required this.unidades,
    required this.valor,
  });

  _CategoriaResumen copyWith({
    int? productos,
    int? unidades,
    double? valor,
  }) {
    return _CategoriaResumen(
      nombre: nombre,
      productos: productos ?? this.productos,
      unidades: unidades ?? this.unidades,
      valor: valor ?? this.valor,
    );
  }
}

class _MovimientoReporte {
  final int cantidad;
  final String tipo;

  const _MovimientoReporte({
    required this.cantidad,
    required this.tipo,
  });

  factory _MovimientoReporte.fromJson(Map<String, dynamic> json) {
    return _MovimientoReporte(
      cantidad: int.tryParse(json['cantidad']?.toString() ?? '') ?? 0,
      tipo: json['tipo']?.toString() ?? '',
    );
  }
}
