import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  // Le dice a Flutter que asegure la inicialización antes de arrancar la app
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializamos Firebase manualmente pasando tus credenciales directamente
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

class MiAppTransporte extends StatelessWidget {
  const MiAppTransporte({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Text(
            "¡Firebase conectado manualmente con éxito! 🚀",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
