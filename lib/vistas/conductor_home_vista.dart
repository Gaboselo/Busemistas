// lib/vistas/conductor_home_vista.dart
<<<<<<< HEAD
// Busemistas USM v6
// REGLA: variables/keys sin tildes. Textos de UI con ortografia correcta.
// Cambios v6:
//   - Sin pantalla de configuracion manual: lee matricula_asignada de Firestore
//   - Simulacion OSRM real: el timer avanza por puntos de la ruta descargada de OSRM
//   - Ruta se descarga una sola vez al iniciar y se recorre punto a punto
//   - Geofencing mantiene 50m de umbral para llegada automatica

import "dart:async";
import "dart:convert";
import "package:cloud_firestore/cloud_firestore.dart";
import "package:flutter/material.dart";
import "package:geolocator/geolocator.dart";
import "package:http/http.dart" as http;
import "package:provider/provider.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart" as ll;
import "../feature_eta.dart" as eta_calc;

import "../providers/auth_provider.dart";
import "login_vista.dart";

const Color _kAzul = Color(0xFF0E004A);

// Coordenadas de las dos paradas
=======
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
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../feature_eta.dart' as eta_calc;

const Color _kAzul = Color(0xFF0E004A);

// ── Coordenadas reales del recorrido ────────────────────────────────────────
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
const LatLngSimple _coordUSM =
    LatLngSimple(10.491360068207142, -66.78017873573735);
const LatLngSimple _coordLaCalif = LatLngSimple(10.483376, -66.819402);

