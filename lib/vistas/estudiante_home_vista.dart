// lib/vistas/estudiante_home_vista.dart
// Busemistas USM v5
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios v5:
//   - Marcadores de parada (La California y USM) son tapeables (GestureDetector)
//   - Al tocar un marcador de parada se abre _ModalInfoParada via showModalBottomSheet
//   - El modal lista en tiempo real (StreamBuilder) todas las camionetas en camino
//     hacia esa parada, con ID, asientos libres y ETA calculado
//   - Header muestra "Empleado" o "Estudiante" segun rol del AuthProvider

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../modelos/camioneta_modelo.dart';
import '../providers/auth_provider.dart';
import '../providers/camioneta_provider.dart';
import 'seleccion_asientos_vista.dart';
import 'monedero_vista.dart';
import 'horarios_vista.dart';
import 'perfil_vista.dart';
import 'login_vista.dart';

const Color _kAzul = Color(0xFF0E004A);

// Coordenadas reales
const LatLng _coordUSM = LatLng(10.491360068207142, -66.78017873573735);
const LatLng _coordLaCalif = LatLng(10.483376, -66.819402);

class EstudianteHomeVista extends StatefulWidget {
  const EstudianteHomeVista({super.key});

  @override
  State<EstudianteHomeVista> createState() => _EstudianteHomeVistaState();
}

class _EstudianteHomeVistaState extends State<EstudianteHomeVista>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  bool _emergenciaActiva = false;

  // Cache de posicion anterior por camioneta para calculo de heading
  final Map<String, LatLng> _posAnterior = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CamionetaProvider>().iniciarStream();
      context.read<AuthProvider>().refrescarDatosUsuario();
    });
  }

  // ── Calcular distancia en metros ─────────────────────────────────
  double _calcularDistanciaMetros(
      double busLat, double busLng, LatLng destino) {
    return Geolocator.distanceBetween(
        busLat, busLng, destino.latitude, destino.longitude);
  }

  // ── Calcular ETA en minutos (40 km/h promedio) ───────────────────
  double _calcularETAMin(double distanciaMetros) {
    const velocidadKmH = 40.0;
    return (distanciaMetros / 1000 / velocidadKmH) * 60;
  }

  String _formatHoraLlegada(double etaMinutos) {
    final llegada = DateTime.now().add(Duration(minutes: etaMinutos.round()));
    final h12 = llegada.hour > 12
        ? llegada.hour - 12
        : llegada.hour == 0
            ? 12
            : llegada.hour;
    final ampm = llegada.hour < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')} $ampm';
  }

  // ── Color dinamico del bus segun ETA y estado ────────────────────
  // Disponible/detenido: gris
  // en_camino ETA < 20: verde
  // en_camino ETA 20-30: amarillo
  // en_camino ETA > 30: rojo
  Color _colorBusPorETA(EstadoCamioneta estado, double? etaMin) {
    if (estado != EstadoCamioneta.en_camino) return Colors.grey.shade500;
    if (etaMin == null) return Colors.green;
    if (etaMin > 30) return Colors.red;
    if (etaMin > 20) return Colors.amber.shade700;
    return Colors.green;
  }

  // ── Heading aproximado entre dos puntos ─────────────────────────
  double _calcularHeading(LatLng origen, LatLng destino) {
    final dLng = destino.longitude - origen.longitude;
    final dLat = destino.latitude - origen.latitude;
    final angulo = math.atan2(dLng, dLat);
    return angulo;
  }

