/// lib/main.dart
library;
// Busemistas USM v2 — Color institucional: Color(0xFF0E004A)

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/camioneta_provider.dart';
import 'vistas/login_vista.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
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
    debugPrint("🚀 Firebase conectado — Busemistas USM v2");
  } catch (e) {
    debugPrint("❌ Error Firebase: $e");
  }

  runApp(const BusemistasApp());
}

// ── Color institucional global ─────────────────────────────────────────────
const Color kColorInstitucional = Color(0xFF0E004A);

class BusemistasApp extends StatelessWidget {
  const BusemistasApp({super.key});

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
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: kColorInstitucional,
            primary: kColorInstitucional,
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: kColorInstitucional,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: kColorInstitucional,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        home: const LoginVista(),
      ),
    );
  }
}