<<<<<<< HEAD
// Ruta base de waypoints (fallback si OSRM falla)
const List<GeoPoint> _rutaBaseHaciaUSM = [
=======
// Ruta real La California -> USM via Autopista F. Fajardo
const List<GeoPoint> _rutaHaciaUSM = [
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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

<<<<<<< HEAD
const List<String> _etiquetasHaciaUSM = [
  "Estacion La California",
  "Av. Principal La California",
  "Autopista F. Fajardo",
  "Distribuidor El Recreo",
  "Paso desnivel Chuao",
  "Av. Rio de Janeiro",
  "Sector La Florencia",
  "Entrada La Florencia",
  "USM Sede La Florencia - Destino",
];

const double kUmbralLlegadaMetros = 50.0;

const Map<String, _PerfilCamioneta> kPerfilesMatricula = {
  "LLPB45": _PerfilCamioneta(modelo: "Yutong", color: "rojo"),
  "ABCD12": _PerfilCamioneta(modelo: "JAC", color: "azul"),
  "WXYZ99": _PerfilCamioneta(modelo: "Zhongtong", color: "blanco"),
  "MNOP67": _PerfilCamioneta(modelo: "Higer", color: "amarillo"),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
};

class _PerfilCamioneta {
  final String modelo;
  final String color;
  const _PerfilCamioneta({required this.modelo, required this.color});
}

<<<<<<< HEAD
=======
// Helper simple para coordenadas (sin depender de latlong2 en el conductor)
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
class LatLngSimple {
  final double lat;
  final double lng;
  const LatLngSimple(this.lat, this.lng);
}

<<<<<<< HEAD
Map<String, dynamic> _asientosVacios24() {
  final m = <String, dynamic>{};
  for (int i = 1; i <= 24; i++) {
    m['$i'] = {
      "ocupado": false,
      "cedula_pasajero": "",
      "nombre_pasajero": "",
      "estado_pago": "",
=======
// Mapa de 24 asientos vacios para reset
Map<String, dynamic> _asientosVacios24() {
  final Map<String, dynamic> m = {};
  for (int i = 1; i <= 24; i++) {
    m['$i'] = {
      'ocupado': false,
      'cedula_pasajero': '',
      'nombre_pasajero': '',
      'estado_pago': '',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    };
  }
  return m;
}

<<<<<<< HEAD
// =============================================================================
// SERVICIO OSRM INTERNO (copia standalone para el conductor)
// =============================================================================

Future<List<ll.LatLng>> _obtenerRutaOSRM(
    ll.LatLng origen, ll.LatLng destino) async {
  final url = Uri.parse("https://router.project-osrm.org/route/v1/driving/"
      "${origen.longitude},${origen.latitude};"
      "${destino.longitude},${destino.latitude}"
      "?overview=full&geometries=geojson");
  try {
    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> coords = data["routes"][0]["geometry"]["coordinates"];
      return coords
          .map((c) => ll.LatLng(c[1] as double, c[0] as double))
          .toList();
    }
  } catch (e) {
    debugPrint("OSRM conductor: $e");
  }
  return [];
}

// =============================================================================
// VISTA PRINCIPAL
// =============================================================================

class ConductorHomeVista extends StatefulWidget {
  const ConductorHomeVista({super.key});
=======
// ── VISTA PRINCIPAL ──────────────────────────────────────────────────────────

class ConductorHomeVista extends StatefulWidget {
  const ConductorHomeVista({super.key});

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  @override
  State<ConductorHomeVista> createState() => _ConductorHomeVistaState();
}

class _ConductorHomeVistaState extends State<ConductorHomeVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

<<<<<<< HEAD
  // Datos de la unidad (cargados de Firestore automaticamente)
  bool _cargandoUnidad = true;
  String? _matricula;
  String? _modelo;
  String? _colorUnidad;

  bool _sentidoHaciaUSM = true;
  bool _rutaActiva = false;
  bool _emergenciaActiva = false;
  bool _llegadaDetectada = false;

  // Simulacion OSRM
  bool _simulando = false;
  List<ll.LatLng> _rutaOSRM = [];
  int _pasoSimulacion = 0;
  Timer? _timerSimulacion;
  bool _descargandoRuta = false;

  String get _camionetaId =>
      context.read<AuthProvider>().camionetaAsignada ?? "camioneta_01";

  LatLngSimple get _coordDestino =>
      _sentidoHaciaUSM ? _coordUSM : _coordLaCalif;

  ll.LatLng get _origenLL => _sentidoHaciaUSM
      ? ll.LatLng(_coordLaCalif.lat, _coordLaCalif.lng)
      : ll.LatLng(_coordUSM.lat, _coordUSM.lng);

  ll.LatLng get _destinoLL => _sentidoHaciaUSM
      ? ll.LatLng(_coordUSM.lat, _coordUSM.lng)
      : ll.LatLng(_coordLaCalif.lat, _coordLaCalif.lng);

  GeoPoint get _geopointInicio =>
      _sentidoHaciaUSM ? _rutaBaseHaciaUSM.first : _rutaBaseHaciaUSM.last;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarUnidad());
  }

=======
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

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  @override
  void dispose() {
    _timerSimulacion?.cancel();
    super.dispose();
  }

<<<<<<< HEAD
  // ---------------------------------------------------------------------------
  // PUNTO 3: Cargar unidad automaticamente desde matricula_asignada
  // No hay pantalla de configuracion manual. El conductor llega directo al panel.
  // ---------------------------------------------------------------------------
  Future<void> _cargarUnidad() async {
    final auth = context.read<AuthProvider>();
    final camionetaId = auth.camionetaAsignada;

    if (camionetaId == null || camionetaId.isEmpty) {
      // Fallback: leer directo de Firestore en el doc del conductor
      final cedula = auth.cedulaActual ?? "";
      if (cedula.isNotEmpty) {
        final userDoc = await _db.collection("usuarios").doc(cedula).get();
        if (userDoc.exists) {
          final asignada = userDoc.data()!["camioneta_asignada"] as String?;
          if (asignada != null && mounted) {
            auth.actualizarCamionetaAsignada(asignada);
          }
        }
      }
    }

    // Leer datos del documento de la camioneta
    try {
      final camDoc = await _db.collection("camionetas").doc(_camionetaId).get();
      if (camDoc.exists && mounted) {
        final data = camDoc.data()!;
        setState(() {
          _modelo = data["modelo"] as String? ?? "Yutong";
          _colorUnidad = data["color"] as String? ?? "rojo";
          _matricula = data["patente"] as String? ?? _camionetaId;

          // Leer el sentido guardado (si existe)
          final dest = data["destino"] as String? ?? "";
          _sentidoHaciaUSM = !dest.toLowerCase().contains("california");

          // FIX Bug 2: _rutaActiva SIEMPRE inicia en false al hacer login,
          // independientemente de lo que diga Firestore. Esto evita que el
          // SwitchListTile dispare onChanged -> _toggleRuta() -> escritura
          // "en_camino" durante la construcción del widget.
          // El conductor debe presionar explícitamente el switch para iniciar.
          _rutaActiva = false;

          _cargandoUnidad = false;
        });
        // FIX Bug 1: Al iniciar sesión, siempre resetear estado a "disponible"
        // y activa a false. Nunca heredar un estado "en_camino" de un viaje
        // anterior que pudo haber quedado sucio en Firestore (p.ej. cierre abrupto).
        // Se preservan SOLO los datos de identidad de la unidad (modelo, color,
        // matrícula) y los asientos si los hay. El estado de ruta siempre arranca limpio.
        await _db.collection("camionetas").doc(_camionetaId).set({
          "modelo": _modelo,
          "color": _colorUnidad,
          "patente": _matricula,
          "destino": _sentidoHaciaUSM ? "Hacia la USM" : "Hacia La California",
          // CORRECCIÓN: nunca leer estado previo — siempre forzar disponible.
          "estado": "disponible",
          // CORRECCIÓN: nunca leer activa previa — siempre forzar false.
          "activa": false,
          "asientos": data.containsKey("asientos")
              ? data["asientos"]
              : _asientosVacios24(),
          "latitud": data["latitud"] ?? _geopointInicio.latitude,
          "longitud": data["longitud"] ?? _geopointInicio.longitude,
          "ubicacion": data["ubicacion"] ?? _geopointInicio,
          "chofer": auth.nombreCompleto ?? "Conductor",
          "trafico_denso": false,
        }, SetOptions(merge: true));
      } else {
        // Documento no existe: crearlo
        await _db.collection("camionetas").doc(_camionetaId).set({
          "modelo": "Yutong",
          "color": "rojo",
          "patente": _camionetaId,
          "destino": "Hacia la USM",
          "estado": "disponible",
          "activa": false,
          "asientos": _asientosVacios24(),
          "latitud": _coordLaCalif.lat,
          "longitud": _coordLaCalif.lng,
          "chofer": auth.nombreCompleto ?? "Conductor",
          "trafico_denso": false,
        });
        if (mounted)
          setState(() {
            _cargandoUnidad = false;
          });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargandoUnidad = false;
        });
        _mostrarError("Error al cargar la unidad: $e");
      }
    }
  }

  // ---------------------------------------------------------------------------
  // PUNTO 2: Descarga la ruta OSRM y arranca la simulacion punto a punto.
  //
  // FIX Bug 3: Este método SOLO puede ejecutarse si _rutaActiva == true,
  // es decir, si el conductor ya presionó el switch "Ruta activa" y Firestore
  // ya fue actualizado a "en_camino" por _toggleRuta(). De lo contrario,
  // _escribirUbicacion(ruta[0]) escribiría en Firestore sin autorización del
  // conductor, lo que desencadenaba el bug original.
  // ---------------------------------------------------------------------------
  Future<void> _iniciarSimulacion() async {
    // Guard principal: bloquear si el conductor no ha iniciado el viaje.
    if (!_rutaActiva) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              "Activa la ruta primero antes de iniciar la simulación GPS."),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    if (_simulando) {
      _detenerSimulacion();
      return;
    }
<<<<<<< HEAD

    setState(() {
      _descargandoRuta = true;
      _pasoSimulacion = 0;
      _llegadaDetectada = false;
    });

    // Descargar ruta real de OSRM
    List<ll.LatLng> ruta = await _obtenerRutaOSRM(_origenLL, _destinoLL);

    if (ruta.isEmpty) {
      // Fallback a waypoints base si OSRM falla
      ruta = _sentidoHaciaUSM
          ? _rutaBaseHaciaUSM
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList()
          : _rutaBaseHaciaUSM.reversed
              .map((p) => ll.LatLng(p.latitude, p.longitude))
              .toList();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Sin conexion a OSRM. Usando ruta base."),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }

    if (!mounted) return;
    setState(() {
      _rutaOSRM = ruta;
      _simulando = true;
      _descargandoRuta = false;
    });

    // Escribir posicion inicial
    await _escribirUbicacion(ruta[0]);

    // Timer: avanza un punto de la ruta cada 3 segundos
    _timerSimulacion =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final siguiente = _pasoSimulacion + 1;
      if (siguiente >= _rutaOSRM.length) {
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        timer.cancel();
        setState(() => _simulando = false);
        return;
      }
      setState(() => _pasoSimulacion = siguiente);
<<<<<<< HEAD
      await _escribirUbicacion(_rutaOSRM[siguiente]);
      await _verificarLlegada(_rutaOSRM[siguiente]);
    });
  }

  Future<void> _verificarLlegada(ll.LatLng pos) async {
    if (_llegadaDetectada) return;
    final distancia = Geolocator.distanceBetween(
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      pos.latitude,
      pos.longitude,
      _coordDestino.lat,
      _coordDestino.lng,
    );
<<<<<<< HEAD
    if (distancia <= kUmbralLlegadaMetros) {
=======

    if (distanciaMetros <= kUmbralLlegadaMetros) {
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      _llegadaDetectada = true;
      _timerSimulacion?.cancel();
      setState(() => _simulando = false);
      await _llegadaAutomatica();
    }
  }

<<<<<<< HEAD
  Future<void> _llegadaAutomatica() async {
    try {
      await _db.collection("camionetas").doc(_camionetaId).update({
        "estado": "terminado",
        "activa": false,
      });
      setState(() => _rutaActiva = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            "Llegaste a: ${_sentidoHaciaUSM ? "USM" : "La California"}. ¡Bien hecho!"),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
<<<<<<< HEAD
      _mostrarError("Error al registrar llegada: $e");
=======
      _mostrarError('Error al registrar llegada: $e');
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    }
  }

  void _detenerSimulacion() {
    _timerSimulacion?.cancel();
<<<<<<< HEAD
    setState(() {
      _simulando = false;
      _rutaOSRM = [];
    });
  }

  Future<void> _escribirUbicacion(ll.LatLng pos) async {
    try {
      await _db.collection("camionetas").doc(_camionetaId).update({
        "latitud": pos.latitude,
        "longitud": pos.longitude,
        "ubicacion": GeoPoint(pos.latitude, pos.longitude),
        "ultimo_update": FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("GPS write: $e");
    }
  }

  Future<void> _toggleRuta(bool valor) async {
    try {
      await _db.collection("camionetas").doc(_camionetaId).update({
        "activa": valor,
        "estado": valor ? "en_camino" : "disponible",
      });
      setState(() {
        _rutaActiva = valor;
        if (!valor) _detenerSimulacion();
      });
    } catch (e) {
      _mostrarError("Error al cambiar estado: $e");
    }
  }

  Future<void> _abrirAbordajeRegreso() async {
    final nuevoSentido = !_sentidoHaciaUSM;
    final nuevoDestino = nuevoSentido ? "Hacia la USM" : "Hacia La California";
    final nuevaUbicacion =
        nuevoSentido ? _rutaBaseHaciaUSM.first : _rutaBaseHaciaUSM.last;

    try {
      await _db.collection("camionetas").doc(_camionetaId).update({
        "destino": nuevoDestino,
        "estado": "disponible",
        "activa": false,
        "asientos": _asientosVacios24(),
        "latitud": nuevaUbicacion.latitude,
        "longitud": nuevaUbicacion.longitude,
        "ubicacion": nuevaUbicacion,
      });
=======
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

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      setState(() {
        _sentidoHaciaUSM = nuevoSentido;
        _pasoSimulacion = 0;
        _llegadaDetectada = false;
        _rutaActiva = false;
<<<<<<< HEAD
        _rutaOSRM = [];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Abordaje abierto. Nuevo destino: $nuevoDestino"),
=======
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Abordaje abierto. Nuevo destino: $nuevoDestino. 24 asientos disponibles.'),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
<<<<<<< HEAD
      _mostrarError("Error al abrir abordaje: $e");
    }
  }

  Future<void> _finalizarViaje() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Finalizar viaje"),
        content: const Text("Se liberarán todos los asientos."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAzul),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Finalizar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      final batch = _db.batch();
      final ref = _db.collection("camionetas").doc(_camionetaId);
      // FIX: al finalizar el viaje el estado queda "disponible" (no "terminado"),
      // de modo que al próximo login _cargarUnidad ya encuentra el doc limpio
      // y no necesita forzar el reset (aunque lo hace de todas formas como
      // medida de seguridad adicional — defensa en profundidad).
      batch.update(ref, {
        "asientos": _asientosVacios24(),
        "estado": "disponible",
        "activa": false,
      });
      await batch.commit();
      setState(() {
        _rutaActiva = false;
        _simulando = false;
        _llegadaDetectada = true;
        _rutaOSRM = [];
      });
      _timerSimulacion?.cancel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Viaje finalizado. Asientos liberados."),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      _mostrarError("Error al finalizar: $e");
    }
  }

=======
      _mostrarError('Error al abrir abordaje: $e');
    }
  }

  // ── Emergencia ───────────────────────────────────────────────────
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
      await _db.collection("camionetas").doc(_camionetaId).update({
        "estado":
            tipo == "Colision/Choque vial" ? "fuera_de_servicio" : "emergencia",
        "tipo_emergencia": tipo,
        "ts_emergencia": FieldValue.serverTimestamp(),
      });
      setState(() => _emergenciaActiva = true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Emergencia: $tipo"),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
<<<<<<< HEAD
      _mostrarError("Error emergencia: $e");
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    }
  }

  Future<void> _resolverEmergencia() async {
    try {
<<<<<<< HEAD
      await _db.collection("camionetas").doc(_camionetaId).update({
        "estado": "disponible",
        "tipo_emergencia": FieldValue.delete(),
        "ts_emergencia": FieldValue.delete(),
      });
      setState(() => _emergenciaActiva = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Emergencia resuelta."),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      _mostrarError("Error: $e");
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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

<<<<<<< HEAD
  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final primerNombre = (auth.nombreCompleto ?? "Conductor").split(" ").first;

    if (_cargandoUnidad) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(color: _kAzul),
            const SizedBox(height: 16),
            const Text("Cargando tu unidad...",
                style: TextStyle(color: _kAzul, fontSize: 16)),
            const SizedBox(height: 8),
            Text("Unidad: ${auth.camionetaAsignada ?? "buscando..."}",
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ]),
        ),
      );
    }

    // Calcular posicion actual para el mapa
    final pasoActual =
        (_pasoSimulacion < _rutaOSRM.length && _rutaOSRM.isNotEmpty)
            ? _rutaOSRM[_pasoSimulacion]
            : ll.LatLng(_sentidoHaciaUSM ? _coordLaCalif.lat : _coordUSM.lat,
                _sentidoHaciaUSM ? _coordLaCalif.lng : _coordUSM.lng);

    // Etiqueta del paso actual
    String etiquetaPasoActual;
    if (_rutaOSRM.isNotEmpty) {
      final pct = (_rutaOSRM.isNotEmpty && _pasoSimulacion < _rutaOSRM.length)
          ? (_pasoSimulacion / (_rutaOSRM.length - 1) * 100).round()
          : 100;
      etiquetaPasoActual = "Ruta OSRM: $pct% completado";
    } else if (_pasoSimulacion < _etiquetasHaciaUSM.length) {
      final etiquetas = _sentidoHaciaUSM
          ? _etiquetasHaciaUSM
          : _etiquetasHaciaUSM.reversed.toList();
      etiquetaPasoActual = etiquetas[_pasoSimulacion];
    } else {
      etiquetaPasoActual = "Destino alcanzado";
    }
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce

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
<<<<<<< HEAD
                // Info de la unidad
                _TarjetaUnidadConfigurada(
                  modelo: _modelo ?? "",
                  colorUnidad: _colorUnidad ?? "",
                  matricula: _matricula ?? _camionetaId,
                  destino:
                      _sentidoHaciaUSM ? "Hacia la USM" : "Hacia La California",
                ),
                const SizedBox(height: 12),

                // Panel GPS con mapa
                _TarjetaGPS(
                  rutaActiva: _rutaActiva,
                  simulando: _simulando,
                  descargandoRuta: _descargandoRuta,
                  pasoSimulacion: _pasoSimulacion,
                  totalPasos: _rutaOSRM.isNotEmpty
                      ? _rutaOSRM.length
                      : _rutaBaseHaciaUSM.length,
                  etiquetaActual: etiquetaPasoActual,
                  llegadaDetectada: _llegadaDetectada,
                  onToggleRuta: _toggleRuta,
                  onToggleSimulacion: _iniciarSimulacion,
                  posicionActual: pasoActual,
                  ruta: _rutaOSRM,
                  coordDestino: _destinoLL,
                ),
                const SizedBox(height: 12),