// ── Construir polilineas bus -> destino ─────────────────────────
  List<Polyline> _buildPolylines(List<CamionetaModelo> camionetas) {
    return camionetas.where((c) => c.ubicacion != null).map((c) {
      final busPos = LatLng(c.ubicacion!.latitude, c.ubicacion!.longitude);
      final destino = _destinoLatLng(c.destino);
      final mid = LatLng(
        (busPos.latitude + destino.latitude) / 2,
        (busPos.longitude + destino.longitude) / 2,
      );
      Color lineColor = _kAzul.withOpacity(0.7);

      if (c.estado == 'emergencia') {
        lineColor = Colors.red;
      }

      return Polyline(
        points: [busPos, mid, destino],
        strokeWidth: 3.5,
        color: lineColor,
        // Se elimino isDotted para asegurar compatibilidad con tu version de mapas
      );
    }).toList();
  }

  LatLng _destinoLatLng(String destino) {
    return destino.toLowerCase().contains('usm') ||
            destino.toLowerCase().contains('florencia')
        ? _coordUSM
        : _coordLaCalif;
  }

  String _sentidoTexto(String destino) {
    return destino.toLowerCase().contains('usm') ||
            destino.toLowerCase().contains('florencia')
        ? 'Sentido: USM Sede La Florencia'
        : 'Sentido: Estacion La California';
  }

  // ── Marcadores con color dinamico y rotacion ─────────────────────
  List<Marker> _buildMarkers(
      List<CamionetaModelo> camionetas, Map<String, double?> etaMap) {
    final markers = <Marker>[];

    // Marcador fijo: La California con pin (tapeable -> modal de clustering)
    markers.add(Marker(
      point: _coordLaCalif,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _mostrarModalParada(
          context: context,
          nombreParada: 'Estacion La California',
          keywordDestino: 'california',
          camionetas: camionetas,
          etaMap: etaMap,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.orange.shade700,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.orange.withOpacity(0.4), blurRadius: 6)
              ],
            ),
            child: const Icon(Icons.location_on_rounded,
                color: Colors.white, size: 18),
          ),
          const SizedBox(height: 1),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.orange.shade700,
                borderRadius: BorderRadius.circular(4)),
            child: const Text('La Calif.',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    ));

    // Marcador fijo: USM con birrete (tapeable -> modal de clustering)
    markers.add(Marker(
      point: _coordUSM,
      width: 48,
      height: 48,
      child: GestureDetector(
        onTap: () => _mostrarModalParada(
          context: context,
          nombreParada: 'USM Sede La Florencia',
          keywordDestino: 'usm',
          camionetas: camionetas,
          etaMap: etaMap,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _kAzul,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _kAzul.withOpacity(0.5), blurRadius: 8)
              ],
            ),
            child: const Icon(Icons.school, color: Colors.white, size: 20),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                color: _kAzul, borderRadius: BorderRadius.circular(4)),
            child: const Text('USM',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 7,
                    fontWeight: FontWeight.bold)),
          ),
        ]),
      ),
    ));

    // Marcadores de buses con color dinamico y rotacion
    for (final c in camionetas.where((c) => c.ubicacion != null)) {
      final busPos = LatLng(c.ubicacion!.latitude, c.ubicacion!.longitude);
      final etaMin = etaMap[c.id];
      final color = _colorBusPorETA(c.estado, etaMin);

      // Calcular heading si hay posicion anterior
      double heading = 0;
      final prevPos = _posAnterior[c.id];
      if (prevPos != null) {
        heading = _calcularHeading(prevPos, busPos);
      }
      // Guardar posicion actual para siguiente tick
      _posAnterior[c.id] = busPos;

      markers.add(Marker(
        point: busPos,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _mostrarInfoCamioneta(context, c),
          child: Transform.rotate(
            angle: heading,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: c.estado == EstadoCamioneta.emergencia ? 18 : 8,
                    spreadRadius:
                        c.estado == EstadoCamioneta.emergencia ? 3 : 0,
                  )
                ],
              ),
              child: const Icon(Icons.directions_bus_rounded,
                  color: Colors.white, size: 24),
            ),
          ),
        ),
      ));
    }

    return markers;
  }

  void _mostrarInfoCamioneta(BuildContext context, CamionetaModelo c) {
    Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => SeleccionAsientosVista(camionetaId: c.id)),
    );
  }

  // ── Modal de clustering: informacion de buses en una parada ──────
  // Se abre al tocar el marcador de La California o de la USM.
  // Lista en tiempo real las unidades cuyo destino coincide con la parada.
  // keywordDestino: 'usm' o 'california' para filtrar el campo 'destino'.
  void _mostrarModalParada({
    required BuildContext context,
    required String nombreParada,
    required String keywordDestino,
    required List<CamionetaModelo> camionetas,
    required Map<String, double?> etaMap,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _ModalInfoParada(
        nombreParada: nombreParada,
        keywordDestino: keywordDestino,
        etaMap: etaMap,
        onSeleccionarCamioneta: (id) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => SeleccionAsientosVista(camionetaId: id)),
          );
        },
      ),
    );
  }

  // ── Emergencia ───────────────────────────────────────────────────
  void _mostrarEmergenciaSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BottomSheetEmergenciaEstudiante(
        emergenciaActiva: _emergenciaActiva,
        onEmergencia: (tipo) async {
          Navigator.pop(context);
          await _ejecutarEmergencia(context, tipo);
        },
        onResolver: () async {
          Navigator.pop(context);
          await _resolverEmergencia(context);
        },
      ),
    );
  }

  Future<void> _ejecutarEmergencia(
      BuildContext context, String tipoEmergencia) async {
    try {
      await FirebaseFirestore.instance
          .collection('camionetas')
          .doc('camioneta_01')
          .update({
        'estado': 'emergencia',
        'tipo_emergencia': tipoEmergencia,
        'ts_emergencia': FieldValue.serverTimestamp(),
      });
      setState(() => _emergenciaActiva = true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Emergencia reportada: $tipoEmergencia'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _resolverEmergencia(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('camionetas')
          .doc('camioneta_01')
          .update({
        'estado': 'disponible',
        'tipo_emergencia': FieldValue.delete(),
        'ts_emergencia': FieldValue.delete(),
      });
      setState(() => _emergenciaActiva = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Emergencia resuelta. Unidad disponible.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _cerrarSesion(BuildContext context) {
    context.read<AuthProvider>().cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginVista()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final camProv = context.watch<CamionetaProvider>();
    final primerNombre = (auth.nombreCompleto ?? 'Usuario').split(' ').first;

    // Calcular ETA por camioneta para el mapa
    final Map<String, double?> etaMap = {};
    for (final c in camProv.camionetas) {
      if (c.ubicacion != null) {
        final destino = _destinoLatLng(c.destino);
        final dist = _calcularDistanciaMetros(
            c.ubicacion!.latitude, c.ubicacion!.longitude, destino);
        etaMap[c.id] = _calcularETAMin(dist);
      } else {
        etaMap[c.id] = null;
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(children: [
          // Header
          _HeaderEstudiante(
            primerNombre: primerNombre,
            onLogout: () => _cerrarSesion(context),
            onEmergencia: () => _mostrarEmergenciaSheet(context),
            emergenciaActiva: _emergenciaActiva,
          ),

          // Accesos rapidos
          _AccesosRapidos(
            onMonedero: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const MonederoVista())),
            onHorarios: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const HorariosVista())),
            onPerfil: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PerfilVista())),
          ),

          // Mapa
          Expanded(
            flex: 5,
            child: ClipRRect(
              child: FlutterMap(
                mapController: _mapCtrl,
                options: const MapOptions(
                  initialCenter: _coordUSM,
                  initialZoom: 13.0,
                  maxZoom: 18,
                  minZoom: 10,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.usm.busemistas',
                  ),
                  PolylineLayer(polylines: _buildPolylines(camProv.camionetas)),
                  MarkerLayer(
                      markers: _buildMarkers(camProv.camionetas, etaMap)),
                ],
              ),
            ),
          ),

          // Lista de unidades
          Expanded(
            flex: 4,
            child: _ListaUnidades(
              camProv: camProv,
              etaMap: etaMap,
              calcularDistancia: _calcularDistanciaMetros,
              formatHora: _formatHoraLlegada,
              sentidoTexto: _sentidoTexto,
              destinoLatLng: _destinoLatLng,
              onVerAsientos: (id) => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => SeleccionAsientosVista(camionetaId: id)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderEstudiante extends StatelessWidget {
  final String primerNombre;
  final VoidCallback onLogout;
  final VoidCallback onEmergencia;
  final bool emergenciaActiva;

  const _HeaderEstudiante({
    required this.primerNombre,
    required this.onLogout,
    required this.onEmergencia,
    required this.emergenciaActiva,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _kAzul,
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hola, $primerNombre!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            const Text('Busemistas USM',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        Opacity(
          opacity: 0.85,
          child: GestureDetector(
            onTap: onEmergencia,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color:
                    emergenciaActiva ? Colors.red : Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.warning_rounded,
                    color:
                        emergenciaActiva ? Colors.white : Colors.red.shade200,
                    size: 18),
                const SizedBox(width: 4),
                Text(
                  emergenciaActiva ? 'EMERGENCIA' : 'SOS',
                  style: TextStyle(
                      color:
                          emergenciaActiva ? Colors.white : Colors.red.shade200,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          onPressed: onLogout,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ACCESOS RAPIDOS
// ─────────────────────────────────────────────────────────────────────────────

class _AccesosRapidos extends StatelessWidget {
  final VoidCallback onMonedero;
  final VoidCallback onHorarios;
  final VoidCallback onPerfil;

  const _AccesosRapidos({
    required this.onMonedero,
    required this.onHorarios,
    required this.onPerfil,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kAzul,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: Row(children: [
        _AccesoCard(
            icono: Icons.account_balance_wallet_rounded,
            label: 'Monedero',
            onTap: onMonedero),
        const SizedBox(width: 10),
        _AccesoCard(
            icono: Icons.schedule_rounded,
            label: 'Horarios',
            onTap: onHorarios),
        const SizedBox(width: 10),
        _AccesoCard(
            icono: Icons.person_rounded, label: 'Perfil', onTap: onPerfil),
      ]),
    );
  }
}

class _AccesoCard extends StatelessWidget {
  final IconData icono;
  final String label;
  final VoidCallback onTap;

  const _AccesoCard(
      {required this.icono, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icono, color: Colors.white, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LISTA DE UNIDADES
// ─────────────────────────────────────────────────────────────────────────────

class _ListaUnidades extends StatelessWidget {
  final CamionetaProvider camProv;
  final Map<String, double?> etaMap;
  final double Function(double, double, LatLng) calcularDistancia;
  final String Function(double) formatHora;
  final String Function(String) sentidoTexto;
  final LatLng Function(String) destinoLatLng;
  final void Function(String) onVerAsientos;

  const _ListaUnidades({
    required this.camProv,
    required this.etaMap,
    required this.calcularDistancia,
    required this.formatHora,
    required this.sentidoTexto,
    required this.destinoLatLng,
    required this.onVerAsientos,
  });

  @override
  Widget build(BuildContext context) {
    if (camProv.cargando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (camProv.camionetas.isEmpty) {
      return const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.directions_bus_outlined, size: 48, color: Colors.grey),
          SizedBox(height: 8),
          Text('Sin unidades activas',
              style: TextStyle(color: Colors.grey, fontSize: 14)),
        ]),
      );
    }

    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(children: [
              const Icon(Icons.directions_bus_rounded, color: _kAzul, size: 18),
              const SizedBox(width: 8),
              Text(
                'Unidades Disponibles (${camProv.camionetas.length})',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: _kAzul),
              ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: camProv.camionetas.length,
              itemBuilder: (_, i) {
                final c = camProv.camionetas[i];
                final etaMin = etaMap[c.id];
                final distancia = c.ubicacion != null
                    ? calcularDistancia(c.ubicacion!.latitude,
                        c.ubicacion!.longitude, destinoLatLng(c.destino))
                    : null;
                final horaLlegada = etaMin != null ? formatHora(etaMin) : null;

                return _TarjetaCamionetaV4(
                  camioneta: c,
                  distanciaMetros: distancia,
                  etaMinutos: etaMin,
                  horaLlegada: horaLlegada,
                  sentido: sentidoTexto(c.destino),
                  onVerAsientos: onVerAsientos,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA CAMIONETA V4
// Limpia etiquetas de trafico si el bus NO esta en camino
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaCamionetaV4 extends StatelessWidget {
  final CamionetaModelo camioneta;
  final double? distanciaMetros;
  final double? etaMinutos;
  final String? horaLlegada;
  final String sentido;
  final void Function(String) onVerAsientos;

  const _TarjetaCamionetaV4({
    required this.camioneta,
    required this.distanciaMetros,
    required this.etaMinutos,
    required this.horaLlegada,
    required this.sentido,
    required this.onVerAsientos,
  });

  Color get _colorEstado => switch (camioneta.estado) {
        EstadoCamioneta.disponible => Colors.green,
        EstadoCamioneta.en_camino => _kAzul,
        EstadoCamioneta.emergencia => Colors.red,
        _ => Colors.grey,
      };

  String get _etiquetaEstado => switch (camioneta.estado) {
        EstadoCamioneta.disponible => 'Disponible',
        EstadoCamioneta.en_camino => 'En camino',
        EstadoCamioneta.emergencia => 'Emergencia',
        _ => 'Desconocido',
      };

  // Solo mostrar indicador de trafico si ESTA en camino
  // Si no esta en camino -> null (limpia trafico fantasma)
  Widget? _chipTrafico() {
    if (camioneta.estado != EstadoCamioneta.en_camino) return null;
    if (etaMinutos == null) return null;

    if (etaMinutos! > 30) {
      return _ChipTrafico(
          label: 'Alto Retraso / Cola Fuerte',
          color: Colors.red.shade700,
          icono: Icons.traffic);
    }
    if (etaMinutos! > 20) {
      return _ChipTrafico(
          label: 'Retraso en la via',
          color: Colors.orange.shade700,
          icono: Icons.warning_amber_rounded);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEmergencia = camioneta.estado == EstadoCamioneta.emergencia;
    final chipTrafico = _chipTrafico();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: isEmergencia ? Border.all(color: Colors.red, width: 2) : null,
        boxShadow: isEmergencia
            ? [
                const BoxShadow(
                    color: Colors.red, blurRadius: 10, spreadRadius: 1)
              ]
            : null,
      ),
      child: Card(
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Fila 1: ID + Estado
            Row(children: [
              Icon(Icons.directions_bus_rounded, size: 20, color: _colorEstado),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(camioneta.id,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14))),
              _BadgeEstado(etiqueta: _etiquetaEstado, color: _colorEstado),
            ]),
            const SizedBox(height: 6),

            // Modelo + Color
            Text('${camioneta.modelo} - ${camioneta.color}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 4),

            // Sentido
            Row(children: [
              const Icon(Icons.swap_horiz_rounded, size: 13, color: _kAzul),
              const SizedBox(width: 4),
              Text(sentido,
                  style: const TextStyle(
                      color: _kAzul,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),

            // ETA y distancia (solo si esta en camino)
            if (camioneta.estado == EstadoCamioneta.en_camino &&
                distanciaMetros != null &&
                etaMinutos != null)
              Row(children: [
                const Icon(Icons.schedule_rounded,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${(distanciaMetros! / 1000).toStringAsFixed(1)} km  '
                  '${etaMinutos!.round()} min  Llegada aprox: $horaLlegada',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                ),
              ]),

            // Chip de trafico (solo si en camino y hay retraso)
            if (chipTrafico != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: chipTrafico,
              ),

            const SizedBox(height: 10),

            // Fila final: asientos + boton
            Row(children: [
              _IndicadorAsientos(
                  libres: camioneta.asientosLibres,
                  total: camioneta.totalAsientos),
              const Spacer(),
              FilledButton.tonal(
                onPressed: camioneta.esSeleccionable
                    ? () => onVerAsientos(camioneta.id)
                    : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  backgroundColor: _kAzul,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  camioneta.asientosLibres == 0
                      ? 'Sin cupo'
                      : !camioneta.esSeleccionable
                          ? 'No disponible'
                          : 'Ver asientos',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _ChipTrafico extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icono;

  const _ChipTrafico(
      {required this.label, required this.color, required this.icono});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icono, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ]),
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
    final color = libres == 0
        ? Colors.red
        : libres <= 3
            ? Colors.orange
            : Colors.green;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.event_seat_outlined, size: 16, color: color),
      const SizedBox(width: 4),
      RichText(
        text: TextSpan(children: [
          TextSpan(
              text: '$libres',
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          TextSpan(
              text: '/$total',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET EMERGENCIA ESTUDIANTE
// ─────────────────────────────────────────────────────────────────────────────

class _BottomSheetEmergenciaEstudiante extends StatelessWidget {
  final bool emergenciaActiva;
  final void Function(String) onEmergencia;
  final VoidCallback onResolver;

  const _BottomSheetEmergenciaEstudiante({
    required this.emergenciaActiva,
    required this.onEmergencia,
    required this.onResolver,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_rounded, color: Colors.red, size: 26),
            const SizedBox(width: 10),
            Text(
              emergenciaActiva ? 'Resolver Emergencia' : 'Reportar Emergencia',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
            ),
          ]),
          const SizedBox(height: 16),
          if (emergenciaActiva) ...[
            _OpcionEmergencia(
              icono: Icons.check_circle_outline_rounded,
              label: 'Resolver Emergencia',
              subtitulo: 'Libera la unidad y los asientos',
              color: Colors.green,
              onTap: onResolver,
            ),
          ] else ...[
            _OpcionEmergencia(
              icono: Icons.personal_injury_rounded,
              label: 'Reportar Desmayo',
              subtitulo: 'Un pasajero se encuentra desmayado',
              color: Colors.red,
              onTap: () => onEmergencia('Desmayo de pasajero'),
            ),
            const SizedBox(height: 8),
            _OpcionEmergencia(
              icono: Icons.sick_rounded,
              label: 'Descompensacion / Vomito',
              subtitulo: 'Pasajero con malestar fisico',
              color: Colors.orange,
              onTap: () => onEmergencia('Descompensacion'),
            ),
            const SizedBox(height: 8),
            _OpcionEmergencia(
              icono: Icons.call_rounded,
              label: 'Llamar al 911 USM',
              subtitulo: 'Contactar seguridad universitaria',
              color: Colors.blue.shade700,
              onTap: () => onEmergencia('Llamada 911 USM'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpcionEmergencia extends StatelessWidget {
  final IconData icono;
  final String label;
  final String subtitulo;
  final Color color;
  final VoidCallback onTap;

  const _OpcionEmergencia({
    required this.icono,
    required this.label,
    required this.subtitulo,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(icono, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              Text(subtitulo,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ]),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withOpacity(0.5), size: 14),
        ]),
      ),
    );
  }
}

// =============================================================================
// MODAL DE CLUSTERING / INFO DE PARADA
// =============================================================================
// Se muestra al tocar los marcadores fijos de La California o la USM.
// Usa StreamBuilder para listar en tiempo real las camionetas que se dirigen
// hacia esa parada, mostrando: ID, sentido, asientos libres y ETA estimado.
// El usuario puede tocar una fila para ir directo a la seleccion de asientos.
// =============================================================================

class _ModalInfoParada extends StatelessWidget {
  // Nombre descriptivo de la parada (para mostrar en el encabezado)
  final String nombreParada;
  // Keyword para filtrar el campo 'destino' en Firestore (ej. 'usm' o 'california')
  final String keywordDestino;
  // Mapa de ETA ya calculado por el parent (evita recalcular aqui)
  final Map<String, double?> etaMap;
  // Callback cuando el usuario toca una fila de camioneta
  final void Function(String camionetaId) onSeleccionarCamioneta;

  const _ModalInfoParada({
    required this.nombreParada,
    required this.keywordDestino,
    required this.etaMap,
    required this.onSeleccionarCamioneta,
  });

  // Cuenta los asientos libres en el mapa de asientos del documento
  int _asientosLibres(Map<String, dynamic> asientos) {
    int libres = 0;
    for (int i = 1; i <= 24; i++) {
      final data = asientos['$i'];
      if (data == null) {
        libres++;
      } else if (data is Map && data['ocupado'] != true) {
        libres++;
      }
    }
    return libres;
  }

  // Formatea el ETA en minutos como texto legible
  String _formatEta(double? etaMin) {
    if (etaMin == null) return 'N/A';
    if (etaMin < 1) return 'Llegando';
    return '~${etaMin.round()} min';
  }

  // Color del chip de ETA segun urgencia
  Color _colorEta(double? etaMin) {
    if (etaMin == null) return Colors.grey;
    if (etaMin < 5) return Colors.green.shade600;
    if (etaMin < 15) return Colors.orange.shade600;
    return Colors.red.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final esUSM = keywordDestino.contains('usm');
    final colorParada = esUSM ? _kAzul : Colors.orange.shade700;
    final iconoParada = esUSM ? Icons.school : Icons.location_on_rounded;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      builder: (_, scrollCtrl) {
        return Column(children: [
          // Handle de arrastre
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Encabezado de la parada
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorParada.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorParada.withOpacity(0.2)),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    BoxDecoration(color: colorParada, shape: BoxShape.circle),
                child: Icon(iconoParada, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombreParada,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: colorParada)),
                      const SizedBox(height: 2),
                      Text('Toca una unidad para reservar tu asiento',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade600)),
                    ]),
              ),
            ]),
          ),

          // Lista de camionetas en camino via StreamBuilder
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('camionetas')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                // Filtrar camionetas con destino a esta parada
                // Solo se muestran las que estan disponibles o en camino
                final docs = snap.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final destino =
                      (data['destino'] as String? ?? '').toLowerCase();
                  final estado = data['estado'] as String? ?? '';
                  final destinoCoincide = destino.contains(keywordDestino);
                  final estadoValido =
                      estado == 'disponible' || estado == 'en_camino';
                  return destinoCoincide && estadoValido;
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_bus_outlined,
                            size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('No hay unidades en camino\nhacia esta parada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 14)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  controller: scrollCtrl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final id = doc.id;
                    final modelo = data['modelo'] as String? ?? 'Bus';
                    final color = data['color'] as String? ?? '';
                    final estado = data['estado'] as String? ?? '';
                    final destino = data['destino'] as String? ?? '';
                    final asientos =
                        (data['asientos'] as Map<String, dynamic>?) ?? {};
                    final libres = _asientosLibres(asientos);
                    final eta = etaMap[id];

                    final colorEstado = estado == 'en_camino'
                        ? Colors.blue.shade600
                        : Colors.green.shade600;
                    final textoEstado =
                        estado == 'en_camino' ? 'En camino' : 'En parada';

                    return InkWell(
                      onTap:
                          libres > 0 ? () => onSeleccionarCamioneta(id) : null,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              libres > 0 ? Colors.white : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: libres > 0
                                  ? colorParada.withOpacity(0.2)
                                  : Colors.grey.shade200),
                          boxShadow: libres > 0
                              ? [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ]
                              : null,
                        ),
                        child: Row(children: [
                          // Icono del bus con color de estado
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorEstado.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.directions_bus_rounded,
                                color: colorEstado, size: 24),
                          ),
                          const SizedBox(width: 12),

                          // Info principal
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(id,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: _kAzul)),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorEstado.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(textoEstado,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: colorEstado,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ]),
                                  const SizedBox(height: 3),
                                  Text('$modelo - $color  |  $destino',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600)),
                                ]),
                          ),

                          // Columna ETA + asientos
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // ETA
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _colorEta(eta).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _formatEta(eta),
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _colorEta(eta),
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Asientos libres
                                Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.event_seat_outlined,
                                      size: 12,
                                      color: libres > 0
                                          ? Colors.green.shade600
                                          : Colors.red.shade400),
                                  const SizedBox(width: 3),
                                  Text(
                                    '$libres libres',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: libres > 0
                                            ? Colors.green.shade700
                                            : Colors.red.shade500,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ]),
                              ]),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Nota al pie
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Text(
              'ETA calculado a 40 km/h promedio. Puede variar segun el trafico.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ),
        ]);
      },
    );
  }
}
