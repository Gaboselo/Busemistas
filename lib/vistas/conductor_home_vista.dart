// lib/vistas/conductor_home_vista.dart
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

const Color _kAzul = Color(0xFF003380);

// Coordenadas de las dos paradas
const LatLngSimple _coordUSM =
    LatLngSimple(10.491360068207142, -66.78017873573735);
const LatLngSimple _coordLaCalif = LatLngSimple(10.483376, -66.819402);

// Ruta base de waypoints (fallback si OSRM falla)
const List<GeoPoint> _rutaBaseHaciaUSM = [
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
};

class _PerfilCamioneta {
  final String modelo;
  final String color;
  const _PerfilCamioneta({required this.modelo, required this.color});
}

class LatLngSimple {
  final double lat;
  final double lng;
  const LatLngSimple(this.lat, this.lng);
}

Map<String, dynamic> _asientosVacios24() {
  final m = <String, dynamic>{};
  for (int i = 1; i <= 24; i++) {
    m['$i'] = {
      "ocupado": false,
      "cedula_pasajero": "",
      "nombre_pasajero": "",
      "estado_pago": "",
    };
  }
  return m;
}

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
  @override
  State<ConductorHomeVista> createState() => _ConductorHomeVistaState();
}

class _ConductorHomeVistaState extends State<ConductorHomeVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

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

  @override
  void dispose() {
    _timerSimulacion?.cancel();
    super.dispose();
  }

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

    if (_simulando) {
      _detenerSimulacion();
      return;
    }

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
        timer.cancel();
        setState(() => _simulando = false);
        return;
      }
      setState(() => _pasoSimulacion = siguiente);
      await _escribirUbicacion(_rutaOSRM[siguiente]);
      await _verificarLlegada(_rutaOSRM[siguiente]);
    });
  }

  Future<void> _verificarLlegada(ll.LatLng pos) async {
    if (_llegadaDetectada) return;
    final distancia = Geolocator.distanceBetween(
      pos.latitude,
      pos.longitude,
      _coordDestino.lat,
      _coordDestino.lng,
    );
    if (distancia <= kUmbralLlegadaMetros) {
      _llegadaDetectada = true;
      _timerSimulacion?.cancel();
      setState(() => _simulando = false);
      await _llegadaAutomatica();
    }
  }

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
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      _mostrarError("Error al registrar llegada: $e");
    }
  }

  void _detenerSimulacion() {
    _timerSimulacion?.cancel();
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
      setState(() {
        _sentidoHaciaUSM = nuevoSentido;
        _pasoSimulacion = 0;
        _llegadaDetectada = false;
        _rutaActiva = false;
        _rutaOSRM = [];
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text("Abordaje abierto. Nuevo destino: $nuevoDestino"),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
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
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      _mostrarError("Error emergencia: $e");
    }
  }

  Future<void> _resolverEmergencia() async {
    try {
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

                _TarjetaETA(
                  camionetaId: _camionetaId,
                  db: _db,
                  sentidoHaciaUSM: _sentidoHaciaUSM,
                ),
                const SizedBox(height: 12),

                if (_llegadaDetectada)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FilledButton.icon(
                      onPressed: _abrirAbordajeRegreso,
                      icon: const Icon(Icons.door_sliding_rounded),
                      label: const Text("Abrir abordaje / Recibir estudiantes"),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),

                _TarjetaPanelControl(camionetaId: _camionetaId, db: _db),
                const SizedBox(height: 12),

                if (!_llegadaDetectada)
                  FilledButton.icon(
                    onPressed: _rutaActiva ? _finalizarViaje : null,
                    icon: const Icon(Icons.flag_rounded),
                    label: const Text("Finalizar Viaje"),
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

// =============================================================================
// WIDGETS DEL CONDUCTOR (Header, GPS, Panel Control, ETA, Emergencia, etc.)
// =============================================================================

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
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("¡Hola, $primerNombre!",
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
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
        IconButton(
          icon: const Icon(Icons.logout_rounded, color: Colors.white70),
          onPressed: onLogout,
        ),
      ]),
    );
  }
}

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF003380), Color(0xFF3A0CA3)],
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
          ),
        ]),
      ),
    );
  }
}