=======
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
                  posicionActual: ll.LatLng(
                    _rutaActual[_pasoSimulacion < _rutaActual.length
                            ? _pasoSimulacion
                            : _rutaActual.length - 1]
                        .latitude,
                    _rutaActual[_pasoSimulacion < _rutaActual.length
                            ? _pasoSimulacion
                            : _rutaActual.length - 1]
                        .longitude,
                  ),
                  ruta: _rutaActual
                      .map((p) => ll.LatLng(p.latitude, p.longitude))
                      .toList(),
                  coordDestino: ll.LatLng(_coordDestino.lat, _coordDestino.lng),
                ),

                const SizedBox(height: 12),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                _TarjetaETA(
                  camionetaId: _camionetaId,
                  db: _db,
                  sentidoHaciaUSM: _sentidoHaciaUSM,
                ),
<<<<<<< HEAD
                const SizedBox(height: 12),

=======

                // Boton de abordaje/retorno si llego
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                if (_llegadaDetectada)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      onPressed: _abrirAbordajeRegreso,
                      icon: const Icon(Icons.door_sliding_rounded),
<<<<<<< HEAD
                      label: const Text("Abrir abordaje / Recibir estudiantes"),
=======
                      label: const Text('Abrir abordaje / Recibir estudiantes'),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

