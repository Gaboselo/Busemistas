// lib/vistas/registro_vista.dart
//
// Flujo en 2 pasos:
//   Paso 1 → Seleccionar rol + ingresar cédula → validar en listas institucionales
//   Paso 2 → Completar datos según el rol

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';

class RegistroVista extends StatefulWidget {
  const RegistroVista({super.key});

  @override
  State<RegistroVista> createState() => _RegistroVistaState();
}

class _RegistroVistaState extends State<RegistroVista> {
  // ── Controladores ───────────────────────────────────────────────
  final _formPaso1 = GlobalKey<FormState>();
  final _formPaso2 = GlobalKey<FormState>();

  final _cedulaCtrl = TextEditingController();
  final _nombreCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();

  int _paso = 1;

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _nombreCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _razonSocialCtrl.dispose();
    super.dispose();
  }

  // ── PASO 1: Validar cédula ──────────────────────────────────────
  Future<void> _avanzarPaso1(BuildContext context) async {
    if (!_formPaso1.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final cedula = _cedulaCtrl.text.trim();

    if (auth.rolSeleccionado == RolUsuario.visitante) {
      // Visitante: saltar validación institucional
      _nombreCtrl.clear();
      setState(() => _paso = 2);
      return;
    }

    // Estudiante o conductor: buscar en listas
    final encontrado = await auth.validarCedulaInstitucional(cedula);

    if (!context.mounted) return;

    if (encontrado) {
      // Autocompletar nombre desde Firestore
      _nombreCtrl.text = auth.nombreCompleto ?? '';
      setState(() => _paso = 2);
    } else {
      _mostrarDialogoNoEncontrado(context);
    }
  }

  void _mostrarDialogoNoEncontrado(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cédula no encontrada'),
        content: const Text(
          'Tu cédula no está en las listas institucionales de la USM.\n\n'
          '¿Deseas continuar como visitante?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().seleccionarRol(RolUsuario.visitante);
              _nombreCtrl.clear();
              setState(() => _paso = 2);
            },
            child: const Text('Continuar como visitante'),
          ),
        ],
      ),
    );
  }

  // ── PASO 2: Registrar usuario ───────────────────────────────────
  Future<void> _registrar(BuildContext context) async {
    if (!_formPaso2.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();

    final exito = await auth.registrarUsuario(
      cedula: _cedulaCtrl.text.trim(),
      nombreCompleto: _nombreCtrl.text.trim(),
      correo: _correoCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      rol: auth.rolSeleccionado ?? RolUsuario.visitante,
      razonSocial: _razonSocialCtrl.text.trim(),
    );

    if (!context.mounted) return;

    if (exito) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Registro exitoso. Ya puedes iniciar sesión.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context); // Volver a login
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.mensajeError ?? 'Error al registrar.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── Build ───────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cargando = auth.estado == AuthEstado.cargando;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        centerTitle: true,
        leading: _paso == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _paso = 1),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: _paso == 1
                ? _buildPaso1(context, auth, cargando, colors)
                : _buildPaso2(context, auth, cargando, colors),
          ),
        ),
      ),
    );
  }

  // ── Widget Paso 1 ───────────────────────────────────────────────
  Widget _buildPaso1(BuildContext context, AuthProvider auth, bool cargando,
      ColorScheme colors) {
    return Form(
      key: _formPaso1,
      child: Column(
        key: const ValueKey('paso1'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Indicador de progreso
          _IndicadorPasos(pasoActual: 1),
          const SizedBox(height: 28),

          Text('¿Quién eres?',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Selector de rol
          _SelectorRol(
            rolActual: auth.rolSeleccionado,
            onSeleccionar: (rol) => auth.seleccionarRol(rol),
          ),
          const SizedBox(height: 24),

          if (auth.rolSeleccionado != null) ...[
            // Campo Cédula
            CampoTexto(
              controller: _cedulaCtrl,
              etiqueta: 'Número de Cédula',
              hint: 'Solo dígitos, sin puntos ni espacios',
              icono: Icons.badge_outlined,
              keyboardType: TextInputType.number,
              maxLength: 12,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: Validadores.cedula,
            ),
            const SizedBox(height: 12),

            // Aviso contexto
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: colors.secondaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: colors.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      auth.rolSeleccionado == RolUsuario.visitante
                          ? 'Como visitante, deberás completar tu nombre y el motivo de tu visita.'
                          : 'Tu nombre será cargado automáticamente desde las listas de la USM.',
                      style: TextStyle(
                          fontSize: 12, color: colors.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            FilledButton(
              onPressed: cargando ? null : () => _avanzarPaso1(context),
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
                  : const Text('Continuar', style: TextStyle(fontSize: 16)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Widget Paso 2 ───────────────────────────────────────────────
  Widget _buildPaso2(BuildContext context, AuthProvider auth, bool cargando,
      ColorScheme colors) {
    final esVisitante = auth.rolSeleccionado == RolUsuario.visitante;

    return Form(
      key: _formPaso2,
      child: Column(
        key: const ValueKey('paso2'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _IndicadorPasos(pasoActual: 2),
          const SizedBox(height: 28),

          Text('Completa tu perfil',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),

          // Nombre completo
          CampoTexto(
            controller: _nombreCtrl,
            etiqueta: 'Nombre completo',
            icono: Icons.person_outline,
            bloqueado: auth.nombreBloqueado,
            validator: Validadores.nombreCompleto,
          ),
          const SizedBox(height: 16),

          // Correo
          CampoTexto(
            controller: _correoCtrl,
            etiqueta: 'Correo electrónico',
            hint: 'tu@correo.com',
            icono: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: Validadores.correo,
          ),
          const SizedBox(height: 16),

          // Teléfono
          CampoTexto(
            controller: _telefonoCtrl,
            etiqueta: 'Teléfono',
            hint: '+56912345678',
            icono: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
            validator: Validadores.telefono,
          ),

          // Solo para visitantes
          if (esVisitante) ...[
            const SizedBox(height: 16),
            CampoTexto(
              controller: _razonSocialCtrl,
              etiqueta: 'Motivo de visita / Razón social',
              hint: 'Ej: Empresa Consultora SpA — reunión con Dirección',
              icono: Icons.business_outlined,
              validator: Validadores.razonSocial,
            ),
          ],

          const SizedBox(height: 28),

          FilledButton(
            onPressed: cargando ? null : () => _registrar(context),
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
                : const Text('Crear cuenta', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

// ── Widgets auxiliares ───────────────────────────────────────────

class _IndicadorPasos extends StatelessWidget {
  final int pasoActual;
  const _IndicadorPasos({required this.pasoActual});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        _Paso(numero: 1, activo: pasoActual >= 1, colors: colors),
        Expanded(
          child: Divider(
            color: pasoActual >= 2 ? colors.primary : colors.outline,
            thickness: 2,
          ),
        ),
        _Paso(numero: 2, activo: pasoActual >= 2, colors: colors),
      ],
    );
  }
}

class _Paso extends StatelessWidget {
  final int numero;
  final bool activo;
  final ColorScheme colors;
  const _Paso(
      {required this.numero, required this.activo, required this.colors});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: activo ? colors.primary : colors.surfaceVariant,
      child: Text(
        '$numero',
        style: TextStyle(
          color: activo ? colors.onPrimary : colors.onSurfaceVariant,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}

class _SelectorRol extends StatelessWidget {
  final RolUsuario? rolActual;
  final void Function(RolUsuario) onSeleccionar;

  const _SelectorRol({required this.rolActual, required this.onSeleccionar});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _TarjetaRol(
          rol: RolUsuario.estudiante,
          icono: Icons.school_outlined,
          etiqueta: 'Estudiante',
          activo: rolActual == RolUsuario.estudiante,
          onTap: () => onSeleccionar(RolUsuario.estudiante),
        ),
        const SizedBox(width: 10),
        _TarjetaRol(
          rol: RolUsuario.conductor,
          icono: Icons.drive_eta_outlined,
          etiqueta: 'Conductor',
          activo: rolActual == RolUsuario.conductor,
          onTap: () => onSeleccionar(RolUsuario.conductor),
        ),
        const SizedBox(width: 10),
        _TarjetaRol(
          rol: RolUsuario.visitante,
          icono: Icons.person_pin_outlined,
          etiqueta: 'Visitante',
          activo: rolActual == RolUsuario.visitante,
          onTap: () => onSeleccionar(RolUsuario.visitante),
        ),
      ],
    );
  }
}

class _TarjetaRol extends StatelessWidget {
  final RolUsuario rol;
  final IconData icono;
  final String etiqueta;
  final bool activo;
  final VoidCallback onTap;

  const _TarjetaRol({
    required this.rol,
    required this.icono,
    required this.etiqueta,
    required this.activo,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: activo
                ? colors.primaryContainer
                : colors.surfaceVariant.withOpacity(0.4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: activo ? colors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono,
                  color: activo ? colors.primary : colors.onSurfaceVariant),
              const SizedBox(height: 6),
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: activo ? FontWeight.bold : FontWeight.normal,
                  color: activo ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