class _TarjetaGPS extends StatelessWidget {
  final bool rutaActiva;
  final bool simulando;
  final bool descargandoRuta;
  final int pasoSimulacion;
  final int totalPasos;
  final String etiquetaActual;
  final bool llegadaDetectada;
  final Future<void> Function(bool) onToggleRuta;
  final VoidCallback onToggleSimulacion;
  final ll.LatLng posicionActual;
  final List<ll.LatLng> ruta;
  final ll.LatLng coordDestino;

  const _TarjetaGPS({
    required this.rutaActiva,
    required this.simulando,
    required this.descargandoRuta,
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
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                          color: _kAzul.withValues(alpha: 0.6),
                          strokeWidth: 4,
                        ),
                      ],
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
      ),
    );
  }
}

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
      case "medio":
        return 1.3;
      case "alto":
        return 1.7;
      default:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection("camionetas").doc(camionetaId).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || !snap.data!.exists) return const SizedBox();
        final data = snap.data!.data() as Map<String, dynamic>;
        final ubicacion = data["ubicacion"] as GeoPoint?;
        final nivelTrafico = data["nivel_trafico"] as String? ?? "bajo";
        if (ubicacion == null) return const SizedBox();

        final eta = eta_calc.calcularETA(
          ubicacion.latitude,
          ubicacion.longitude,
          factorTrafico: _factorTrafico(nivelTrafico),
        );

        final destinoData = sentidoHaciaUSM
            ? eta["parada_universidad"]
            : eta["parada_california"];
        final nombreDestino = sentidoHaciaUSM ? "USM" : "La California";

        if (destinoData == null) return const SizedBox();
        final minutos = destinoData["minutos"] as double? ?? 0;
        final km = destinoData["km"] as double? ?? 0;

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
                child:
                    const Icon(Icons.timer_outlined, color: _kAzul, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
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
            ]),
          ),
        );
      },
    );
  }
}

class _TarjetaPanelControl extends StatelessWidget {
  final String camionetaId;
  final FirebaseFirestore db;

  const _TarjetaPanelControl({required this.camionetaId, required this.db});

  void _cambiarTrafico(BuildContext context, String nivel) {
    db.collection("camionetas").doc(camionetaId).update({
      "nivel_trafico": nivel,
      "nivel_trafico_ts": FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.people_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
                      Text("Pasajeros a bordo",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 16),

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
                          child: Text("Sin pasajeros aún.",
                              style: TextStyle(color: Colors.grey)),
                        ),
                      )
                    else
                      Column(
                        children: pasajeros.map((entry) {
                          final v = entry.value as Map;
                          return _FilaPasajero(
                            asiento: entry.key,
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.traffic_rounded, color: _kAzul, size: 20),
                      SizedBox(width: 8),
                      Text("Nivel de Tráfico",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _kAzul)),
                    ]),
                    const SizedBox(height: 6),
                    const Text("Indica el tráfico para ajustar el ETA",
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 14),
                    Row(children: [
                      Expanded(
                        child: _BotonTrafico(
                          label: "Bajo",
                          emoji: "🟢",
                          seleccionado: nivelActual == "bajo",
                          color: Colors.green,
                          onTap: () => _cambiarTrafico(context, "bajo"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
                          label: "Medio",
                          emoji: "🟡",
                          seleccionado: nivelActual == "medio",
                          color: Colors.orange,
                          onTap: () => _cambiarTrafico(context, "medio"),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _BotonTrafico(
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
          border: Border.all(
            color: seleccionado ? color : Colors.grey.shade300,
            width: seleccionado ? 2 : 1,
          ),
        ),
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
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPagado = widget.estadoPago == "pagado" ||
        widget.estadoPago == "confirmado" ||
        widget.estadoPago == "mensualidad";
    final isPendiente = widget.estadoPago == "pendiente_pago" ||
        widget.estadoPago == "en_puerta";

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
      ]),
    );
  }
}

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
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_rounded, color: Colors.red, size: 26),
            const SizedBox(width: 10),
            Text(
              emergenciaActiva ? "Resolver Emergencia" : "Reportar Emergencia",
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
            ),
          ]),
          const SizedBox(height: 16),
          if (emergenciaActiva) ...[
            _OpcionEmergencia(
              icono: Icons.check_circle_outline_rounded,
              label: "Resolver Emergencia",
              subtitulo: "Libera la unidad y los asientos",
              color: Colors.green,
              onTap: onResolver,
            ),
          ] else ...[
            _OpcionEmergencia(
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
              color: color.withValues(alpha: 0.5), size: 14),
        ]),
      ),
    );
  }
}