<<<<<<< HEAD
                _TarjetaPanelControl(camionetaId: _camionetaId, db: _db),
                const SizedBox(height: 12),

=======
                // Lista de pasajeros
                _TarjetaPanelControl(camionetaId: _camionetaId, db: _db),
                const SizedBox(height: 12),

                // Boton finalizar viaje (solo si no llego aun)
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                if (!_llegadaDetectada)
                  FilledButton.icon(
                    onPressed: _rutaActiva ? _finalizarViaje : null,
                    icon: const Icon(Icons.flag_rounded),
<<<<<<< HEAD
                    label: const Text("Finalizar Viaje"),
=======
                    label: const Text('Finalizar Viaje'),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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

<<<<<<< HEAD
// =============================================================================
// WIDGETS DEL CONDUCTOR (Header, GPS, Panel Control, ETA, Emergencia, etc.)
// =============================================================================
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce

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
<<<<<<< HEAD
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("¡Hola, $primerNombre!",
=======
        const Icon(Icons.directions_bus_rounded,
            color: Colors.white70, size: 24),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hola, $primerNombre!',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
<<<<<<< HEAD
            const Text("Panel del Conductor",
                style: TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        GestureDetector(
          onTap: onEmergencia,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: emergenciaActiva
                  ? Colors.red
                  : Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade300),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.warning_rounded,
                  color: emergenciaActiva ? Colors.white : Colors.red.shade200,
                  size: 18),
              const SizedBox(width: 4),
              Text(
                emergenciaActiva ? "EMERGENCIA" : "SOS",
                style: TextStyle(
                    color:
                        emergenciaActiva ? Colors.white : Colors.red.shade200,
                    fontSize: 11,
                    fontWeight: FontWeight.bold),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
=======
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
                color: emergenciaActiva
                    ? Colors.red
                    : Colors.red.withValues(alpha: 0.2),
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          onPressed: onLogout,
        ),
      ]),
    );
  }
}

