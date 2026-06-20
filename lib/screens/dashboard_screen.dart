import 'package:flutter/material.dart';
import 'scanner_screen.dart';
import 'productos_screen.dart';
import 'categorias_screen.dart';
import 'salidas_screen.dart';
import 'reportes_screen.dart';
import 'usuarios_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final opciones = [
      _MenuCard(
        titulo: 'Productos',
        icono: Icons.inventory_2,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductosScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Categorías',
        icono: Icons.category,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CategoriasScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Vender escaneando',
        icono: Icons.point_of_sale,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ScannerScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Entrada y salida',
        icono: Icons.sync_alt,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SalidasScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Reportes',
        icono: Icons.bar_chart,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ReportesScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Usuarios',
        icono: Icons.people,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsuariosScreen()),
        ),
      ),
      _MenuCard(
        titulo: 'Configuración',
        icono: Icons.settings,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('DataStock'),
        backgroundColor: const Color(0xFF0F2A66),
        foregroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Image.asset('lib/assets/logo.png', fit: BoxFit.contain),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: GridView.builder(
          itemCount: opciones.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.02,
          ),
          itemBuilder: (context, index) => opciones[index],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final String titulo;
  final IconData icono;
  final VoidCallback onTap;

  const _MenuCard({
    required this.titulo,
    required this.icono,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icono, size: 46, color: const Color(0xFF0F2A66)),
              const SizedBox(height: 10),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Abrir módulo',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
