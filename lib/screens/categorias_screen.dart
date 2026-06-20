import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/api_config.dart';

class CategoriasScreen extends StatefulWidget {
  const CategoriasScreen({super.key});

  @override
  State<CategoriasScreen> createState() => _CategoriasScreenState();
}

class _CategoriasScreenState extends State<CategoriasScreen> {
  final TextEditingController _categoriaController = TextEditingController();
  final List<Map<String, dynamic>> _productos = [];
  String _categoriaBuscada = '';
  bool _cargando = true;

  List<Map<String, dynamic>> get _productosFiltrados {
    final filtro = _normalizar(_categoriaBuscada);
    if (filtro.isEmpty) return [];

    return _productos.where((producto) {
      final categoria = _normalizar(producto['categoria']?.toString() ?? '');
      return categoria.contains(filtro);
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _obtenerProductos();
  }

  @override
  void dispose() {
    _categoriaController.dispose();
    super.dispose();
  }

  String _normalizar(String texto) {
    return texto.trim().toLowerCase();
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

  void _buscarCategoria() {
    FocusScope.of(context).unfocus();
    setState(() {
      _categoriaBuscada = _categoriaController.text.trim();
    });
  }

  void _limpiarBusqueda() {
    _categoriaController.clear();
    setState(() => _categoriaBuscada = '');
  }

  Widget _buildProductoCard(Map<String, dynamic> producto) {
    final nombre = producto['nombre']?.toString() ?? 'Sin nombre';
    final categoria = producto['categoria']?.toString() ?? 'Sin categoria';
    final cantidad = int.tryParse(
          producto['stock']?.toString() ?? producto['cantidad']?.toString() ?? '',
        ) ??
        0;
    final precio = double.tryParse(producto['precio']?.toString() ?? '') ?? 0.0;
    final codigo = producto['codigo']?.toString() ?? producto['id']?.toString() ?? 'Sin codigo';
    final descripcion = producto['descripcion']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Color(0xFF0F2A66)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nombre,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: const Icon(Icons.category_outlined, size: 18),
                  label: Text(categoria),
                  backgroundColor: const Color(0xFF0F2A66).withValues(alpha: 0.12),
                  labelStyle: const TextStyle(
                    color: Color(0xFF0F2A66),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Chip(
                  avatar: const Icon(Icons.numbers_outlined, size: 18),
                  label: Text('Stock: $cantidad'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Codigo: $codigo'),
            const SizedBox(height: 4),
            Text('Precio: \$${precio.toStringAsFixed(2)}'),
            if (descripcion.trim().isNotEmpty) ...[
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
  }

  Widget _buildContenido() {
    if (_cargando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categoriaBuscada.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Escribe una categoria para ver los productos que pertenecen a ella.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    final productos = _productosFiltrados;

    if (productos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No se encontraron productos en la categoria "$_categoriaBuscada".',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _obtenerProductos,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: productos.length,
        itemBuilder: (context, index) => _buildProductoCard(productos[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cantidadResultados = _productosFiltrados.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias'),
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
      body: Column(
        children: [
          Material(
            elevation: 2,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _categoriaController,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      labelText: 'Categoria a buscar',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _categoriaController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar',
                              onPressed: _limpiarBusqueda,
                              icon: const Icon(Icons.close),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _buscarCategoria(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _buscarCategoria,
                          icon: const Icon(Icons.manage_search),
                          label: const Text('Buscar categoria'),
                        ),
                      ),
                    ],
                  ),
                  if (_categoriaBuscada.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      '$cantidadResultados producto${cantidadResultados == 1 ? '' : 's'} encontrado${cantidadResultados == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(child: _buildContenido()),
        ],
      ),
    );
  }
}