<<<<<<< HEAD
=======
// ─────────────────────────────────────────────────────────────────────────────
// TARJETA UNIDAD CONFIGURADA
// ─────────────────────────────────────────────────────────────────────────────

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0E004A), Color(0xFF3A0CA3)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(modelo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _kAzul)),
              const SizedBox(height: 2),
              Text("Matrícula: $matricula  |  Color: $colorUnidad",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.navigation_outlined,
                      size: 12, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text(destino,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
          ),
        ]),
      ),
    );
  }
}

<<<<<<< HEAD
class _TarjetaGPS extends StatelessWidget {
  final bool rutaActiva;
  final bool simulando;
  final bool descargandoRuta;
=======
// ─────────────────────────────────────────────────────────────────────────────
// TARJETA GPS
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaGPS extends StatefulWidget {
  final bool rutaActiva;
  final bool simulando;
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  final int pasoSimulacion;
  final int totalPasos;
  final String etiquetaActual;
  final bool llegadaDetectada;
<<<<<<< HEAD
  final Future<void> Function(bool) onToggleRuta;
=======
  final void Function(bool) onToggleRuta;
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  final VoidCallback onToggleSimulacion;
  final ll.LatLng posicionActual;
  final List<ll.LatLng> ruta;
  final ll.LatLng coordDestino;

  const _TarjetaGPS({
    required this.rutaActiva,
    required this.simulando,
<<<<<<< HEAD
    required this.descargandoRuta,
=======
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    required this.pasoSimulacion,
    required this.totalPasos,
    required this.etiquetaActual,
    required this.llegadaDetectada,
    required this.onToggleRuta,
    required this.onToggleSimulacion,
    required this.posicionActual,
    required this.ruta,
    required this.coordDestino,
  });

  @override
<<<<<<< HEAD
=======
  State<_TarjetaGPS> createState() => _TarjetaGPSState();
}

class _TarjetaGPSState extends State<_TarjetaGPS> {
  final MapController _mapController = MapController();

  @override
  void didUpdateWidget(covariant _TarjetaGPS oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.posicionActual != widget.posicionActual) {
      try {
        _mapController.move(widget.posicionActual, _mapController.camera.zoom);
      } catch (_) {}
    }
  }

  @override
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
<<<<<<< HEAD
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Row(children: [
            Icon(Icons.gps_fixed_rounded, color: _kAzul, size: 20),
            SizedBox(width: 8),
            Text("Control de Ruta",
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: _kAzul)),
          ]),
          const SizedBox(height: 16),

          // Mini-mapa
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 200,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: posicionActual,
                  initialZoom: 14.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                    userAgentPackageName: "com.usm.busemistas",
                  ),
                  if (ruta.length > 1)
                    PolylineLayer<Object>(
                      // <-- AGREGA <Object> AQUÍ para cumplir con la restricción de Flutter Map v7
                      polylines: [
                        Polyline(
                          points: ruta,
=======
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
            const SizedBox(height: 16),

            // ── MAPA ──
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.posicionActual,
                    initialZoom: 14.0,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.busemistas',
                    ),
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: widget.ruta,
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                          color: _kAzul.withValues(alpha: 0.6),
                          strokeWidth: 4,
                        ),
                      ],
