// lib/vistas/estudiante_home_vista.dart
// Mapa con flutter_map + OpenStreetMap (sin API Key, 100% gratuito)

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../modelos/camioneta_modelo.dart';
import '../providers/auth_provider.dart';
import '../providers/camioneta_provider.dart';
import 'seleccion_asientos_vista.dart';

class EstudianteHomeVista extends StatefulWidget {
  const EstudianteHomeVista({super.key});

  @override
  State<EstudianteHomeVista> createState() => _EstudianteHomeVistaState();
}

class _EstudianteHomeVistaState extends State<EstudianteHomeVista> {
  final MapController _mapController = MapController();

  // ── Coordenadas iniciales: USM Caracas (ajusta a tu campus) ──────
  static const LatLng _centroUSM = LatLng(10.4806, -66.9036);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CamionetaProvider>().iniciarStream();
    });
  }

  // ── Marcadores desde camionetas activas ──────────────────────────
  List<Marker> _buildMarkers(List<CamionetaModelo> camionetas) {
    return camionetas.where((c) => c.ubicacion != null).map((c) {
      final color = switch (c.estado) {
        EstadoCamioneta.disponible => Colors.green,
        EstadoCamioneta.en_camino => Colors.blue,
        _ => Colors.red,
      };

      return Marker(
        point: LatLng(
          c.ubicacion!.latitude,
          c.ubicacion!.longitude,
        ),
        width: 48,
        height: 56,
        child: GestureDetector(
          onTap: () => _mostrarInfoCamioneta(context, c),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  c.id.replaceAll('camioneta_', 'U'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                ),
              ),
              Icon(Icons.location_pin, color: color, size: 28),
            ],
          ),
        ),
      );
    }).toList();
  }

  void _mostrarInfoCamioneta(BuildContext context, CamionetaModelo c) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.id,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Destino: ${c.destino}'),
            Text('Asientos libres: ${c.asientosLibres}/${c.totalAsientos}'),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SeleccionAsientosVista(camionetaId: c.id),
                    ),
                  );
                },
                child: const Text('Ver asientos'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final camionetaProv = context.watch<CamionetaProvider>();
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          children: [
            _EncabezadoEstudiante(auth: auth),

            // ── Mapa OpenStreetMap ──────────────────────────────────
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _centroUSM,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.all,
                      ),
                    ),
                    children: [
                      // Capa base OpenStreetMap
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.usm.transporte_app',
                        maxZoom: 19,
                      ),
                      // Capa de marcadores
                      MarkerLayer(
                        markers: _buildMarkers(camionetaProv.camionetasActivas),
                      ),
                    ],
                  ),

                  // Leyenda
                  const Positioned(bottom: 12, left: 12, child: _LeyendaMapa()),

                  // Botón centrar
                  Positioned(
                    bottom: 12,
                    right: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'centrar',
                      onPressed: () => _mapController.move(_centroUSM, 14),
                      tooltip: 'Centrar mapa',
                      child: const Icon(Icons.center_focus_strong, size: 20),
                    ),
                  ),

                  // Overlay de carga
                  if (camionetaProv.cargando)
                    Container(
                      color: Colors.black12,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                ],
              ),
            ),

            // ── Lista de camionetas ──────────────────────────────────
            Expanded(
              flex: 4,
              child: _ListaCamionetas(
                cargando: camionetaProv.cargando,
                error: camionetaProv.error,
                camionetas: camionetaProv.camionetasActivas,
                onVerAsientos: (id) => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SeleccionAsientosVista(camionetaId: id),
                  ),
                ),
                onCentrarMapa: (ubicacion) {
                  if (ubicacion != null) {
                    _mapController.move(
                      LatLng(ubicacion.latitude, ubicacion.longitude),
                      16,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENCABEZADO
// ─────────────────────────────────────────────────────────────────────────────

class _EncabezadoEstudiante extends StatelessWidget {
  final AuthProvider auth;
  const _EncabezadoEstudiante({required this.auth});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final nombre = auth.nombreCompleto ?? 'Estudiante';
    final rol = auth.rolSeleccionado?.name ?? 'estudiante';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        boxShadow: [
          BoxShadow(
              color: colors.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colors.primary,
            child: Text(
              nombre.isNotEmpty ? nombre[0].toUpperCase() : 'E',
              style: TextStyle(
                  color: colors.onPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                _ChipRol(rol: rol),
              ],
            ),
          ),
          // TODO: reemplazar con UsuarioProvider para saldo real
          _PanelSaldo(saldo: 0, mensualidadActiva: false),
        ],
      ),
    );
  }
}

class _ChipRol extends StatelessWidget {
  final String rol;
  const _ChipRol({required this.rol});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        rol.toUpperCase(),
        style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.primary,
            letterSpacing: 0.8),
      ),
    );
  }
}

