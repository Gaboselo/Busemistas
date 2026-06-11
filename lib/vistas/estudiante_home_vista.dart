// lib/vistas/estudiante_home_vista.dart
// Busemistas USM v6 - REESCRITURA DEFINITIVA
// REGLA: variables/keys sin tildes. Textos de UI con ortografia correcta (tildes y enie).
// Puntos implementados:
//   1. _PantallaViajeActivo COMPLETA: mapa, SOS, mensajes dinamicos, auto-retorno
//   5. Dialogo obligatorio de visitante con Dropdown + TextField
//   6. Lazy init de 24 asientos en CamionetaProvider (ver ese archivo)
//   7. onTap de buses en movimiento DESHABILITADO; solo paradas son tapeables

import 'dart:async';
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
import 'perfil_vista.dart';
import 'login_vista.dart';
import '../servicios/ruta_servicio.dart';

const Color _kAzul = Color(0xFF003380);
const LatLng _coordUSM = LatLng(10.491360068207142, -66.78017873573735);
const LatLng _coordLaCalif = LatLng(10.483376, -66.819402);

// =============================================================================
// WIDGET PRINCIPAL
// =============================================================================

class EstudianteHomeVista extends StatefulWidget {
  const EstudianteHomeVista({super.key});
  @override
  State<EstudianteHomeVista> createState() => _EstudianteHomeVistaState();
}

// =============================================================================
// STATE PRINCIPAL
// =============================================================================

