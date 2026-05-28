import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Librería para manejar la base de datos

void main() async {
  // Asegura que Flutter esté listo antes de inicializar Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // 1. TU CONEXIÓN MANUAL A FIREBASE
  // (Reemplaza estos textos con tus credenciales reales de la web, las que usamos antes)
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
//          LÓGICA DEL BACKEND (POO)
// ==========================================

// El molde de nuestro objeto Camioneta
class Camioneta {
  String id;
  GeoPoint posicion;
  String chofer;

  // Constructor: define cómo se construye el objeto
  Camioneta({required this.id, required this.posicion, required this.chofer});
}

// Función asíncrona que envía los datos del objeto a la nube de Google
void actualizarUbicacionEnNube(Camioneta autobus) async {
  await FirebaseFirestore.instance
      .collection('camionetas') // Busca la lista en la web
      .doc(autobus.id) // Busca el documento (unidad_01)
      .update({
        // Actualiza los campos con los datos del objeto
        'posicion': autobus.posicion,
      });
  print("¡Ubicación de la ${autobus.id} actualizada en Firebase! 📡");
}

// ==========================================
//         INTERFAZ GRÁFICA (FRONTEND)
// ==========================================

class MiAppTransporte extends StatelessWidget {
  const MiAppTransporte({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Control de Carlos chupalo - Simulador"),
          backgroundColor: Colors.blueAccent,
        ),
        // El StreamBuilder se queda "escuchando" la base de datos en vivo
        body: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('camionetas')
              .doc('unidad_01')
              .snapshots(),
          builder: (context, snapshot) {
            // Mientras descarga los datos por primera vez
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            // Si hay un error o borraste el documento en la web
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return const Center(
                child: Text(
                  "Falta crear el documento 'unidad_01' en Firebase web.",
                ),
              );
            }

            // Mapeo de datos (Como extraer datos de un archivo o struct)
            var datosCamioneta = snapshot.data!.data() as Map<String, dynamic>;
            GeoPoint posicion =
                datosCamioneta['posicion'] ?? GeoPoint(0.0, 0.0);
            String chofer = datosCamioneta['chofer'] ?? "Sin nombre";

            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      "Chofer: $chofer",
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Latitud GeoPost: {${posicion.latitude}}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      "Longitud (GeoPost): ${posicion.longitude}",
                      style: const TextStyle(
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 40),

                    // EL BOTÓN DEL PASO 4
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 15,
                        ),
                      ),
                      icon: const Icon(
                        Icons.directions_bus,
                        color: Colors.white,
                      ),
                      label: const Text(
                        "Simular Avance (Mover Autobús)",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                      onPressed: () {
                        // 1. Usamos POO para crear un objeto con coordenadas un poco movidas

                        GeoPoint nuevaPosicion = GeoPoint(
                          posicion.latitude + 0.001,
                          posicion.longitude - 0.001,
                        );

                        Camioneta unidadActualizada = Camioneta(
                          id: 'unidad_01',
                          posicion: nuevaPosicion,
                          chofer: chofer,
                        );

                        // 2. Llamamos a tu función de backend para subirlo
                        actualizarUbicacionEnNube(unidadActualizada);
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
