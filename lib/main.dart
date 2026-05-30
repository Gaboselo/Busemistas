import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
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

// ==========================================
//          LÓGICA DEL BACKEND (GPS)
// ==========================================

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

// ==========================================
//          LÓGICA DEL BACKEND (POO)
// ==========================================

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
  print("📡 Ubicación actualizada: ${autobus.posicion.latitude}, ${autobus.posicion.longitude}");
}

// ==========================================
//         INTERFAZ GRÁFICA (FRONTEND)
// ==========================================

class MiAppTransporte extends StatefulWidget {
  const MiAppTransporte({super.key});

  @override
  State<MiAppTransporte> createState() => _MiAppTransporteState();
}

class _MiAppTransporteState extends State<MiAppTransporte> {
  StreamSubscription<Position>? _trackingSubscription;
  bool _trackingActivo = false;

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
        distanceFilter: 0, // Solo actualiza si se movió más de 10 metros
      ),
    ).listen((Position posicion) {
      actualizarUbicacionEnNube(Camioneta(
        id: 'unidad_01',
        posicion: GeoPoint(posicion.latitude, posicion.longitude),
        chofer: 'Viryin Redondocalves',
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
      home: Scaffold(
        appBar: AppBar(
          title: const Text("BUSEMISTAS - GPS Conductor"),
          backgroundColor: Colors.blueAccent,
        ),
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('camionetas')
              .doc('unidad_01')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text("Falta crear el documento 'unidad_01' en Firebase."),
              );
            }

            var datos = snapshot.data!.data() as Map<String, dynamic>;
            GeoPoint posicion = datos['posicion'] ?? GeoPoint(0.0, 0.0);
            String chofer = datos['chofer'] ?? "Sin nombre";

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Chofer: $chofer",
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Text("Latitud: ${posicion.latitude}",
                        style: const TextStyle(fontSize: 16, fontFamily: 'monospace')),
                    Text("Longitud: ${posicion.longitude}",
                        style: const TextStyle(fontSize: 16, fontFamily: 'monospace')),
                    const SizedBox(height: 20),

                    // INDICADOR DE ESTADO
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

                    const SizedBox(height: 30),

                    // BOTÓN INICIAR TRACKING
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                      icon: const Icon(Icons.gps_fixed, color: Colors.white),
                      label: const Text("Iniciar Tracking",
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      onPressed: _trackingActivo ? null : _iniciarTracking,
                    ),

                    const SizedBox(height: 15),

                    // BOTÓN DETENER TRACKING
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                      icon: const Icon(Icons.gps_off, color: Colors.white),
                      label: const Text("Detener Tracking",
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      onPressed: _trackingActivo ? _detenerTracking : null,
                    ),

                    const SizedBox(height: 15),

                    // BOTÓN SIMULADO
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                      ),
                      icon: const Icon(Icons.directions_bus, color: Colors.white),
                      label: const Text("Simular Avance (prueba)",
                          style: TextStyle(color: Colors.white, fontSize: 16)),
                      onPressed: () {
                        GeoPoint nuevaPosicion = GeoPoint(
                          posicion.latitude + 0.001,
                          posicion.longitude - 0.001,
                        );
                        actualizarUbicacionEnNube(Camioneta(
                          id: 'unidad_01',
                          posicion: nuevaPosicion,
                          chofer: chofer,
                        ));
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}