<<<<<<< HEAD
                    ), // <-- Asegúrate de que cierre con su respectiva coma/paréntesis
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: posicionActual,
                        width: 40,
                        height: 40,
                        child: Container(
                          decoration: BoxDecoration(
                            color: simulando ? Colors.green : _kAzul,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(Icons.directions_bus_rounded,
                              color: Colors.white, size: 22),
                        ),
                      ),
                      Marker(
                        point: coordDestino,
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.flag_rounded,
                            color: Colors.red, size: 36),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Progreso
          if (totalPasos > 0) ...[
            Row(children: [
              const Icon(Icons.route, color: _kAzul, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(etiquetaActual,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500)),
              ),
              Text("$pasoSimulacion / $totalPasos",
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: totalPasos > 0 ? pasoSimulacion / totalPasos : 0,
                backgroundColor: Colors.grey.shade200,
                color: _kAzul,
                minHeight: 8,
              ),
            ),
            const SizedBox(height: 16),
          ],

          if (llegadaDetectada)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded, color: Colors.green),
                SizedBox(width: 8),
                Text("¡Has llegado al destino!",
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
            )
          else ...[
            Row(children: [
              Expanded(
                child: SwitchListTile.adaptive(
                  title: const Text("Ruta activa",
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(rutaActiva ? "En camino" : "Detenido",
                      style: TextStyle(
                          fontSize: 11,
                          color: rutaActiva ? Colors.green : Colors.grey)),
                  value: rutaActiva,
                  onChanged: onToggleRuta,
                  activeColor: _kAzul,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            descargandoRuta
                ? const Center(
                    child: Column(children: [
                    CircularProgressIndicator(color: _kAzul),
                    SizedBox(height: 8),
                    Text("Descargando ruta OSRM...",
                        style: TextStyle(color: _kAzul, fontSize: 12)),
                  ]))
                : OutlinedButton.icon(
                    onPressed: onToggleSimulacion,
                    icon: Icon(simulando
                        ? Icons.stop_circle_outlined
                        : Icons.play_circle_outlined),
                    label: Text(simulando
                        ? "Detener simulacion GPS"
                        : "Iniciar simulacion GPS (OSRM)"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _kAzul,
                      side: const BorderSide(color: _kAzul),
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
          ],
        ]),
=======
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: widget.posicionActual,
                          width: 50,
                          height: 50,
                          child: const Icon(
                            Icons.directions_bus_rounded,
                            color: _kAzul,
                            size: 36,
                          ),
                        ),
                        Marker(
                          point: widget.coordDestino,
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.flag_rounded,
                            color: Colors.green.shade700,
                            size: 30,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Destino alcanzado
            if (widget.llegadaDetectada)
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
                onTap: () => widget.onToggleRuta(!widget.rutaActiva),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 130,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: widget.rutaActiva
                          ? [Colors.red.shade600, Colors.red.shade800]
                          : [Colors.green.shade500, Colors.green.shade700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: widget.rutaActiva
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
                        widget.rutaActiva
                            ? Icons.stop_circle_rounded
                            : Icons.play_circle_rounded,
                        color: Colors.white,
                        size: 52,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.rutaActiva ? 'TERMINAR RUTA' : 'INICIAR RUTA',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        widget.rutaActiva
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
              if (widget.rutaActiva) ...[
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
                          'Ubicacion: ${widget.etiquetaActual}',
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
                        value: widget.totalPasos > 0
                            ? widget.pasoSimulacion / (widget.totalPasos - 1)
                            : 0,
                        backgroundColor: Colors.grey.shade200,
                        color: _kAzul,
                        minHeight: 8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: widget.onToggleSimulacion,
                      icon: Icon(widget.simulando
                          ? Icons.stop_circle_outlined
                          : Icons.play_circle_outlined),
                      label: Text(widget.simulando
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      ),
    );
  }
}

<<<<<<< HEAD
=======
// ─────────────────────────────────────────────────────────────────────────────
// TARJETA ETA (Tiempo estimado de llegada)
// ─────────────────────────────────────────────────────────────────────────────

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
class _TarjetaETA extends StatelessWidget {
  final String camionetaId;
  final FirebaseFirestore db;
  final bool sentidoHaciaUSM;

  const _TarjetaETA({
    required this.camionetaId,
    required this.db,
    required this.sentidoHaciaUSM,
  });

  double _factorTrafico(String nivel) {
    switch (nivel) {
<<<<<<< HEAD
      case "medio":
        return 1.3;
      case "alto":
=======
      case 'medio':
        return 1.3;
      case 'alto':
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        return 1.7;
      default:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
<<<<<<< HEAD
      stream: db.collection("camionetas").doc(camionetaId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox();
        final data = snap.data!.data() as Map<String, dynamic>;
        final ubicacion = data["ubicacion"] as GeoPoint?;
        final nivelTrafico = data["nivel_trafico"] as String? ?? "bajo";
=======
      stream: db.collection('camionetas').doc(camionetaId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const SizedBox();
        }

        final data = snap.data!.data() as Map<String, dynamic>;
        final ubicacion = data['ubicacion'] as GeoPoint?;
        final nivelTrafico = data['nivel_trafico'] as String? ?? 'bajo';

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        if (ubicacion == null) return const SizedBox();

        final eta = eta_calc.calcularETA(
          ubicacion.latitude,
          ubicacion.longitude,
          factorTrafico: _factorTrafico(nivelTrafico),
        );

        final destinoData = sentidoHaciaUSM
<<<<<<< HEAD
            ? eta["parada_universidad"]
            : eta["parada_california"];
        final nombreDestino = sentidoHaciaUSM ? "USM" : "La California";

        if (destinoData == null) return const SizedBox();
        final minutos = destinoData["minutos"] as double? ?? 0;
        final km = destinoData["km"] as double? ?? 0;
=======
            ? eta['parada_universidad']
            : eta['parada_california'];
        final nombreDestino =
            sentidoHaciaUSM ? 'USM (La Florencia)' : 'La California';
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _kAzul.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
<<<<<<< HEAD
                child:
                    const Icon(Icons.timer_outlined, color: _kAzul, size: 24),
=======
                child: const Icon(Icons.timer_rounded, color: _kAzul, size: 28),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
<<<<<<< HEAD
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("ETA a $nombreDestino",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: _kAzul)),
                      const SizedBox(height: 4),
                      Text(
                        "${minutos.round()} min  ·  ${km.toStringAsFixed(1)} km  ·  Tráfico: $nivelTrafico",
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ]),
              ),
=======
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Llegada estimada a $nombreDestino',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('${destinoData['eta_minutos']} min',
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: _kAzul)),
                    Text('${destinoData['distancia_km']} km restantes',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
              if (nivelTrafico != 'bajo')
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: nivelTrafico == 'alto'
                        ? Colors.red.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    nivelTrafico == 'alto'
                        ? '🔴 Trafico alto'
                        : '🟡 Trafico medio',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: nivelTrafico == 'alto'
                          ? Colors.red.shade700
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
            ]),
          ),
        );
      },
    );
  }
}

<<<<<<< HEAD
class _TarjetaPanelControl extends StatelessWidget {
  final String camionetaId;
  final FirebaseFirestore db;

  const _TarjetaPanelControl({required this.camionetaId, required this.db});