class _EstudianteHomeVistaState extends State<EstudianteHomeVista>
    with TickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  final Map<String, LatLng> _posAnterior = {};
  final RutaServicio _rutaServicio = RutaServicio();
  final Map<String, List<LatLng>> _cacheRutas = {};

  // Controla si ya se mostro el dialogo de visitante en esta sesion
  bool _dialogoVisitanteMostrado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CamionetaProvider>().iniciarStream();
      context.read<AuthProvider>().refrescarDatosUsuario();
      _verificarDialogoVisitante();
    });
  }

  // ---------------------------------------------------------------------------
  // FLUJO VISITANTE: dialogo obligatorio de razon de visita
  // Se dispara una vez por sesion. Guarda en 'usuarios/razon_visita'.
  // ---------------------------------------------------------------------------
  Future<void> _verificarDialogoVisitante() async {
    final auth = context.read<AuthProvider>();
    if (auth.rolSeleccionado != RolUsuario.visitante) return;
    if (_dialogoVisitanteMostrado) return;
    _dialogoVisitanteMostrado = true;
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    await _mostrarDialogoRazonVisita();
  }

  Future<void> _mostrarDialogoRazonVisita() async {
    String? razonSeleccionada;
    final otroCtrl = TextEditingController();
    bool muestraOtro = false;

    const opciones = [
      'Trámites académicos',
      'Evento',
      'Familiar',
      'Otra',
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          return AlertDialog(
            icon: const Icon(Icons.person_pin_circle_outlined,
                color: _kAzul, size: 36),
            title: const Text('Razón de tu visita'),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text(
                'Indícanos el motivo de tu visita a la Universidad Santa María.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: opciones
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: (v) {
                  setStateDialog(() {
                    razonSeleccionada = v;
                    muestraOtro = v == 'Otra';
                  });
                },
              ),
              if (muestraOtro) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: otroCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Describe el motivo',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                  ),
                ),
              ],
            ]),
            actions: [
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kAzul),
                onPressed: () async {
                  if (razonSeleccionada == null) return;
                  final razonFinal = razonSeleccionada == 'Otra'
                      ? otroCtrl.text.trim().isEmpty
                          ? 'Otra'
                          : otroCtrl.text.trim()
                      : razonSeleccionada!;
                  Navigator.pop(ctx);
                  final cedula =
                      context.read<AuthProvider>().cedulaActual ?? '';
                  if (cedula.isNotEmpty) {
                    await FirebaseFirestore.instance
                        .collection('usuarios')
                        .doc(cedula)
                        .update({'razon_visita': razonFinal});
                  }
                },
                child: const Text('Continuar'),
              ),
            ],
          );
        });
      },
    );
    otroCtrl.dispose();
  }

  // ---------------------------------------------------------------------------
  // HELPERS MATEMATICOS
  // ---------------------------------------------------------------------------

  double _calcularDistanciaMetros(
      double busLat, double busLng, LatLng destino) {
    return Geolocator.distanceBetween(
        busLat, busLng, destino.latitude, destino.longitude);
  }

  double _calcularETAMin(double distanciaMetros) {
    const velocidadKmH = 40.0;
    return (distanciaMetros / 1000.0 / velocidadKmH) * 60.0;
  }

  String _formatHoraLlegada(double etaMinutos) {
    final llegada = DateTime.now().add(Duration(minutes: etaMinutos.round()));
    final h = llegada.hour;
    final h12 = h > 12 ? h - 12 : (h == 0 ? 12 : h);
    final ampm = h < 12 ? 'AM' : 'PM';
    return '${h12.toString().padLeft(2, '0')}:${llegada.minute.toString().padLeft(2, '0')} $ampm';
  }

  LatLng _destinoLatLng(String destino) {
    final d = destino.toLowerCase();
    return (d.contains('usm') || d.contains('florencia'))
        ? _coordUSM
        : _coordLaCalif;
  }

  String _sentidoTexto(String destino) {
    final d = destino.toLowerCase();
    return (d.contains('usm') || d.contains('florencia'))
        ? 'Sentido: USM Sede La Florencia'
        : 'Sentido: Estacion La California';
  }

  double _calcularHeading(LatLng origen, LatLng destino) {
    final dLng = destino.longitude - origen.longitude;
    final dLat = destino.latitude - origen.latitude;
    return math.atan2(dLng, dLat);
  }

  Color _colorBusPorETA(EstadoCamioneta estado, double? etaMin) {
    if (estado == EstadoCamioneta.emergencia) return Colors.red;
    if (estado != EstadoCamioneta.en_camino) return Colors.grey.shade500;
    if (etaMin == null) return Colors.green;
    if (etaMin > 30) return Colors.red;
    if (etaMin > 20) return Colors.amber.shade700;
    return Colors.green;
  }

  // ---------------------------------------------------------------------------
  // POLILÍNEAS CON OSRM + CACHE
  // ---------------------------------------------------------------------------

  List<Polyline> _buildPolylines(List<CamionetaModelo> camionetas) {
    final result = <Polyline>[];
    for (final c in camionetas) {
      if (c.ubicacion == null) continue;
      final busPos = LatLng(c.ubicacion!.latitude, c.ubicacion!.longitude);
      final destino = _destinoLatLng(c.destino);

      Color lineColor = _kAzul.withValues(alpha: 0.7);
      if (c.estado == EstadoCamioneta.emergencia) {
        lineColor = Colors.red;
      } else if (c.estado == EstadoCamioneta.en_camino) {
        final dist = _calcularDistanciaMetros(
            c.ubicacion!.latitude, c.ubicacion!.longitude, destino);
        final eta = _calcularETAMin(dist);
        if (eta > 30)
          lineColor = Colors.red.withValues(alpha: 0.8);
        else if (eta > 15) lineColor = Colors.orange.withValues(alpha: 0.8);
      }

      final llaveCache =
          '${busPos.latitude.toStringAsFixed(4)},${busPos.longitude.toStringAsFixed(4)}';

      // Solo dibujar polilínea cuando OSRM ya descargó la ruta real.
      // Antes de que llegue la ruta, no mostrar ninguna línea (evita
      // la línea recta fantasma que aparecía de la nada).
      if (_cacheRutas.containsKey(llaveCache)) {
        final puntos = _cacheRutas[llaveCache]!;
        if (puntos.length > 1) {
          result.add(
              Polyline(points: puntos, strokeWidth: 3.5, color: lineColor));
        }
      } else {
        // Iniciar descarga de ruta en background sin mostrar línea provisional
        _rutaServicio.obtenerRuta(busPos, destino).then((pts) {
          if (mounted && pts.length > 1) {
            setState(() => _cacheRutas[llaveCache] = pts);
          }
        }).catchError((e) => debugPrint('OSRM: $e'));
        // No agregamos ningún Polyline aquí — sin líneas hasta que OSRM responda
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // MARCADORES — buses SIN onTap; solo paradas son tapeables (punto 7)
  // ---------------------------------------------------------------------------

  List<Marker> _buildMarkers(
      List<CamionetaModelo> camionetas, Map<String, double?> etaMap) {
    final markers = <Marker>[];

    // Parada La California — tapeable (azul claro)
    markers.add(Marker(
      point: _coordLaCalif,
      width: 52,
      height: 52,
      child: GestureDetector(
        onTap: () => _mostrarModalParada(
          nombreParada: 'Estación La California',
          keywordDestino: 'california',
          etaMap: etaMap,
        ),
        child: _MarkerParada(
          label: 'La Calif.',
          color: const Color(0xFF1565C0),
          icono: Icons.location_on_rounded,
        ),
      ),
    ));

    // Parada USM — tapeable (azul claro)
    markers.add(Marker(
      point: _coordUSM,
      width: 52,
      height: 52,
      child: GestureDetector(
        onTap: () => _mostrarModalParada(
          nombreParada: 'USM Sede La Florencia',
          keywordDestino: 'usm',
          etaMap: etaMap,
        ),
        child: _MarkerParada(
          label: 'USM',
          color: const Color(0xFF1565C0),
          icono: Icons.school,
        ),
      ),
    ));

    // Buses — SIN onTap. Solo se muestra el icono cuando está EN CAMINO
    // o EMERGENCIA. Si está "disponible" (parado en parada), se oculta para
    // no tapar el marcador de la parada.
    for (final c in camionetas) {
      if (c.ubicacion == null) continue;
      // No mostrar icono si el bus está disponible/parado en la parada
      if (c.estado == EstadoCamioneta.disponible) continue;

      final busPos = LatLng(c.ubicacion!.latitude, c.ubicacion!.longitude);
      final etaMin = etaMap[c.id];
      final color = _colorBusPorETA(c.estado, etaMin);

      double heading = 0.0;
      final prev = _posAnterior[c.id];
      if (prev != null) heading = _calcularHeading(prev, busPos);
      _posAnterior[c.id] = busPos;

      final esEmergencia = c.estado == EstadoCamioneta.emergencia;
      markers.add(Marker(
        point: busPos,
        width: 44,
        height: 44,
        child: Transform.rotate(
          angle: heading,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: esEmergencia ? 18 : 8,
                  spreadRadius: esEmergencia ? 3 : 0,
                ),
              ],
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: Colors.white, size: 24),
          ),
        ),
      ));
    }
    return markers;
  }

  // ---------------------------------------------------------------------------
  // MODAL DE CLUSTERING
  // ---------------------------------------------------------------------------

  void _mostrarModalParada({
    required String nombreParada,
    required String keywordDestino,
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

  void _cerrarSesion() {
    context.read<AuthProvider>().cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginVista()),
      (_) => false,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD PRINCIPAL
  // Detecta viaje activo en tiempo real. Si existe -> _PantallaViajeActivo.
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final camProv = context.watch<CamionetaProvider>();
    final primerNombre = (auth.nombreCompleto ?? 'Usuario').split(' ').first;
    final cedula = auth.cedulaActual ?? '';

    final Map<String, double?> etaMap = {};
    for (final c in camProv.camionetas) {
      if (c.ubicacion != null) {
        final dest = _destinoLatLng(c.destino);
        final dist = _calcularDistanciaMetros(
            c.ubicacion!.latitude, c.ubicacion!.longitude, dest);
        etaMap[c.id] = _calcularETAMin(dist);
      } else {
        etaMap[c.id] = null;
      }
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('camionetas').snapshots(),
      builder: (context, snap) {
        String? camionetaActivaId;
        String? estadoViaje;
        String? destinoViaje;
        double? etaViaje;

        if (snap.hasData && cedula.isNotEmpty) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final asientos = (data['asientos'] as Map<String, dynamic>?) ?? {};
            final tieneAsiento = asientos.values.any((v) =>
                v is Map &&
                v['ocupado'] == true &&
                v['cedula_pasajero'] == cedula);
            if (tieneAsiento) {
              camionetaActivaId = doc.id;
              estadoViaje = data['estado'] as String? ?? '';
              destinoViaje = data['destino'] as String? ?? '';
              final lat = (data['latitud'] as num?)?.toDouble();
              final lng = (data['longitud'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                final dest = _destinoLatLng(destinoViaje);
                final dist = _calcularDistanciaMetros(lat, lng, dest);
                etaViaje = _calcularETAMin(dist);
              }
              break;
            }
          }
        }

        // PANTALLA DE VIAJE ACTIVO
        if (camionetaActivaId != null &&
            estadoViaje != 'terminado' &&
            estadoViaje != 'disponible') {
          return _PantallaViajeActivo(
            camionetaId: camionetaActivaId,
            estado: estadoViaje ?? '',
            destino: destinoViaje ?? '',
            etaMinutos: etaViaje,
            cedula: cedula,
            primerNombre: primerNombre,
            buildPolylines: _buildPolylines,
            cacheRutas: _cacheRutas,
            rutaServicio: _rutaServicio,
          );
        }

        // HOME NORMAL
        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          body: SafeArea(
            child: Column(children: [
              _HeaderEstudiante(
                primerNombre: primerNombre,
                rol: auth.rolSeleccionado,
                onLogout: _cerrarSesion,
              ),
              _AccesosRapidos(
                onMonedero: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const MonederoVista())),
                onPerfil: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PerfilVista())),
              ),
              Expanded(
                flex: 5,
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
                    PolylineLayer(
                        polylines: _buildPolylines(camProv.camionetas)),
                    MarkerLayer(
                        markers: _buildMarkers(camProv.camionetas, etaMap)),
                  ],
                ),
              ),
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
                        builder: (_) =>
                            SeleccionAsientosVista(camionetaId: id)),
                  ),
                ),
              ),
            ]),
          ),
        );
      },
    );
  }
}

