// lib/vistas/registro_vista.dart
// Busemistas USM v3
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios:
//   - Agrega campo Contrasenia (obligatorio)
//   - nombre_completo se copia automaticamente de lista oficial (no editable)
//   - Estudiante jamas tipea su nombre

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';
import 'estudiante_home_vista.dart';
import 'conductor_home_vista.dart';

const Color _kAzul = Color(0xFF0E004A);

class RegistroVista extends StatefulWidget {
  const RegistroVista({super.key});

  @override
  State<RegistroVista> createState() => _RegistroVistaState();
}

class _RegistroVistaState extends State<RegistroVista> {
  final _formPaso1 = GlobalKey<FormState>();
  final _formPaso2 = GlobalKey<FormState>();

  final _cedulaCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passConfirmCtrl = TextEditingController();
  final _razonSocialCtrl = TextEditingController();
  final _nombreVisitanteCtrl = TextEditingController();

  int _paso = 1;
  bool _verPass = false;
  bool _verPassConfirm = false;

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    _passCtrl.dispose();
    _passConfirmCtrl.dispose();
    _razonSocialCtrl.dispose();
    _nombreVisitanteCtrl.dispose();
    super.dispose();
  }

  // ── PASO 1: Verificar cedula ─────────────────────────────────────
  Future<void> _avanzarPaso1(BuildContext context) async {
    if (!_formPaso1.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final cedula = _cedulaCtrl.text.trim();

    if (auth.rolSeleccionado == RolUsuario.visitante) {
      setState(() => _paso = 2);
      return;
    }

    final resultado = await auth.verificarCedula(cedula);
    if (!context.mounted) return;

    switch (resultado) {
      case ResultadoVerificacion.yaRegistrado:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esta cedula ya tiene cuenta. Inicia sesion.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
        break;
      case ResultadoVerificacion.noAutorizado:
        _mostrarDialogoNoAutorizado(context);
        break;
      case ResultadoVerificacion.esEstudiante:
      case ResultadoVerificacion.esConductor:
      case ResultadoVerificacion.esEmpleado:
        setState(() => _paso = 2);
        break;
      case ResultadoVerificacion.error:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(auth.mensajeError ?? 'Error al verificar cedula.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        break;
    }
  }

  void _mostrarDialogoNoAutorizado(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.no_accounts, color: Colors.orange, size: 40),
        title: const Text('Cedula no autorizada'),
        content: const Text(
            'Tu cedula no figura en las listas institucionales de la USM.\n'
            'Puedes registrarte como visitante.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              context.read<AuthProvider>().seleccionarRol(RolUsuario.visitante);
              setState(() => _paso = 2);
            },
            child: const Text('Registrarme como Visitante'),
          ),
        ],
      ),
    );
  }

  // ── PASO 2: Guardar usuario ──────────────────────────────────────
  Future<void> _registrar(BuildContext context) async {
    if (!_formPaso2.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final cedula = _cedulaCtrl.text.trim();
    final rol = auth.rolSeleccionado ?? RolUsuario.visitante;

    if (_passCtrl.text.trim() != _passConfirmCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Las contrasenias no coinciden.'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final ok = await auth.registrarUsuario(
      cedula: cedula,
      correo: _correoCtrl.text.trim(),
      telefono: _telefonoCtrl.text.trim(),
      contrasenia: _passCtrl.text.trim(),
      rol: rol,
      razonSocial: _razonSocialCtrl.text.trim(),
      nombreManual:
          rol == RolUsuario.visitante ? _nombreVisitanteCtrl.text.trim() : null,
    );

    if (!context.mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.mensajeError ?? 'Error al registrar.'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    // Redirigir segun rol
    final destino = rol == RolUsuario.conductor
        ? const ConductorHomeVista()
        : const EstudianteHomeVista();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destino),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cargando = auth.estado == AuthEstado.cargando;
    final rol = auth.rolSeleccionado;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(_paso == 1 ? 'Verificar Cedula' : 'Crear Cuenta'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        leading: _paso == 2
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _paso = 1),
              )
            : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: _paso == 1
            ? _FormPaso1(
                formKey: _formPaso1,
                cedulaCtrl: _cedulaCtrl,
                cargando: cargando,
                onAvanzar: () => _avanzarPaso1(context),
                onSeleccionarRol: (r) =>
                    context.read<AuthProvider>().seleccionarRol(r),
                rolActual: rol,
              )
            : _FormPaso2(
                formKey: _formPaso2,
                correoCtrl: _correoCtrl,
                telefonoCtrl: _telefonoCtrl,
                passCtrl: _passCtrl,
                passConfirmCtrl: _passConfirmCtrl,
                razonSocialCtrl: _razonSocialCtrl,
                nombreVisitanteCtrl: _nombreVisitanteCtrl,
                verPass: _verPass,
                verPassConfirm: _verPassConfirm,
                onTogglePass: () => setState(() => _verPass = !_verPass),
                onTogglePassConfirm: () =>
                    setState(() => _verPassConfirm = !_verPassConfirm),
                rol: rol ?? RolUsuario.visitante,
                nombreCopiadoLista: auth.nombreCompleto,
                cargando: cargando,
                onRegistrar: () => _registrar(context),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMULARIO PASO 1
// ─────────────────────────────────────────────────────────────────────────────

class _FormPaso1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController cedulaCtrl;
  final bool cargando;
  final VoidCallback onAvanzar;
  final void Function(RolUsuario) onSeleccionarRol;
  final RolUsuario? rolActual;

  const _FormPaso1({
    required this.formKey,
    required this.cedulaCtrl,
    required this.cargando,
    required this.onAvanzar,
    required this.onSeleccionarRol,
    required this.rolActual,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Tipo de cuenta',
            style: TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14, color: _kAzul)),
        const SizedBox(height: 12),

        // Selector de rol
<<<<<<< HEAD
// Selector de rol — 4 opciones en 2x2 grid
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 3.0,
          children: [
            _BotonRol(
              label: 'Estudiante',
              icono: Icons.school_rounded,
              seleccionado: rolActual == RolUsuario.estudiante,
              onTap: () => onSeleccionarRol(RolUsuario.estudiante),
            ),
            _BotonRol(
              label: 'Conductor',
              icono: Icons.drive_eta_rounded,
              seleccionado: rolActual == RolUsuario.conductor,
              onTap: () => onSeleccionarRol(RolUsuario.conductor),
            ),
            _BotonRol(
              label: 'Visitante',
              icono: Icons.badge_outlined,
              seleccionado: rolActual == RolUsuario.visitante,
              onTap: () => onSeleccionarRol(RolUsuario.visitante),
            ),
            _BotonRol(
              label: 'Profesor/Empleado',
              icono: Icons.work_outline_rounded,
              seleccionado: rolActual == RolUsuario.empleado,
              onTap: () => onSeleccionarRol(RolUsuario.empleado),
            ),
          ],
        ),
=======
        Row(children: [
          _BotonRol(
            label: 'Estudiante',
            icono: Icons.school_rounded,
            seleccionado: rolActual == RolUsuario.estudiante,
            onTap: () => onSeleccionarRol(RolUsuario.estudiante),
          ),
          const SizedBox(width: 8),
          _BotonRol(
            label: 'Conductor',
            icono: Icons.drive_eta_rounded,
            seleccionado: rolActual == RolUsuario.conductor,
            onTap: () => onSeleccionarRol(RolUsuario.conductor),
          ),
          const SizedBox(width: 8),
          _BotonRol(
            label: 'Visitante',
            icono: Icons.badge_outlined,
            seleccionado: rolActual == RolUsuario.visitante,
            onTap: () => onSeleccionarRol(RolUsuario.visitante),
          ),
        ]),
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
        const SizedBox(height: 24),

        CampoTexto(
          controller: cedulaCtrl,
          etiqueta: 'Numero de Cedula',
          hint: 'Solo numeros',
          icono: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          validator: Validadores.cedula,
        ),
        const SizedBox(height: 24),

        FilledButton.icon(
          onPressed: cargando ? null : onAvanzar,
          icon: cargando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.arrow_forward_rounded),
          label: Text(cargando ? 'Verificando...' : 'Verificar Cedula'),
          style: FilledButton.styleFrom(
            backgroundColor: _kAzul,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),

        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
<<<<<<< HEAD
                  'Para Estudiantes, Conductores y Profesores/Empleados, el sistema '
                  'verificará tu cédula contra las listas institucionales de la USM '
=======
                  'Para Estudiantes y Conductores, el sistema verificara '
                  'tu cedula contra las listas institucionales de la USM '
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
                  'antes de continuar.',
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORMULARIO PASO 2
// ─────────────────────────────────────────────────────────────────────────────

class _FormPaso2 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController correoCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController passCtrl;
  final TextEditingController passConfirmCtrl;
  final TextEditingController razonSocialCtrl;
  final TextEditingController nombreVisitanteCtrl;
  final bool verPass;
  final bool verPassConfirm;
  final VoidCallback onTogglePass;
  final VoidCallback onTogglePassConfirm;
  final RolUsuario rol;
  final String? nombreCopiadoLista;
  final bool cargando;
  final VoidCallback onRegistrar;

  const _FormPaso2({
    required this.formKey,
    required this.correoCtrl,
    required this.telefonoCtrl,
    required this.passCtrl,
    required this.passConfirmCtrl,
    required this.razonSocialCtrl,
    required this.nombreVisitanteCtrl,
    required this.verPass,
    required this.verPassConfirm,
    required this.onTogglePass,
    required this.onTogglePassConfirm,
    required this.rol,
    required this.nombreCopiadoLista,
    required this.cargando,
    required this.onRegistrar,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Nombre: solo lectura para est/conductor, editable para visitante
        if (rol != RolUsuario.visitante && nombreCopiadoLista != null) ...[
          const Text('Nombre (verificado por la USM)',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.green.shade300),
            ),
            child: Row(children: [
              Icon(Icons.verified_rounded,
                  color: Colors.green.shade700, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nombreCopiadoLista!,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800),
                ),
              ),
              Icon(Icons.lock_rounded, color: Colors.green.shade400, size: 16),
            ]),
          ),
          const SizedBox(height: 14),
        ] else if (rol == RolUsuario.visitante) ...[
          CampoTexto(
            controller: nombreVisitanteCtrl,
            etiqueta: 'Nombre completo',
            hint: 'Tu nombre real',
            icono: Icons.person_outline,
            validator: Validadores.nombreCompleto,
          ),
          const SizedBox(height: 14),
        ],

        CampoTexto(
          controller: correoCtrl,
          etiqueta: 'Correo electronico',
          hint: 'correo@ejemplo.com',
          icono: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          validator: Validadores.correo,
        ),
        const SizedBox(height: 14),

        CampoTexto(
          controller: telefonoCtrl,
          etiqueta: 'Telefono',
          hint: '+584141234567',
          icono: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
          ],
          validator: Validadores.telefono,
        ),
        const SizedBox(height: 14),

        // Campo contrasenia
        TextFormField(
          controller: passCtrl,
          obscureText: !verPass,
          decoration: InputDecoration(
            labelText: 'Crear Contrasenia',
            hintText: 'Minimo 4 caracteres',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(verPass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: onTogglePass,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'La contrasenia es obligatoria.';
            }
            if (v.trim().length < 4) return 'Minimo 4 caracteres.';
            return null;
          },
        ),
        const SizedBox(height: 14),

        // Confirmar contrasenia
        TextFormField(
          controller: passConfirmCtrl,
          obscureText: !verPassConfirm,
          decoration: InputDecoration(
            labelText: 'Confirmar Contrasenia',
            hintText: 'Repite tu contrasenia',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(verPassConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: onTogglePassConfirm,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return 'Confirma tu contrasenia.';
            }
            return null;
          },
        ),
        const SizedBox(height: 14),

        if (rol == RolUsuario.visitante) ...[
          CampoTexto(
            controller: razonSocialCtrl,
            etiqueta: 'Motivo de visita / Razon social',
            hint: 'Describe el motivo de tu visita',
            icono: Icons.assignment_outlined,
            validator: Validadores.razonSocial,
          ),
          const SizedBox(height: 14),
        ],

        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: cargando ? null : onRegistrar,
          icon: cargando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.how_to_reg_rounded),
          label: Text(cargando ? 'Registrando...' : 'Crear Cuenta'),
          style: FilledButton.styleFrom(
            backgroundColor: _kAzul,
            minimumSize: const Size.fromHeight(52),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ]),
    );
  }
}

class _BotonRol extends StatelessWidget {
  final String label;
  final IconData icono;
  final bool seleccionado;
  final VoidCallback onTap;

  const _BotonRol(
      {required this.label,
      required this.icono,
      required this.seleccionado,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: seleccionado ? _kAzul : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border:
                Border.all(color: seleccionado ? _kAzul : Colors.grey.shade300),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono,
                  color: seleccionado ? Colors.white : Colors.grey.shade600,
                  size: 20),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 11,
                      color: seleccionado ? Colors.white : Colors.grey.shade700,
                      fontWeight:
                          seleccionado ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
