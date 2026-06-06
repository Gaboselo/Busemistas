// lib/vistas/conductor_home_vista.dart
// Busemistas USM v4
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios:
//   - Auto-completado por matricula (LLPB45 -> Yutong, rojo)
//   - Geofencing: detecta llegada a < 50m y finaliza viaje automaticamente
//   - Boton "Abrir abordaje / Recibir estudiantes" post-llegada
//   - Retorno inteligente: invierte ruta y limpia asientos
//   - GPS con coordenadas reales La California -> USM

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'login_vista.dart';

const Color _kAzul = Color(0xFF0E004A);

// ── Coordenadas reales del recorrido ────────────────────────────────────────
const LatLngSimple _coordUSM =
    LatLngSimple(10.491360068207142, -66.78017873573735);
const LatLngSimple _coordLaCalif = LatLngSimple(10.483376, -66.819402);

// Ruta real La California -> USM via Autopista F. Fajardo
const List<GeoPoint> _rutaHaciaUSM = [
  GeoPoint(10.483376, -66.819402),
  GeoPoint(10.484200, -66.816800),
  GeoPoint(10.485100, -66.813200),
  GeoPoint(10.486300, -66.808500),
  GeoPoint(10.487500, -66.803200),
  GeoPoint(10.488600, -66.798700),
  GeoPoint(10.489500, -66.794300),
  GeoPoint(10.490200, -66.789100),
  GeoPoint(10.491360, -66.780178),
];

final List<GeoPoint> _rutaHaciaLaCalif = _rutaHaciaUSM.reversed.toList();

const List<String> _etiquetasHaciaUSM = [
  'Estacion La California',
  'Av. Principal La California',
  'Autopista F. Fajardo',
  'Distribuidor El Recreo',
  'Paso desnivel Chuao',
  'Av. Rio de Janeiro',
  'Sector La Florencia',
  'Entrada La Florencia',
  'USM Sede La Florencia - Destino',
];

// Umbral de geofencing en metros
const double kUmbralLlegadaMetros = 50.0;

// ── Mapa de perfil de camionetas por matricula ───────────────────────────────
// Cuando el conductor selecciona la matricula, modelo y color se autocompletan.
const Map<String, _PerfilCamioneta> kPerfilesMatricula = {
  'LLPB45': _PerfilCamioneta(modelo: 'Yutong', color: 'rojo'),
  'ABCD12': _PerfilCamioneta(modelo: 'JAC', color: 'azul'),
  'WXYZ99': _PerfilCamioneta(modelo: 'Zhongtong', color: 'blanco'),
  'MNOP67': _PerfilCamioneta(modelo: 'Higer', color: 'amarillo'),
};

class _PerfilCamioneta {
  final String modelo;
  final String color;
  const _PerfilCamioneta({required this.modelo, required this.color});
}

// Helper simple para coordenadas (sin depender de latlong2 en el conductor)
class LatLngSimple {
  final double lat;
  final double lng;
  const LatLngSimple(this.lat, this.lng);
}

// Mapa de 24 asientos vacios para reset
Map<String, dynamic> _asientosVacios24() {
  final Map<String, dynamic> m = {};
  for (int i = 1; i <= 24; i++) {
    m['$i'] = {
      'ocupado': false,
      'cedula_pasajero': '',
      'nombre_pasajero': '',
      'estado_pago': '',
    };
  }
  return m;
}

// ── VISTA PRINCIPAL ──────────────────────────────────────────────────────────

class ConductorHomeVista extends StatefulWidget {
  const ConductorHomeVista({super.key});

  @override
  State<ConductorHomeVista> createState() => _ConductorHomeVistaState();
}

