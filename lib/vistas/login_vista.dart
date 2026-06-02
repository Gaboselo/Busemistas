// lib/vistas/login_vista.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';
import 'registro_vista.dart';
import 'estudiante_home_vista.dart';
import 'conductor_home_vista.dart';

class LoginVista extends StatefulWidget {
  const LoginVista({super.key});

  @override
  State<LoginVista> createState() => _LoginVistaState();
}

class _LoginVistaState extends State<LoginVista> {
  final _formKey = GlobalKey<FormState>();
  final _cedulaCtrl = TextEditingController();

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    super.dispose();
  }

  Future<void> _iniciarSesion(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final rol = await auth.login(_cedulaCtrl.text.trim());

    if (!context.mounted) return;

    if (rol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.mensajeError ?? 'Error desconocido.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    // Navegar borrando el historial para que no puedan volver al login
    switch (rol) {
      case RolUsuario.estudiante:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EstudianteHomeVista()),
        );
      case RolUsuario.conductor:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ConductorHomeVista()),
        );
      case RolUsuario.visitante:
        // Los visitantes por ahora van al home del estudiante (solo lectura)
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const EstudianteHomeVista()),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cargando = auth.estado == AuthEstado.cargando;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.directions_bus_rounded,
                      size: 72, color: colors.primary),
                  const SizedBox(height: 12),
                  Text(
                    'Busemistas USM',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: colors.primary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Inicia sesión con tu cédula',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: colors.onSurface.withOpacity(0.6)),
                  ),
                  const SizedBox(height: 36),
                  CampoTexto(
                    controller: _cedulaCtrl,
                    etiqueta: 'Cédula',
                    hint: 'Ej: 12345678',
                    icono: Icons.badge_outlined,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: Validadores.cedula,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: cargando ? null : () => _iniciarSesion(context),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: cargando
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Iniciar sesión',
                            style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: cargando
                        ? null
                        : () {
                            auth.limpiarError();
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const RegistroVista()),
                            );
                          },
                    child: const Text('¿No tienes cuenta? Regístrate aquí'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
