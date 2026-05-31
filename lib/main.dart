import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyAupvDu_ZomdZiM-mMNRdKJ3zK0ypRY9lY",
      authDomain: "transporte-usm.firebaseapp.com",
      projectId: "transporte-usm",
      storageBucket: "transporte-usm.firebasestorage.app",
      messagingSenderId: "286764501080",
      appId: "1:286764501080:web:9faeb3ab264b39321aa22d",
    ),
  );

  runApp(const MiAppTransporte());
}

Future<bool> pedirPermisosUbicacion() async {
  bool servicioActivo = await Geolocator.isLocationServiceEnabled();
  if (!servicioActivo) return false;

  LocationPermission permiso = await Geolocator.checkPermission();
  if (permiso == LocationPermission.denied) {
    permiso = await Geolocator.requestPermission();
    if (permiso == LocationPermission.denied) return false;
  }
  if (permiso == LocationPermission.deniedForever) {
    await Geolocator.openAppSettings();
    return false;
  }
  return true;
}

class Camioneta {
  String id;
  GeoPoint posicion;
  String chofer;
  Camioneta({required this.id, required this.posicion, required this.chofer});
}

void actualizarUbicacionEnNube(Camioneta autobus) async {
  await FirebaseFirestore.instance
      .collection('camionetas')
      .doc(autobus.id)
      .update({'posicion': autobus.posicion});
}

Future<String> procesarPagoOnline(String cedulaEstudiante) async {
  const double costoPasaje = 240.0;
  try {
    QuerySnapshot resultado = await FirebaseFirestore.instance
        .collection('pasajeros')
        .where('Cedula', isEqualTo: cedulaEstudiante)
        .get();

    if (resultado.docs.isEmpty) return "❌ Estudiante no encontrado";

    DocumentSnapshot estudianteDoc = resultado.docs.first;
    double saldoActual = (estudianteDoc['saldo'] as num).toDouble();

    if (saldoActual < costoPasaje) {
      return "❌ Saldo insuficiente. Saldo actual: $saldoActual bs";
    }

    await FirebaseFirestore.instance
        .collection('pasajeros')
        .doc(estudianteDoc.id)
        .update({'saldo': saldoActual - costoPasaje});

    DocumentSnapshot camionetaDoc = await FirebaseFirestore.instance
        .collection('camionetas')
        .doc('unidad_01')
        .get();

    double ingresosActuales = (camionetaDoc['Ingresos'] as num).toDouble();

    await FirebaseFirestore.instance
        .collection('camionetas')
        .doc('unidad_01')
        .update({'Ingresos': ingresosActuales + costoPasaje});

    return "✅ Pago exitoso. Nuevo saldo: ${saldoActual - costoPasaje} bs";
  } catch (e) {
    return "❌ Error en el pago: $e";
  }
}

class MiAppTransporte extends StatefulWidget {
  const MiAppTransporte({super.key});

  @override
  State<MiAppTransporte> createState() => _MiAppTransporteState();
}

class _MiAppTransporteState extends State<MiAppTransporte> {
  StreamSubscription<Position>? _trackingSubscription;
  bool _trackingActivo = false;
  bool _centrarMapa = true;
  final MapController _mapController = MapController();
  LatLng _posicionMapa = LatLng(10.5744, -66.9104);
  String _chofer = "Cargando...";
  GeoPoint _posicionFirebase = GeoPoint(10.5744, -66.9104);

  @override
  void initState() {
    super.initState();
    FirebaseFirestore.instance
        .collection('camionetas')
        .doc('unidad_01')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        var datos = snapshot.data() as Map<String, dynamic>;
        setState(() {
          _chofer = datos['chofer'] ?? "Sin nombre";
          _posicionFirebase = datos['posicion'] ?? GeoPoint(0.0, 0.0);
        });
      }
    });
  }

  void _iniciarTracking() async {
    bool tienePermiso = await pedirPermisosUbicacion();
    if (!tienePermiso) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ No se pudo obtener permiso de ubicación")),
      );
      return;
    }

    setState(() => _trackingActivo = true);

    _trackingSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((Position posicion) {
      setState(() {
        _posicionMapa = LatLng(posicion.latitude, posicion.longitude);
      });

      if (_centrarMapa) {
        _mapController.move(_posicionMapa, 17.0);
      }

      actualizarUbicacionEnNube(Camioneta(
        id: 'unidad_01',
        posicion: GeoPoint(posicion.latitude, posicion.longitude),
        chofer: _chofer,
      ));
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Tracking iniciado")),
    );
  }

  void _detenerTracking() {
    _trackingSubscription?.cancel();
    _trackingSubscription = null;
    setState(() => _trackingActivo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🛑 Tracking detenido")),
    );
  }

  @override
  void dispose() {
    _trackingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text("BUSEMISTAS - GPS Conductor"),
            backgroundColor: Colors.blueAccent,
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: Colors.blueAccent,
            child: const Icon(Icons.my_location, color: Colors.white),
            onPressed: () {
              setState(() => _centrarMapa = true);
              _mapController.move(_posicionMapa, 17.0);
            },
          ),
          body: Column(
            children: [
              Expanded(
                flex: 3,
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _posicionMapa,
                    initialZoom: 17.0,
                    onMapEvent: (event) {
                      if (event is MapEventMoveStart) {
                        setState(() => _centrarMapa = false);
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.transporte_app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _posicionMapa,
                          width: 60,
                          height: 60,
                          child: const Icon(
                            Icons.directions_bus,
                            color: Colors.blue,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              Expanded(
                flex: 2,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("Chofer: $_chofer",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 5),
                        Text("Lat: ${_posicionFirebase.latitude.toStringAsFixed(6)}",
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                        Text("Lng: ${_posicionFirebase.longitude.toStringAsFixed(6)}",
                            style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: _trackingActivo ? Colors.green[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _trackingActivo ? "🟢 Tracking activo" : "⚫ Tracking inactivo",
                            style: TextStyle(
                              color: _trackingActivo ? Colors.green[800] : Colors.grey[600],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              icon: const Icon(Icons.gps_fixed, color: Colors.white),
                              label: const Text("Iniciar",
                                  style: TextStyle(color: Colors.white)),
                              onPressed: _trackingActivo ? null : _iniciarTracking,
                            ),
                            const SizedBox(width: 15),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              ),
                              icon: const Icon(Icons.gps_off, color: Colors.white),
                              label: const Text("Detener",
                                  style: TextStyle(color: Colors.white)),
                              onPressed: _trackingActivo ? _detenerTracking : null,
                            ),
                          ],
                        ),

                        const SizedBox(height: 15),

                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                          icon: const Icon(Icons.payment, color: Colors.white),
                          label: const Text("Pagar Pasaje (prueba)",
                              style: TextStyle(color: Colors.white)),
                          onPressed: () async {
                            String resultado = await procesarPagoOnline('12.345.678');
                            print("Resultado pago: $resultado");
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(resultado)),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}