class _PanelSaldo extends StatelessWidget {
  final num saldo;
  final bool mensualidadActiva;
  const _PanelSaldo({required this.saldo, required this.mensualidadActiva});

  String _fmt(num v) {
    final s = v.toInt().toString();
    final buf = StringBuffer();
    int c = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      if (c > 0 && c % 3 == 0) buf.write('.');
      buf.write(s[i]);
      c++;
    }
    return buf.toString().split('').reversed.join();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text('\$${_fmt(saldo)}',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold, color: colors.primary)),
        const SizedBox(height: 3),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mensualidadActiva
                  ? Icons.check_circle_outline
                  : Icons.cancel_outlined,
              size: 13,
              color: mensualidadActiva ? Colors.green : colors.error,
            ),
            const SizedBox(width: 3),
            Text(
              mensualidadActiva ? 'Activa' : 'Vencida',
              style: TextStyle(
                  fontSize: 11,
                  color: mensualidadActiva ? Colors.green : colors.error,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEYENDA DEL MAPA
// ─────────────────────────────────────────────────────────────────────────────

class _LeyendaMapa extends StatelessWidget {
  const _LeyendaMapa();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ItemLeyenda(color: Colors.green, texto: 'Disponible'),
          SizedBox(height: 4),
          _ItemLeyenda(color: Colors.blue, texto: 'En camino'),
        ],
      ),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _ItemLeyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 6),
        Text(texto, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LISTA DE CAMIONETAS
// ─────────────────────────────────────────────────────────────────────────────

class _ListaCamionetas extends StatelessWidget {
  final bool cargando;
  final String? error;
  final List<CamionetaModelo> camionetas;
  final void Function(String) onVerAsientos;
  final void Function(dynamic) onCentrarMapa;

  const _ListaCamionetas({
    required this.cargando,
    required this.error,
    required this.camionetas,
    required this.onVerAsientos,
    required this.onCentrarMapa,
  });

  @override
  Widget build(BuildContext context) {
    if (cargando) return const Center(child: CircularProgressIndicator());

    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      );
    }

    if (camionetas.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_bus_outlined, size: 40, color: Colors.grey),
            SizedBox(height: 10),
            Text('No hay camionetas activas en este momento.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              Text('Camionetas activas',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${camionetas.length}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: camionetas.length,
            itemBuilder: (context, i) => _TarjetaCamioneta(
              camioneta: camionetas[i],
              onVerAsientos: onVerAsientos,
              onCentrarMapa: onCentrarMapa,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE CAMIONETA
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaCamioneta extends StatelessWidget {
  final CamionetaModelo camioneta;
  final void Function(String) onVerAsientos;
  final void Function(dynamic) onCentrarMapa;

  const _TarjetaCamioneta({
    required this.camioneta,
    required this.onVerAsientos,
    required this.onCentrarMapa,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final c = camioneta;

    final colorEstado = switch (c.estado) {
      EstadoCamioneta.disponible => Colors.green,
      EstadoCamioneta.en_camino => colors.primary,
      _ => colors.error,
    };

    final etiquetaEstado = switch (c.estado) {
      EstadoCamioneta.disponible => 'Disponible',
      EstadoCamioneta.en_camino => 'En camino',
      _ => 'Emergencia',
    };

    final hayAsientos = c.asientosLibres > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.airport_shuttle_outlined,
                    size: 20, color: colorEstado),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.id,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
                _BadgeEstado(etiqueta: etiquetaEstado, color: colorEstado),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(c.destino,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurface.withOpacity(0.7)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _IndicadorAsientos(
                    libres: c.asientosLibres, total: c.totalAsientos),
                const Spacer(),
                if (c.ubicacion != null)
                  IconButton(
                    onPressed: () => onCentrarMapa(c.ubicacion),
                    icon: const Icon(Icons.my_location_outlined),
                    iconSize: 20,
                    tooltip: 'Ver en mapa',
                    style: IconButton.styleFrom(
                      foregroundColor: colors.primary,
                      backgroundColor: colors.primaryContainer.withOpacity(0.5),
                      minimumSize: const Size(36, 36),
                    ),
                  ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: hayAsientos ? () => onVerAsientos(c.id) : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    hayAsientos ? 'Ver asientos' : 'Sin cupo',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeEstado extends StatelessWidget {
  final String etiqueta;
  final Color color;
  const _BadgeEstado({required this.etiqueta, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(etiqueta,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _IndicadorAsientos extends StatelessWidget {
  final int libres;
  final int total;
  const _IndicadorAsientos({required this.libres, required this.total});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = libres == 0
        ? colors.error
        : libres <= 3
            ? Colors.orange
            : Colors.green;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_seat_outlined, size: 16, color: color),
        const SizedBox(width: 4),
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                  text: '$libres',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              TextSpan(
                  text: '/$total libres',
                  style: TextStyle(
                      fontSize: 12, color: colors.onSurface.withOpacity(0.6))),
            ],
          ),
        ),
      ],
    );
  }
}