class _ConductorHomeVistaState extends State<ConductorHomeVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Configuracion de la unidad
  bool _configurado = false;
  String? _matriculaSeleccionada;
  bool _sentidoHaciaUSM = true;

  bool _rutaActiva = false;
  bool _simulando = false;
  int _pasoSimulacion = 0;
  Timer? _timerSimulacion;
  bool _emergenciaActiva = false;
  bool _llegadaDetectada = false; // true cuando el geofence disparo

  String get _camionetaId =>
      context.read<AuthProvider>().camionetaAsignada ?? 'camioneta_01';

  List<GeoPoint> get _rutaActual =>
      _sentidoHaciaUSM ? _rutaHaciaUSM : _rutaHaciaLaCalif;

  List<String> get _etiquetasActuales => _sentidoHaciaUSM
      ? _etiquetasHaciaUSM
      : _etiquetasHaciaUSM.reversed.toList();

  // Coordenadas del destino segun sentido
  LatLngSimple get _coordDestino =>
      _sentidoHaciaUSM ? _coordUSM : _coordLaCalif;

  @override
  void dispose() {
    _timerSimulacion?.cancel();
    super.dispose();
  }

  // ── Guardar configuracion con auto-completado por matricula ──────
  Future<void> _guardarConfiguracion() async {
    if (_matriculaSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecciona la matricula de la unidad.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final perfil = kPerfilesMatricula[_matriculaSeleccionada!];
    final destino = _sentidoHaciaUSM ? 'Hacia la USM' : 'Hacia La California';

    try {
      await _db.collection('camionetas').doc(_camionetaId).set({
        'modelo': perfil?.modelo ?? 'Sin modelo',
        'color': perfil?.color ?? 'Sin color',
        'patente': _matriculaSeleccionada,
        'destino': destino,
        'estado': 'disponible',
        'activa': false,
        'asientos': _asientosVacios24(),
        'latitud': _rutaActual.first.latitude,
        'longitud': _rutaActual.first.longitude,
        'ubicacion': _rutaActual.first,
        'chofer': context.read<AuthProvider>().nombreCompleto ?? 'Conductor',
        'trafico_denso': false,
      }, SetOptions(merge: true));

      setState(() {
        _configurado = true;
        _llegadaDetectada = false;
      });
    } catch (e) {
      _mostrarError('Error al guardar configuracion: $e');
    }
  }

  // ── Toggle ruta ──────────────────────────────────────────────────
  Future<void> _toggleRuta(bool valor) async {
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'activa': valor,
        'estado': valor ? 'en_camino' : 'disponible',
      });
      setState(() {
        _rutaActiva = valor;
        if (!valor) _detenerSimulacion();
      });
    } catch (e) {
      _mostrarError('Error al cambiar estado: $e');
    }
  }

  // ── Simulacion GPS con geofencing ────────────────────────────────
  void _iniciarSimulacion() {
    if (_simulando) {
      _detenerSimulacion();
      return;
    }
    setState(() {
      _simulando = true;
      _pasoSimulacion = 0;
      _llegadaDetectada = false;
    });
    _escribirUbicacion(0);

    _timerSimulacion =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      final siguiente = _pasoSimulacion + 1;
      if (siguiente >= _rutaActual.length) {
        timer.cancel();
        setState(() => _simulando = false);
        return;
      }
      setState(() => _pasoSimulacion = siguiente);
      await _escribirUbicacion(siguiente);

      // Verificar geofencing
      await _verificarLlegada(siguiente);
    });
  }

  // Verifica si la posicion actual esta dentro del umbral del destino
  Future<void> _verificarLlegada(int paso) async {
    if (_llegadaDetectada) return;
    final pos = _rutaActual[paso];
    final distanciaMetros = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      _coordDestino.lat,
      _coordDestino.lng,
    );

    if (distanciaMetros <= kUmbralLlegadaMetros) {
      _llegadaDetectada = true;
      _timerSimulacion?.cancel();
      setState(() => _simulando = false);
      await _llegadaAutomatica();
    }
  }

  // Dispara cuando el geofence detecta llegada
  Future<void> _llegadaAutomatica() async {
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'estado': 'terminado',
        'activa': false,
      });
      setState(() => _rutaActiva = false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Has llegado a tu destino: ${_sentidoHaciaUSM ? "USM" : "La California"}!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      _mostrarError('Error al registrar llegada: $e');
    }
  }

  void _detenerSimulacion() {
    _timerSimulacion?.cancel();
    setState(() => _simulando = false);
  }

  Future<void> _escribirUbicacion(int paso) async {
    if (paso >= _rutaActual.length) return;
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'latitud': _rutaActual[paso].latitude,
        'longitud': _rutaActual[paso].longitude,
        'ubicacion': _rutaActual[paso],
        'ultimo_update': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('GPS write error: $e');
    }
  }

  // ── Abrir abordaje / Retorno inteligente ─────────────────────────
  Future<void> _abrirAbordajeRegreso() async {
    // Invertir sentido y limpiar asientos
    final nuevoSentido = !_sentidoHaciaUSM;
    final nuevoDestino = nuevoSentido ? 'Hacia la USM' : 'Hacia La California';

    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'destino': nuevoDestino,
        'estado': 'disponible',
        'activa': false,
        'asientos': _asientosVacios24(),
        'latitud':
            (nuevoSentido ? _rutaHaciaUSM : _rutaHaciaLaCalif).first.latitude,
        'longitud':
            (nuevoSentido ? _rutaHaciaUSM : _rutaHaciaLaCalif).first.longitude,
        'ubicacion': (nuevoSentido ? _rutaHaciaUSM : _rutaHaciaLaCalif).first,
      });

      setState(() {
        _sentidoHaciaUSM = nuevoSentido;
        _pasoSimulacion = 0;
        _llegadaDetectada = false;
        _rutaActiva = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Abordaje abierto. Nuevo destino: $nuevoDestino. 24 asientos disponibles.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      _mostrarError('Error al abrir abordaje: $e');
    }
  }

  // ── Emergencia ───────────────────────────────────────────────────
  void _mostrarEmergenciaSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BottomSheetEmergenciaConductor(
        emergenciaActiva: _emergenciaActiva,
        onEmergencia: (tipo) async {
          Navigator.pop(context);
          await _ejecutarEmergencia(tipo);
        },
        onResolver: () async {
          Navigator.pop(context);
          await _resolverEmergencia();
        },
      ),
    );
  }

  Future<void> _ejecutarEmergencia(String tipo) async {
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'estado':
            tipo == 'Colision/Choque vial' ? 'fuera_de_servicio' : 'emergencia',
        'tipo_emergencia': tipo,
        'ts_emergencia': FieldValue.serverTimestamp(),
      });
      setState(() => _emergenciaActiva = true);

      if (tipo == 'Colision/Choque vial') {
        await _transferirRespaldo();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Emergencia declarada: $tipo'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      _mostrarError('Error al activar emergencia: $e');
    }
  }

  Future<void> _transferirRespaldo() async {
    try {
      final snap = await _db.collection('camionetas').doc(_camionetaId).get();
      if (!snap.exists) return;
      final data = snap.data()!;
      final asientos = data['asientos'] as Map<String, dynamic>? ?? {};
      final destino = data['destino'] as String? ?? 'Hacia la USM';

      final batch = _db.batch();
      final backupRef = _db.collection('camionetas').doc('unidad_backup');
      batch.set(
        backupRef,
        {
          'modelo': 'Unidad de Respaldo',
          'color': 'blanco',
          'patente': 'RESPALDO',
          'chofer': 'Sistema - Asignacion Automatica',
          'estado': 'en_camino',
          'destino': destino,
          'latitud': _rutaActual.first.latitude,
          'longitud': _rutaActual.first.longitude,
          'ubicacion': _rutaActual.first,
          'asientos': asientos,
          'es_respaldo': true,
          'unidad_reemplazada': _camionetaId,
          'ts_activacion': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unidad de respaldo activada. Recogiendo pasajeros.'),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      debugPrint('Error respaldo: $e');
    }
  }

  Future<void> _resolverEmergencia() async {
    try {
      final batch = _db.batch();
      final camRef = _db.collection('camionetas').doc(_camionetaId);
      batch.update(camRef, {
        'estado': 'disponible',
        'tipo_emergencia': FieldValue.delete(),
        'ts_emergencia': FieldValue.delete(),
      });
      await batch.commit();
      setState(() => _emergenciaActiva = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Emergencia resuelta. Unidad disponible.'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      _mostrarError('Error al resolver emergencia: $e');
    }
  }

  // ── Fin manual del viaje ─────────────────────────────────────────
  Future<void> _finalizarViaje() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Finalizar Viaje?'),
        content: const Text(
            'Libera todos los asientos y pone la unidad como disponible.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAzul),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finalizar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final batch = _db.batch();
      final camRef = _db.collection('camionetas').doc(_camionetaId);
      batch.update(camRef, {
        'asientos': _asientosVacios24(),
        'estado': 'terminado',
        'activa': false,
      });
      await batch.commit();
      setState(() {
        _rutaActiva = false;
        _simulando = false;
        _llegadaDetectada = true;
      });
      _timerSimulacion?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Viaje finalizado. Asientos liberados.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      _mostrarError('Error al finalizar viaje: $e');
    }
  }

  void _mostrarError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _cerrarSesion() {
    _detenerSimulacion();
    context.read<AuthProvider>().cerrarSesion();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginVista()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final primerNombre = (auth.nombreCompleto ?? 'Conductor').split(' ').first;

    if (!_configurado) {
      return _PantallaConfiguracion(
        primerNombre: primerNombre,
        matriculaSeleccionada: _matriculaSeleccionada,
        sentidoHaciaUSM: _sentidoHaciaUSM,
        onMatriculaChanged: (v) => setState(() => _matriculaSeleccionada = v),
        onSentidoChanged: (v) => setState(() => _sentidoHaciaUSM = v),
        onConfirmar: _guardarConfiguracion,
        onCerrarSesion: _cerrarSesion,
        perfilesMatricula: kPerfilesMatricula,
      );
    }

    final perfil = kPerfilesMatricula[_matriculaSeleccionada ?? ''];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(children: [
          _HeaderConductor(
            primerNombre: primerNombre,
            emergenciaActiva: _emergenciaActiva,
            onEmergencia: _mostrarEmergenciaSheet,
            onLogout: _cerrarSesion,
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                // Info de la unidad configurada
                _TarjetaUnidadConfigurada(
                  modelo: perfil?.modelo ?? '',
                  colorUnidad: perfil?.color ?? '',
                  matricula: _matriculaSeleccionada ?? '',
                  destino:
                      _sentidoHaciaUSM ? 'Hacia la USM' : 'Hacia La California',
                ),
                const SizedBox(height: 12),

                // Panel GPS
                _TarjetaGPS(
                  rutaActiva: _rutaActiva,
                  simulando: _simulando,
                  pasoSimulacion: _pasoSimulacion,
                  totalPasos: _rutaActual.length,
                  etiquetaActual: _pasoSimulacion < _etiquetasActuales.length
                      ? _etiquetasActuales[_pasoSimulacion]
                      : 'Destino alcanzado',
                  llegadaDetectada: _llegadaDetectada,
                  onToggleRuta: _toggleRuta,
                  onToggleSimulacion: _iniciarSimulacion,
                ),
                const SizedBox(height: 12),

                // Boton de abordaje/retorno si llego
                if (_llegadaDetectada)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      onPressed: _abrirAbordajeRegreso,
                      icon: const Icon(Icons.door_sliding_rounded),
                      label: const Text('Abrir abordaje / Recibir estudiantes'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                // Lista de pasajeros
                _TarjetaPanelControl(camionetaId: _camionetaId, db: _db),
                const SizedBox(height: 12),

                // Boton finalizar viaje (solo si no llego aun)
                if (!_llegadaDetectada)
                  FilledButton.icon(
                    onPressed: _rutaActiva ? _finalizarViaje : null,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text('Finalizar Viaje'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANTALLA DE CONFIGURACION
// ─────────────────────────────────────────────────────────────────────────────

class _PantallaConfiguracion extends StatelessWidget {
  final String primerNombre;
  final String? matriculaSeleccionada;
  final bool sentidoHaciaUSM;
  final void Function(String?) onMatriculaChanged;
  final void Function(bool) onSentidoChanged;
  final VoidCallback onConfirmar;
  final VoidCallback onCerrarSesion;
  final Map<String, _PerfilCamioneta> perfilesMatricula;

  const _PantallaConfiguracion({
    required this.primerNombre,
    required this.matriculaSeleccionada,
    required this.sentidoHaciaUSM,
    required this.onMatriculaChanged,
    required this.onSentidoChanged,
    required this.onConfirmar,
    required this.onCerrarSesion,
    required this.perfilesMatricula,
  });

  @override
  Widget build(BuildContext context) {
    final perfilActual = perfilesMatricula[matriculaSeleccionada ?? ''];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Configurar Unidad'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: onCerrarSesion,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bienvenida
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0E004A), Color(0xFF3A0CA3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(children: [
                const Icon(Icons.drive_eta_rounded,
                    color: Colors.white, size: 36),
                const SizedBox(width: 14),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Hola, $primerNombre',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const Text('Configura tu unidad antes de iniciar',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ]),
              ]),
            ),
            const SizedBox(height: 24),

            // Selector de matricula
            const Text('Matricula / Placa',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: _kAzul)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: matriculaSeleccionada,
              decoration: InputDecoration(
                hintText: 'Selecciona la matricula',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              items: perfilesMatricula.keys
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: onMatriculaChanged,
            ),
            const SizedBox(height: 12),

            // Auto-completado visual
            if (perfilActual != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Row(children: [
                  Icon(Icons.auto_awesome,
                      color: Colors.green.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Modelo: ${perfilActual.modelo}  |  Color: ${perfilActual.color}',
                    style: TextStyle(
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ]),
              ),
            const SizedBox(height: 16),

            // Selector de sentido
            const Text('Sentido de la Ruta',
                style: TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13, color: _kAzul)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _BotonSentido(
                  label: 'Hacia la USM',
                  sublabel: 'La California -> USM',
                  icono: Icons.school_rounded,
                  seleccionado: sentidoHaciaUSM,
                  onTap: () => onSentidoChanged(true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BotonSentido(
                  label: 'Regreso',
                  sublabel: 'USM -> La California',
                  icono: Icons.directions_bus_rounded,
                  seleccionado: !sentidoHaciaUSM,
                  onTap: () => onSentidoChanged(false),
                ),
              ),
            ]),
            const SizedBox(height: 28),

            FilledButton.icon(
              onPressed: onConfirmar,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Iniciar Servicio'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BotonSentido extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;

  const _BotonSentido({
    required this.label,
    required this.sublabel,
    required this.icono,
    required this.seleccionado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: seleccionado ? _kAzul : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: seleccionado ? _kAzul : Colors.grey.shade300),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icono,
                color: seleccionado ? Colors.white : Colors.grey.shade600,
                size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: seleccionado ? Colors.white : Colors.grey.shade800)),
            Text(sublabel,
                style: TextStyle(
                    fontSize: 10,
                    color:
                        seleccionado ? Colors.white70 : Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER CONDUCTOR
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderConductor extends StatelessWidget {
  final String primerNombre;
  final bool emergenciaActiva;
  final VoidCallback onEmergencia;
  final VoidCallback onLogout;

  const _HeaderConductor({
    required this.primerNombre,
    required this.emergenciaActiva,
    required this.onEmergencia,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: _kAzul,
      child: Row(children: [
        const Icon(Icons.directions_bus_rounded,
            color: Colors.white70, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hola, $primerNombre!',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const Text('Panel del Conductor',
                style: TextStyle(color: Colors.white60, fontSize: 11)),
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
                    emergenciaActiva ? Colors.red : Colors.red.withValues(alpha: 0.2),
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
        const SizedBox(width: 6),
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          onPressed: onLogout,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA UNIDAD CONFIGURADA
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaUnidadConfigurada extends StatelessWidget {
  final String modelo;
  final String colorUnidad;
  final String matricula;
  final String destino;

  const _TarjetaUnidadConfigurada({
    required this.modelo,
    required this.colorUnidad,
    required this.matricula,
    required this.destino,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kAzul.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: _kAzul, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$modelo - $matricula',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: _kAzul)),
                Text('Color: $colorUnidad  |  $destino',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA GPS
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaGPS extends StatelessWidget {
  final bool rutaActiva;
  final bool simulando;
  final int pasoSimulacion;
  final int totalPasos;
  final String etiquetaActual;
  final bool llegadaDetectada;
  final void Function(bool) onToggleRuta;
  final VoidCallback onToggleSimulacion;

  const _TarjetaGPS({
    required this.rutaActiva,
    required this.simulando,
    required this.pasoSimulacion,
    required this.totalPasos,
    required this.etiquetaActual,
    required this.llegadaDetectada,
    required this.onToggleRuta,
    required this.onToggleSimulacion,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Titulo
            const Row(children: [
              Icon(Icons.gps_fixed_rounded, color: _kAzul, size: 20),
              SizedBox(width: 8),
              Text('Control de Ruta',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _kAzul)),
            ]),
            const SizedBox(height: 20),

            // Destino alcanzado
            if (llegadaDetectada)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: const Row(children: [
                  Icon(Icons.flag_rounded, color: Colors.green, size: 28),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Destino alcanzado.\nViaje completado.',
                        style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ]),
              )
            else ...[
              // BOTON GIGANTE
              GestureDetector(
                onTap: () => onToggleRuta(!rutaActiva),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 130,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: rutaActiva
                          ? [Colors.red.shade600, Colors.red.shade800]
                          : [Colors.green.shade500, Colors.green.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: rutaActiva
                            ? Colors.red.withValues(alpha: 0.4)
                            : Colors.green.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        rutaActiva
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        rutaActiva ? 'TERMINAR RUTA' : 'INICIAR RUTA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        rutaActiva
                            ? 'Toca para finalizar el servicio'
                            : 'Toca para comenzar el servicio',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Info de ruta activa
              if (rutaActiva) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.location_on_rounded,
                          color: _kAzul, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Ubicacion: $etiquetaActual',
                          style: const TextStyle(
                              fontSize: 12,
                              color: _kAzul,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: totalPasos > 0
                            ? pasoSimulacion / (totalPasos - 1)
                            : 0,
                        backgroundColor: Colors.grey.shade200,
                        color: _kAzul,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: onToggleSimulacion,
                      icon: Icon(simulando
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outlined),
                      label: Text(simulando
                          ? 'Detener simulacion GPS'
                          : 'Iniciar simulacion GPS'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kAzul,
                        side: const BorderSide(color: _kAzul),
                        minimumSize: const Size.fromHeight(40),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA PASAJEROS
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA PANEL DE CONTROL (Pasajeros + Trafico)
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaPanelControl extends StatefulWidget {
  final String camionetaId;
  final FirebaseFirestore db;
  const _TarjetaPanelControl({required this.camionetaId, required this.db});

  @override
  State<_TarjetaPanelControl> createState() => _TarjetaPanelControlState();
}

class _TarjetaPanelControlState extends State<_TarjetaPanelControl> {
  String _nivelTrafico = 'bajo';

  Future<void> _cambiarTrafico(String nivel) async {
    setState(() => _nivelTrafico = nivel);
    try {
      await widget.db.collection('camionetas').doc(widget.camionetaId).update({
        'nivel_trafico': nivel,
        'trafico_denso': nivel == 'alto',
      });
    } catch (e) {
      debugPrint('Error al actualizar trafico: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: widget.db
          .collection('camionetas')
          .doc(widget.camionetaId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox();
        }

        final data = snap.data!.data() as Map<String, dynamic>;
        final asientos = (data['asientos'] as Map<String, dynamic>?) ?? {};
        final pasajeros = asientos.entries
            .where(
                (e) => e.value is Map && (e.value as Map)['ocupado'] == true)
            .toList();
        final totalPasajeros = pasajeros.length;
        final nivelActual = data['nivel_trafico'] as String? ?? 'bajo';

        return Column(
          children: [
            // ── CONTADOR DE PASAJEROS ──
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.people_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
                      Text('Pasajeros a bordo',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 16),

                    // Contador visual grande
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 16),
                          decoration: BoxDecoration(
                            color: totalPasajeros >= 24
                                ? Colors.red.shade50
                                : totalPasajeros >= 18
                                    ? Colors.orange.shade50
                                    : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: totalPasajeros >= 24
                                  ? Colors.red.shade300
                                  : totalPasajeros >= 18
                                      ? Colors.orange.shade300
                                      : Colors.green.shade300,
                              width: 2,
                            ),
                          ),
                          child: Column(children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: '$totalPasajeros',
                                    style: TextStyle(
                                      fontSize: 56,
                                      fontWeight: FontWeight.bold,
                                      color: totalPasajeros >= 24
                                          ? Colors.red.shade700
                                          : totalPasajeros >= 18
                                              ? Colors.orange.shade700
                                              : Colors.green.shade700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' / 24',
                                    style: TextStyle(
                                      fontSize: 24,
                                      color: Colors.grey.shade500,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              totalPasajeros >= 24
                                  ? 'Unidad llena'
                                  : totalPasajeros >= 18
                                      ? 'Casi llena'
                                      : 'Asientos disponibles',
                              style: TextStyle(
                                fontSize: 13,
                                color: totalPasajeros >= 24
                                    ? Colors.red.shade700
                                    : totalPasajeros >= 18
                                        ? Colors.orange.shade700
                                        : Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Barra de progreso de ocupacion
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: totalPasajeros / 24,
                        backgroundColor: Colors.grey.shade200,
                        color: totalPasajeros >= 24
                            ? Colors.red
                            : totalPasajeros >= 18
                                ? Colors.orange
                                : Colors.green,
                        minHeight: 10,
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Lista de pasajeros
                    if (pasajeros.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Sin pasajeros aun.',
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Column(
                        children: pasajeros.map((entry) {
                          final v = entry.value as Map;
                          return _FilaPasajero(
                            asiento: entry.key,
                            nombre:
                                v['nombre_pasajero'] as String? ?? '-',
                            cedula:
                                v['cedula_pasajero'] as String? ?? '-',
                            estadoPago:
                                v['estado_pago'] as String? ?? 'pendiente',
                            camionetaId: widget.camionetaId,
                            db: widget.db,
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // ── SELECTOR DE TRAFICO ──
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.traffic_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
                      Text('Nivel de Trafico',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'Indica el trafico actual para ajustar el ETA',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _BotonTrafico(
                          label: 'Bajo',
                          emoji: '🟢',
                          seleccionado: nivelActual == 'bajo',
                          color: Colors.green,
                          onTap: () => _cambiarTrafico('bajo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
                          label: 'Medio',
                          emoji: '🟡',
                          seleccionado: nivelActual == 'medio',
                          color: Colors.orange,
                          onTap: () => _cambiarTrafico('medio'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
                          label: 'Alto',
                          emoji: '🔴',
                          seleccionado: nivelActual == 'alto',
                          color: Colors.red,
                          onTap: () => _cambiarTrafico('alto'),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BotonTrafico extends StatelessWidget {
  final String label;
  final String emoji;
  final bool seleccionado;
  final Color color;
  final VoidCallback onTap;

  const _BotonTrafico({
    required this.label,
    required this.emoji,
    required this.seleccionado,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: seleccionado ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: seleccionado ? color : Colors.grey.shade300,
            width: seleccionado ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: seleccionado ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaPasajero extends StatefulWidget {
  final String asiento;
  final String nombre;
  final String cedula;
  final String estadoPago;
  final String camionetaId;
  final FirebaseFirestore db;

  const _FilaPasajero({
    required this.asiento,
    required this.nombre,
    required this.cedula,
    required this.estadoPago,
    required this.camionetaId,
    required this.db,
  });

  @override
  State<_FilaPasajero> createState() => _FilaPasajeroState();
}

class _FilaPasajeroState extends State<_FilaPasajero> {
  bool _procesando = false;

  Future<void> _confirmarPago() async {
    setState(() => _procesando = true);
    try {
      await widget.db
          .collection('camionetas')
          .doc(widget.camionetaId)
          .update({'asientos.${widget.asiento}.estado_pago': 'confirmado'});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPagado = widget.estadoPago == 'pagado' ||
        widget.estadoPago == 'confirmado' ||
        widget.estadoPago == 'mensualidad';
    final isPendiente = widget.estadoPago == 'pendiente_pago' ||
        widget.estadoPago == 'en_puerta';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isPagado
            ? Colors.green.shade50
            : isPendiente
                ? Colors.orange.shade50
                : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isPagado
                ? Colors.green.shade200
                : isPendiente
                    ? Colors.orange.shade300
                    : Colors.grey.shade200),
      ),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: _kAzul, borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: Text(widget.asiento,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.nombre,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('C.I. ${widget.cedula}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        if (isPagado)
          const Chip(
            label: Text('PAGADO',
                style: TextStyle(
                    color: Colors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
            backgroundColor: Colors.transparent,
            side: BorderSide(color: Colors.green),
            padding: EdgeInsets.zero,
          )
        else if (isPendiente)
          _procesando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : FilledButton(
                  onPressed: _confirmarPago,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(fontSize: 10),
                  ),
                  child: const Text('Confirmar\nPago'),
                ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET EMERGENCIA CONDUCTOR
// ─────────────────────────────────────────────────────────────────────────────

class _BottomSheetEmergenciaConductor extends StatelessWidget {
  final bool emergenciaActiva;
  final void Function(String) onEmergencia;
  final VoidCallback onResolver;

  const _BottomSheetEmergenciaConductor({
    required this.emergenciaActiva,
    required this.onEmergencia,
    required this.onResolver,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.warning_rounded, color: Colors.red, size: 26),
            SizedBox(width: 10),
            Text('Panel de Emergencia',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red)),
          ]),
          const SizedBox(height: 16),
          if (emergenciaActiva) ...[
            _OpcionEmergencia(
              icono: Icons.check_circle_outline_rounded,
              label: 'Resolver Emergencia',
              subtitulo: 'Libera la unidad y reactiva el servicio',
              color: Colors.green,
              onTap: onResolver,
            ),
          ] else ...[
            _OpcionEmergencia(
              icono: Icons.build_circle_outlined,
              label: 'Falla Mecanica',
              subtitulo: 'Problema tecnico en la unidad',
              color: Colors.orange,
              onTap: () => onEmergencia('Falla mecanica'),
            ),
            const SizedBox(height: 8),
            _OpcionEmergencia(
              icono: Icons.car_crash_rounded,
              label: 'Colision / Choque Vial',
              subtitulo: 'Activa unidad de respaldo automaticamente',
              color: Colors.red,
              onTap: () => onEmergencia('Colision/Choque vial'),
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
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(icono, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: color)),
                Text(subtitulo,
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withValues(alpha: 0.5), size: 14),
        ]),
      ),
    );
  }
}