  void _cambiarTrafico(BuildContext context, String nivel) {
    db.collection("camionetas").doc(camionetaId).update({
      "nivel_trafico": nivel,
      "nivel_trafico_ts": FieldValue.serverTimestamp(),
    });
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
<<<<<<< HEAD
      stream: db.collection("camionetas").doc(camionetaId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) {
          return const Card(
              child: Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ));
        }
        final data = snap.data!.data() as Map<String, dynamic>;
        final asientos = (data["asientos"] as Map<String, dynamic>?) ?? {};
        final pasajeros = asientos.entries
            .where((e) => e.value is Map && (e.value as Map)["ocupado"] == true)
            .toList();
        final total = pasajeros.length;
        final nivelActual = data["nivel_trafico"] as String? ?? "bajo";

        return Column(children: [
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
=======
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
            .where((e) => e.value is Map && (e.value as Map)['ocupado'] == true)
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.people_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
<<<<<<< HEAD
                      Text("Pasajeros a bordo",
=======
                      Text('Pasajeros a bordo',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 16),

<<<<<<< HEAD
                    // Contador
                    Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 16),
                        decoration: BoxDecoration(
                          color: total >= 24
                              ? Colors.red.shade50
                              : total >= 18
                                  ? Colors.orange.shade50
                                  : Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: total >= 24
                                ? Colors.red.shade300
                                : total >= 18
                                    ? Colors.orange.shade300
                                    : Colors.green.shade300,
                            width: 2,
                          ),
                        ),
                        child: Column(children: [
                          RichText(
                            text: TextSpan(children: [
                              TextSpan(
                                text: "$total",
                                style: TextStyle(
                                  fontSize: 56,
                                  fontWeight: FontWeight.bold,
                                  color: total >= 24
                                      ? Colors.red.shade700
                                      : total >= 18
                                          ? Colors.orange.shade700
                                          : Colors.green.shade700,
                                ),
                              ),
                              TextSpan(
                                text: " / 24",
                                style: TextStyle(
                                    fontSize: 24,
                                    color: Colors.grey.shade500,
                                    fontWeight: FontWeight.w500),
                              ),
                            ]),
                          ),
                          Text(
                            total >= 24
                                ? "Unidad llena"
                                : total >= 18
                                    ? "Casi llena"
                                    : "Asientos disponibles",
                            style: TextStyle(
                              fontSize: 13,
                              color: total >= 24
                                  ? Colors.red.shade700
                                  : total >= 18
                                      ? Colors.orange.shade700
                                      : Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 12),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: total / 24,
                        backgroundColor: Colors.grey.shade200,
                        color: total >= 24
                            ? Colors.red
                            : total >= 18
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                                ? Colors.orange
                                : Colors.green,
                        minHeight: 10,
                      ),
                    ),
<<<<<<< HEAD
=======

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                    const SizedBox(height: 16),

                    // Lista de pasajeros
                    if (pasajeros.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
<<<<<<< HEAD
                          child: Text("Sin pasajeros aún.",
=======
                          child: Text('Sin pasajeros aun.',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Column(
                        children: pasajeros.map((entry) {
                          final v = entry.value as Map;
                          return _FilaPasajero(
                            asiento: entry.key,
<<<<<<< HEAD
                            nombre: v["nombre_pasajero"] as String? ?? "-",
                            cedula: v["cedula_pasajero"] as String? ?? "-",
                            estadoPago:
                                v["estado_pago"] as String? ?? "pendiente",
                            camionetaId: camionetaId,
                            db: db,
                          );
                        }).toList(),
                      ),
                  ]),
            ),
          ),

          const SizedBox(height: 12),

          // Selector de trafico
          Card(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
=======
                            nombre: v['nombre_pasajero'] as String? ?? '-',
                            cedula: v['cedula_pasajero'] as String? ?? '-',
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.traffic_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
<<<<<<< HEAD
                      Text("Nivel de Tráfico",
=======
                      Text('Nivel de Trafico',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 6),
<<<<<<< HEAD
                    const Text("Indica el tráfico para ajustar el ETA",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
=======
                    const Text(
                      'Indica el trafico actual para ajustar el ETA',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _BotonTrafico(
<<<<<<< HEAD
                          label: "Bajo",
                          emoji: "🟢",
                          seleccionado: nivelActual == "bajo",
                          color: Colors.green,
                          onTap: () => _cambiarTrafico(context, "bajo"),
=======
                          label: 'Bajo',
                          emoji: '🟢',
                          seleccionado: nivelActual == 'bajo',
                          color: Colors.green,
                          onTap: () => _cambiarTrafico('bajo'),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
<<<<<<< HEAD
                          label: "Medio",
                          emoji: "🟡",
                          seleccionado: nivelActual == "medio",
                          color: Colors.orange,
                          onTap: () => _cambiarTrafico(context, "medio"),
=======
                          label: 'Medio',
                          emoji: '🟡',
                          seleccionado: nivelActual == 'medio',
                          color: Colors.orange,
                          onTap: () => _cambiarTrafico('medio'),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
<<<<<<< HEAD
                          label: "Alto",
                          emoji: "🔴",
                          seleccionado: nivelActual == "alto",
                          color: Colors.red,
                          onTap: () => _cambiarTrafico(context, "alto"),
                        ),
                      ),
                    ]),
                  ]),
            ),
          ),
        ]);
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color:
              seleccionado ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
=======
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: seleccionado
              ? color.withValues(alpha: 0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
          border: Border.all(
            color: seleccionado ? color : Colors.grey.shade300,
            width: seleccionado ? 2 : 1,
          ),
        ),