// =============================================================================
// PANTALLA DE VIAJE ACTIVO
// Reemplaza TODA la UI mientras el estudiante tenga asiento reservado.
// Muestra: mapa con ruta OSRM, mensajes dinamicos, SOS, boton Cancelar.
// =============================================================================

class _PantallaViajeActivo extends StatefulWidget {
  final String camionetaId;
  final String estado;
  final String destino;
  final double? etaMinutos;
  final String cedula;
  final String primerNombre;
  // Se pasan las funciones del parent para reutilizar el mismo cache OSRM
  final List<Polyline> Function(List<CamionetaModelo>) buildPolylines;
  final Map<String, List<LatLng>> cacheRutas;
  final RutaServicio rutaServicio;

  const _PantallaViajeActivo({
    required this.camionetaId,
    required this.estado,
    required this.destino,
    required this.etaMinutos,
    required this.cedula,
    required this.primerNombre,
    required this.buildPolylines,
    required this.cacheRutas,
    required this.rutaServicio,
  });

  @override
  State<_PantallaViajeActivo> createState() => _PantallaViajeActivoState();
}

class _PantallaViajeActivoState extends State<_PantallaViajeActivo>
    with TickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MapController _mapCtrl = MapController();

  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  // Controla si ya empezamos el temporizador de retorno automatico
  bool _retornoIniciado = false;

  // Estado local sincronizado con Firestore via StreamBuilder interno
  String _estadoLocal = '';
  String _destinoLocal = '';
  double? _etaLocal;

  @override
  void initState() {
    super.initState();
    _estadoLocal = widget.estado;
    _destinoLocal = widget.destino;
    _etaLocal = widget.etaMinutos;

    _pulseCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // AVISO DE TRÁFICO PARA EL PANEL DE VIAJE ACTIVO
  // Lee trafico_denso y nivel_trafico del documento de Firestore en tiempo real
  // ---------------------------------------------------------------------------
  List<Widget> _buildTrafficBanner(Map<String, dynamic> data) {
    final trafico = data['trafico_denso'] as bool? ?? false;
    final nivel = data['nivel_trafico'] as String? ?? 'bajo';
    final hayTrafico = trafico || nivel == 'medio' || nivel == 'alto';
    if (!hayTrafico) return [];

    final Color color;
    final String mensaje;
    final IconData icono;
    if (nivel == 'alto' || trafico) {
      color = Colors.red.shade700;
      mensaje = '🚨 Tráfico intenso — ETA aumentado';
      icono = Icons.traffic_rounded;
    } else {
      color = Colors.orange.shade700;
      mensaje = '⚠️ Tráfico moderado en la vía';
      icono = Icons.warning_amber_rounded;
    }

    return [
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          Icon(icono, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(mensaje,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // LOGICA DE MENSAJES DINAMICOS (punto 1)
  // ---------------------------------------------------------------------------

  // Umbral en metros para mostrar "Llegando"
  static const double _kUmbralLlegando = 300.0;

  String get _mensajePrincipal {
    if (_estadoLocal == 'terminado') return '¡Muchas gracias por preferirnos!';
    if (_etaLocal != null &&
        _etaLocal! <= (_kUmbralLlegando / 1000 / 40 * 60)) {
      return '¡Llegando!';
    }
    if (_estadoLocal == 'en_camino') return '¡Feliz viaje!';
    if (_estadoLocal == 'emergencia') return '¡Emergencia activa!';
    return '¡Feliz viaje!';
  }

  String get _etiquetaDestino {
    final d = _destinoLocal.toLowerCase();
    if (d.contains('usm') || d.contains('florencia')) {
      return 'En camino a: Universidad Santa María';
    }
    return 'En camino a: La California';
  }

  String get _badgeEstado {
    if (_estadoLocal == 'terminado') return 'Viaje finalizado';
    if (_etaLocal != null &&
        _etaLocal! <= (_kUmbralLlegando / 1000 / 40 * 60)) {
      return 'Llegando';
    }
    if (_estadoLocal == 'en_camino') return 'En camino';
    if (_estadoLocal == 'emergencia') return 'Emergencia';
    return 'Esperando salida';
  }

  Color get _colorBadge {
    if (_estadoLocal == 'terminado') return Colors.teal;
    if (_estadoLocal == 'emergencia') return Colors.red;
    if (_estadoLocal == 'en_camino') return Colors.green.shade600;
    return Colors.orange.shade600;
  }

  // ---------------------------------------------------------------------------
  // RETORNO AUTOMATICO CUANDO EL CONDUCTOR FINALIZA EL VIAJE (punto 1)
  // Cuenta 3 segundos y vuelve al Home sin accion del usuario.
  // ---------------------------------------------------------------------------
  void _iniciarRetornoAutomatico() {
    if (_retornoIniciado) return;
    _retornoIniciado = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        // El StreamBuilder del parent dejara de detectar asiento activo
        // porque el conductor limpio los asientos, entonces la UI vuelve
        // automaticamente. Aqui forzamos la actualizacion del provider.
        context.read<AuthProvider>().refrescarDatosUsuario();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // SOS (solo visible aqui)
  // ---------------------------------------------------------------------------
  Future<void> _activarSOS() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.warning_rounded, color: Colors.red, size: 40),
        title: const Text('Activar Emergencia SOS'),
        content: const Text(
          'Esto alertará a control central con la ubicación exacta '
          'de la unidad y la marcará como emergencia.\n\n'
          '¿Confirmar emergencia?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('SOS — Activar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;
    try {
      await _db.collection('camionetas').doc(widget.camionetaId).update({
        'estado': 'emergencia',
        'tipo_emergencia': 'SOS Pasajero — C.I. ${widget.cedula}',
        'ts_emergencia': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('¡SOS activado! Control central fue notificado.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final camProv = context.watch<CamionetaProvider>();

    return StreamBuilder<DocumentSnapshot>(
      stream: _db.collection('camionetas').doc(widget.camionetaId).snapshots(),
      builder: (context, snap) {
        // Sincronizar estado local con Firestore en tiempo real
        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          _estadoLocal = data['estado'] as String? ?? '';
          _destinoLocal = data['destino'] as String? ?? widget.destino;
          final lat = (data['latitud'] as num?)?.toDouble();
          final lng = (data['longitud'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            final d = _destinoLocal.toLowerCase();
            final destLatLng = (d.contains('usm') || d.contains('florencia'))
                ? _coordUSM
                : _coordLaCalif;
            final dist = Geolocator.distanceBetween(
                lat, lng, destLatLng.latitude, destLatLng.longitude);
            // Factor de tráfico: si trafico_denso == true, aumentar ETA 40%
            final trafico = data['trafico_denso'] as bool? ?? false;
            final nivelTrafico = data['nivel_trafico'] as String? ?? 'bajo';
            double factor = 1.0;
            if (trafico || nivelTrafico == 'alto')
              factor = 1.7;
            else if (nivelTrafico == 'medio') factor = 1.3;
            _etaLocal = ((dist / 1000.0 / 40.0) * 60.0) * factor;
          }
        }

        // Iniciar retorno automatico cuando el viaje termina
        if (_estadoLocal == 'terminado') {
          _iniciarRetornoAutomatico();
        }

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // ── CAPA 1: MAPA A PANTALLA COMPLETA ──────────────────
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapCtrl,
                  options: MapOptions(
                    initialCenter: _coordUSM,
                    initialZoom: 14.0,
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
                    // Polilíneas OSRM (reutiliza el mismo cache del parent)
                    PolylineLayer(
                        polylines: widget.buildPolylines(camProv.camionetas)),
                    // Marcadores de parada (sin buses clicables)
                    MarkerLayer(markers: [
                      Marker(
                        point: _coordLaCalif,
                        width: 44,
                        height: 44,
                        child: _MarkerParada(
                          label: 'La Calif.',
                          color: Colors.orange.shade700,
                          icono: Icons.location_on_rounded,
                        ),
                      ),
                      Marker(
                        point: _coordUSM,
                        width: 44,
                        height: 44,
                        child: _MarkerParada(
                          label: 'USM',
                          color: _kAzul,
                          icono: Icons.school,
                        ),
                      ),
                      // Bus activo en tiempo real
                      ...camProv.camionetas
                          .where((c) =>
                              c.id == widget.camionetaId && c.ubicacion != null)
                          .map((c) {
                        final p = LatLng(
                            c.ubicacion!.latitude, c.ubicacion!.longitude);
                        return Marker(
                          point: p,
                          width: 50,
                          height: 50,
                          child: Container(
                            decoration: BoxDecoration(
                              color: _colorBadge,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                    color: _colorBadge.withValues(alpha: 0.5),
                                    blurRadius: 10)
                              ],
                            ),
                            child: const Icon(Icons.directions_bus_rounded,
                                color: Colors.white, size: 26),
                          ),
                        );
                      }),
                    ]),
                  ],
                ),
              ),

              // ── CAPA 2: PANEL SUPERIOR (mensaje principal) ─────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Badge de estado dinamico
                          Row(children: [
                            AnimatedBuilder(
                              animation: _pulseAnim,
                              builder: (_, __) => Transform.scale(
                                scale: _pulseAnim.value,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _colorBadge.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color:
                                            _colorBadge.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                              color: _colorBadge,
                                              shape: BoxShape.circle),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(_badgeEstado,
                                            style: TextStyle(
                                                color: _colorBadge,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12)),
                                      ]),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text('Unidad: ${widget.camionetaId}',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade600)),
                          ]),
                          const SizedBox(height: 10),

                          // Mensaje principal en grande
                          Text(
                            _mensajePrincipal,
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: _estadoLocal == 'terminado'
                                  ? Colors.teal
                                  : _kAzul,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // Etiqueta de destino
                          if (_estadoLocal != 'terminado')
                            Row(children: [
                              Icon(Icons.navigation_outlined,
                                  size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 6),
                              Text(
                                _etiquetaDestino,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade700,
                                    fontWeight: FontWeight.w500),
                              ),
                            ]),

                          // ETA
                          if (_etaLocal != null &&
                              _estadoLocal == 'en_camino') ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.timer_outlined,
                                  size: 14, color: Colors.grey.shade500),
                              const SizedBox(width: 6),
                              Text(
                                'ETA: ~${_etaLocal!.round()} minutos',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ]),
                          ],

                          // AVISO DE TRÁFICO — se lee directo del stream
                          if (snap.hasData && snap.data!.exists)
                            ..._buildTrafficBanner(
                              snap.data!.data() as Map<String, dynamic>,
                            ),

                          // Mensaje de retorno si termino
                          if (_estadoLocal == 'terminado')
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                'Volviendo a la pantalla principal...',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.teal.shade600),
                              ),
                            ),
                        ]),
                  ),
                ),
              ),

              // ── CAPA 3: PANEL INFERIOR (SOS + Cancelar) ────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.97),
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, -4))
                      ],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      // Linea de agarre
                      Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),

                      // Boton SOS — solo aqui, nunca en el Home general
                      AnimatedBuilder(
                        animation: _pulseAnim,
                        builder: (_, __) => GestureDetector(
                          onTap: _activarSOS,
                          child: Opacity(
                            opacity: _pulseAnim.value,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.red.withValues(alpha: 0.4),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4))
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.warning_rounded,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 10),
                                  Text('SOS — Emergencia',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Boton Cancelar viaje
                      OutlinedButton.icon(
                        onPressed: _estadoLocal == 'terminado'
                            ? null
                            : () {
                                ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                  content: Text(
                                    'Hable con el conductor para que este le devuelva su dinero.',
                                  ),
                                  backgroundColor: Colors.orange,
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 5),
                                ));
                              },
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.red),
                        label: const Text('Cancelar viaje',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Texto informativo fijo debajo del boton
                      Text(
                        'Hable con el conductor para que este le devuelva su dinero.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500),
                        textAlign: TextAlign.center,
                      ),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// WIDGETS REUTILIZABLES
// =============================================================================

// Marcador visual de parada (pin + etiqueta)
class _MarkerParada extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icono;
  const _MarkerParada(
      {required this.label, required this.color, required this.icono});

  @override
  Widget build(BuildContext context) {
    // FittedBox evita el overflow "BOTTOM OVERFLOWED" cuando el Column
    // supera la altura asignada por el Marker (52px)
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)
            ],
          ),
          child: Icon(icono, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(4)),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 7,
                  fontWeight: FontWeight.bold)),
        ),
      ]),
    );
  }
}

