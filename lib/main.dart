// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/camioneta_provider.dart';
import 'vistas/login_vista.dart';

void main() async {
  // Asegura la inicialización de los componentes nativos de Flutter
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Conexión oficial y manual con tus datos reales de Firebase de la imagen
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyAupvDu_ZomdZiM-mMNRdKJ3zK0ypRY9lY",
        authDomain: "transporte-usm.firebaseapp.com",
        projectId: "transporte-usm",
        storageBucket: "transporte-usm.firebasestorage.app",
        messagingSenderId: "28676401080",
        appId: "1:286764501080:web:9faeb3ab264b39321aa22d",
      ),
    );
    debugPrint("🚀 ¡Conexión con Firebase establecida con éxito!");
  } catch (e) {
    debugPrint("❌ Error crítico al iniciar Firebase: $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => CamionetaProvider()),
      ],
      child: MaterialApp(
        title: 'Busemistas USM',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          primaryColor: Colors.indigo,
          useMaterial3: true,
        ),
        home: const LoginVista(),
      ),
    );
  }
}
