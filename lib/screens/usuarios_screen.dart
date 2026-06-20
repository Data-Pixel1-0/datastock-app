import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_config.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  List usuarios = [];
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    obtenerUsuarios();
  }

  Future<void> obtenerUsuarios() async {
    try {
      final response = await http.get(Uri.parse(ApiConfig.usuariosUrl));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        setState(() {
          usuarios = data is List ? data : [];
          cargando = false;
        });
      } else {
        if (!mounted) return;
        setState(() => cargando = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => cargando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudieron cargar los usuarios: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios'),
        backgroundColor: const Color(0xFF0F2A66),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: obtenerUsuarios,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: cargando
          ? const Center(child: CircularProgressIndicator())
          : usuarios.isEmpty
              ? const Center(child: Text('No hay usuarios registrados'))
              : RefreshIndicator(
                  onRefresh: obtenerUsuarios,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: usuarios.length,
                    itemBuilder: (context, index) {
                      final usuario = usuarios[index];
                      final nombre = usuario['nombre']?.toString() ?? 'Sin nombre';
                      final usuarioNombre = usuario['usuario']?.toString() ?? 'Sin usuario';
                      final rol = usuario['rol']?.toString() ?? 'Sin rol';
                      final correo = usuario['correo']?.toString() ?? 'Sin correo';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF0F2A66),
                            foregroundColor: Colors.white,
                            child: Text(nombre.isNotEmpty ? nombre[0].toUpperCase() : 'U'),
                          ),
                          title: Text(
                            nombre,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('$usuarioNombre • $rol'),
                              const SizedBox(height: 2),
                              Text(correo, style: const TextStyle(color: Colors.black54)),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'ver') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Detalle de $nombre')),
                                );
                              } else if (value == 'editar') {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Editar a $nombre')),
                                );
                              }
                            },
                            itemBuilder: (context) => const [
                              PopupMenuItem(value: 'ver', child: Text('Ver detalle')),
                              PopupMenuItem(value: 'editar', child: Text('Editar')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Agregar usuario habilitado.')),
          );
        },
        backgroundColor: const Color(0xFF0F2A66),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Agregar usuario'),
      ),
    );
  }
}