<<<<<<< HEAD
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: seleccionado ? color : Colors.grey,
                  fontWeight:
                      seleccionado ? FontWeight.bold : FontWeight.normal)),
        ]),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
          .collection("camionetas")
          .doc(widget.camionetaId)
          .update({"asientos.${widget.asiento}.estado_pago": "confirmado"});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _quitarPasajero() async {
    if (widget.cedula.isEmpty || widget.cedula == "-") return;
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.person_remove_rounded,
            color: Colors.red, size: 36),
        title: const Text("Quitar pasajero"),
        content: Text(
            "¿Está seguro de quitar a C.I. ${widget.cedula}?\n\nSi pagó con saldo virtual, se le reembolsará automáticamente."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancelar")),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Quitar"),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    setState(() => _procesando = true);
    try {
      await widget.db.runTransaction((tx) async {
        final camRef =
            widget.db.collection("camionetas").doc(widget.camionetaId);
        final camSnap = await tx.get(camRef);
        if (!camSnap.exists) throw Exception("Camioneta no encontrada.");
        final asientoData =
            (camSnap.data()!["asientos"] as Map?)?[widget.asiento] as Map?;
        final estadoPago = asientoData?["estado_pago"] as String? ?? "";
        final cedulaPasajero = asientoData?["cedula_pasajero"] as String? ?? "";
        tx.update(camRef, {
          "asientos.${widget.asiento}.ocupado": false,
          "asientos.${widget.asiento}.cedula_pasajero": "",
          "asientos.${widget.asiento}.nombre_pasajero": "",
          "asientos.${widget.asiento}.estado_pago": "",
        });
        if (estadoPago == "pagado" && cedulaPasajero.isNotEmpty) {
          final userRef = widget.db.collection("usuarios").doc(cedulaPasajero);
          final userSnap = await tx.get(userRef);
          if (userSnap.exists) {
            final rolStr = userSnap.data()!["rol"] as String? ?? "estudiante";
            final rolEnum = RolUsuario.values.firstWhere(
                (r) => r.name == rolStr,
                orElse: () => RolUsuario.estudiante);
            final montoReembolso = Tarifas.pasaje(rolEnum);
            if (montoReembolso > 0) {
              tx.update(
                  userRef, {"saldo": FieldValue.increment(montoReembolso)});
            }
          }
        }
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Pasajero C.I. ${widget.cedula} retirado y reembolsado."),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Error: $e"), backgroundColor: Colors.red.shade700));
=======
          .collection('camionetas')
          .doc(widget.camionetaId)
          .update({'asientos.${widget.asiento}.estado_pago': 'confirmado'});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    final isPagado = widget.estadoPago == "pagado" ||
        widget.estadoPago == "confirmado" ||
        widget.estadoPago == "mensualidad";
    final isPendiente = widget.estadoPago == "pendiente_pago" ||
        widget.estadoPago == "en_puerta";
=======
    final isPagado = widget.estadoPago == 'pagado' ||
        widget.estadoPago == 'confirmado' ||
        widget.estadoPago == 'mensualidad';
    final isPendiente = widget.estadoPago == 'pendiente_pago' ||
        widget.estadoPago == 'en_puerta';
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce

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
<<<<<<< HEAD
            Text("C.I. ${widget.cedula}",
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ),
        if (_procesando)
          const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))
        else if (isPagado)
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Chip(
              label: Text("PAGADO",
                  style: TextStyle(
                      color: Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold)),
              backgroundColor: Colors.transparent,
              side: BorderSide(color: Colors.green),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _quitarPasajero,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Icon(Icons.close, size: 14, color: Colors.red.shade600),
              ),
            ),
          ])
        else if (isPendiente)
          Row(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              onPressed: _confirmarPago,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 10),
              ),
              child: const Text("Confirmar\nPago"),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _quitarPasajero,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Icon(Icons.close, size: 14, color: Colors.red.shade600),
              ),
            ),
          ]),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      ]),
    );
  }
}

<<<<<<< HEAD
=======
// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET EMERGENCIA CONDUCTOR
// ─────────────────────────────────────────────────────────────────────────────

>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
=======
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
<<<<<<< HEAD
          Row(children: [
            const Icon(Icons.warning_rounded, color: Colors.red, size: 26),
            const SizedBox(width: 10),
            Text(
              emergenciaActiva ? "Resolver Emergencia" : "Reportar Emergencia",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
            ),
=======
          const Row(children: [
            Icon(Icons.warning_rounded, color: Colors.red, size: 26),
            SizedBox(width: 10),
            Text('Panel de Emergencia',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.red)),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
          ]),
          const SizedBox(height: 16),
          if (emergenciaActiva) ...[
            _OpcionEmergencia(
              icono: Icons.check_circle_outline_rounded,
<<<<<<< HEAD
              label: "Resolver Emergencia",
              subtitulo: "Libera la unidad y los asientos",
=======
              label: 'Resolver Emergencia',
              subtitulo: 'Libera la unidad y reactiva el servicio',
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
              color: Colors.green,
              onTap: onResolver,
            ),
          ] else ...[
            _OpcionEmergencia(
<<<<<<< HEAD
              icono: Icons.personal_injury_rounded,
              label: "Reportar Desmayo",
              subtitulo: "Un pasajero se encuentra desmayado",
              color: Colors.red,
              onTap: () => onEmergencia("Desmayo de pasajero"),
            ),
            const SizedBox(height: 8),
            _OpcionEmergencia(
              icono: Icons.sick_rounded,
              label: "Descompensacion / Vomito",
              subtitulo: "Pasajero con malestar fisico",
              color: Colors.orange,
              onTap: () => onEmergencia("Descompensacion"),
            ),
            const SizedBox(height: 8),
            _OpcionEmergencia(
              icono: Icons.directions_car_rounded,
              label: "Colision/Choque vial",
              subtitulo: "Accidente de transito",
              color: Colors.red.shade900,
              onTap: () => onEmergencia("Colision/Choque vial"),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
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
<<<<<<< HEAD
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14, color: color)),
              Text(subtitulo,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            ]),
=======
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
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
          ),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withValues(alpha: 0.5), size: 14),
        ]),
      ),
    );
  }
<<<<<<< HEAD
}
=======
}
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