class _HeaderEstudiante extends StatelessWidget {
  final String primerNombre;
  final VoidCallback onLogout;
  final RolUsuario? rol;
  const _HeaderEstudiante(
      {required this.primerNombre, required this.onLogout, required this.rol});

  @override
  Widget build(BuildContext context) {
    final esEmpleado = rol == RolUsuario.empleado;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _kAzul,
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('¡Hola, $primerNombre!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold)),
            Text(
              switch (rol) {
                RolUsuario.empleado => 'Empleado — Busemistas USM',
                RolUsuario.visitante => 'Visitante — Busemistas USM',
                _ => 'Estudiante — Busemistas USM',
              },
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ]),
        ),
        IconButton(
          onPressed: onLogout,
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
        ),
      ]),
    );
  }
}

class _AccesosRapidos extends StatelessWidget {
  final VoidCallback onMonedero;
  final VoidCallback onPerfil;
  const _AccesosRapidos({required this.onMonedero, required this.onPerfil});

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
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
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

// =============================================================================
// LISTA DE UNIDADES
// =============================================================================

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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
    );
  }
}

// =============================================================================
// TARJETA CAMIONETA
// =============================================================================

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

  Widget? _chipTrafico() {
    if (camioneta.estado != EstadoCamioneta.en_camino) return null;
    if (etaMinutos == null) return null;
    if (etaMinutos! > 30) {
      return _ChipTrafico(
          label: 'Alto Retraso / Cola',
          color: Colors.red.shade700,
          icono: Icons.traffic);
    }
    if (etaMinutos! > 20) {
      return _ChipTrafico(
          label: 'Retraso en la vía',
          color: Colors.orange.shade700,
          icono: Icons.warning_amber_rounded);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isEmergencia = camioneta.estado == EstadoCamioneta.emergencia;
    final chip = _chipTrafico();
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
            Text('${camioneta.modelo} — ${camioneta.color}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 4),
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
            if (camioneta.estado == EstadoCamioneta.en_camino &&
                distanciaMetros != null &&
                etaMinutos != null)
              Row(children: [
                const Icon(Icons.schedule_rounded,
                    size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  '${(distanciaMetros! / 1000).toStringAsFixed(1)} km  '
                  '${etaMinutos!.round()} min  Llegada: $horaLlegada',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
                ),
              ]),
            if (chip != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: chip),
            const SizedBox(height: 10),
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

// =============================================================================
// MODAL DE CLUSTERING
// =============================================================================

class _ModalInfoParada extends StatelessWidget {
  final String nombreParada;
  final String keywordDestino;
  final Map<String, double?> etaMap;
  final void Function(String) onSeleccionarCamioneta;

  const _ModalInfoParada({
    required this.nombreParada,
    required this.keywordDestino,
    required this.etaMap,
    required this.onSeleccionarCamioneta,
  });

  int _asientosLibres(Map<String, dynamic> asientos) {
    int libres = 0;
    for (int i = 1; i <= 24; i++) {
      final d = asientos['$i'];
      if (d == null || (d is Map && d['ocupado'] != true)) libres++;
    }
    return libres;
  }

  String _formatEta(double? e) {
    if (e == null) return 'N/A';
    if (e < 1) return 'Llegando';
    return '~${e.round()} min';
  }

  Color _colorEta(double? e) {
    if (e == null) return Colors.grey;
    if (e < 5) return Colors.green.shade600;
    if (e < 15) return Colors.orange.shade600;
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
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorParada.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorParada.withValues(alpha: 0.2)),
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
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('camionetas')
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final dest = (data['destino'] as String? ?? '').toLowerCase();
                  final estado = data['estado'] as String? ?? '';
                  return dest.contains(keywordDestino) &&
                      (estado == 'disponible' || estado == 'en_camino');
                }).toList();

                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.directions_bus_outlined,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 12),
                          Text(
                            'No hay unidades en camino\nhacia esta parada',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 14),
                          ),
                        ]),
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
                    final colorUnidad = data['color'] as String? ?? '';
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
                                  ? colorParada.withValues(alpha: 0.2)
                                  : Colors.grey.shade200),
                          boxShadow: libres > 0
                              ? [
                                  BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2))
                                ]
                              : null,
                        ),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorEstado.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(Icons.directions_bus_rounded,
                                color: colorEstado, size: 24),
                          ),
                          const SizedBox(width: 12),
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
                                        color:
                                            colorEstado.withValues(alpha: 0.12),
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
                                  Text('$modelo — $colorUnidad  |  $destino',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatEta(eta),
                                    style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _colorEta(eta)),
                                  ),
                                ]),
                          ),
                          if (libres == 0)
                            Text('Sin cupo',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey.shade400)),
                        ]),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Text(
              'ETA calculado a 40 km/h promedio. Puede variar según el tráfico.',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ),
        ]);
      },
    );
  }
}

// =============================================================================
// CHIPS Y BADGES
// =============================================================================

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
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
