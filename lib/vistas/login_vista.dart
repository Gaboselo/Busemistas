// lib/vistas/login_vista.dart
// Busemistas USM v3
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios:
//   - Login exige cedula + contrasenia
//   - QR: si no tiene cuenta -> redirige a registro con datos prellenados
//   - Registro copia nombre de lista oficial

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';
import 'estudiante_home_vista.dart';
import 'conductor_home_vista.dart';
import 'registro_vista.dart';

const Color _kAzul = Color(0xFF003380);

class LoginVista extends StatefulWidget {
  const LoginVista({super.key});

  @override
  State<LoginVista> createState() => _LoginVistaState();
}

class _LoginVistaState extends State<LoginVista>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _cedulaCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _verPassword = false;

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _cedulaCtrl.dispose();
    _passCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── Login manual: cedula + contrasenia ──────────────────────────
  Future<void> _iniciarSesion(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final cedula = _cedulaCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    final rol = await auth.login(cedula, pass);
    if (!context.mounted) return;

    if (rol == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(auth.mensajeError ?? 'Credenciales incorrectas.'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    _navegar(context, rol);
  }

  void _navegar(BuildContext context, RolUsuario rol) {
    final destino = rol == RolUsuario.conductor
        ? const ConductorHomeVista()
        : const EstudianteHomeVista();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destino),
      (_) => false,
    );
  }

  // ── Login via QR ─────────────────────────────────────────────────
  Future<void> _iniciarEscaneoQR(BuildContext context) async {
    final cedulaLeida = await Navigator.push<String>(
      context,
      MaterialPageRoute(
          builder: (_) => const _SimuladorQRVista(), fullscreenDialog: true),
    );
    if (!mounted || cedulaLeida == null || cedulaLeida.isEmpty) return;

    if (!RegExp(r'^\d+$').hasMatch(cedulaLeida)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('QR invalido: no contiene una cedula valida.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final auth = context.read<AuthProvider>();
    final rol = await auth.loginQR(cedulaLeida);
    if (!context.mounted) return;

    if (rol != null) {
      _navegar(context, rol);
      return;
    }

    // Necesita registro (primera vez con este carnet)
    if (auth.mensajeError == '__NECESITA_REGISTRO__') {
      auth.limpiarError();
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RegistroVista()),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(auth.mensajeError ?? 'Error al verificar carnet.'),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cargando = auth.estado == AuthEstado.cargando;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: _kAzul,
      body: SafeArea(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height - 80),
            child: Column(
              children: [
                // ── Header ──────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 40),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF003380), Color(0xFF1A0070)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(children: [
                    Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8))
                        ],
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          size: 48, color: Colors.white),
                    ),
                    const SizedBox(height: 18),
                    const Text('Busemistas USM',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        )),
                    const SizedBox(height: 4),
                    Text('Universidad Santa Maria - Caracas',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 13)),
                  ]),
                ),

                // ── Tarjeta de login ─────────────────────────────────
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Iniciar Sesion',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: _kAzul,
                                  )),
                          const SizedBox(height: 6),
                          Text('Cedula + contrasenia o escanea tu carnet',
                              style: TextStyle(
                                  color: Colors.grey.shade600, fontSize: 13)),
                          const SizedBox(height: 24),

                          // Boton QR
                          _BotonQR(onTap: () => _iniciarEscaneoQR(context)),
                          const SizedBox(height: 20),

                          Row(children: [
                            const Expanded(child: Divider()),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text('o ingresa manualmente',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 12)),
                            ),
                            const Expanded(child: Divider()),
                          ]),
                          const SizedBox(height: 20),

                          Form(
                            key: _formKey,
                            child: Column(children: [
                              CampoTexto(
                                controller: _cedulaCtrl,
                                etiqueta: 'Numero de Cedula',
                                hint: 'Solo numeros (ej: 25891234)',
                                icono: Icons.badge_outlined,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(12),
                                ],
                                validator: Validadores.cedula,
                              ),
                              const SizedBox(height: 14),
                              // Campo contrasenia
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: !_verPassword,
                                decoration: InputDecoration(
                                  labelText: 'contrasenia',
                                  hintText: 'Tu contrasenia de acceso',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_verPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined),
                                    onPressed: () => setState(
                                        () => _verPassword = !_verPassword),
                                  ),
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'La contrasenia es obligatoria.';
                                  }
                                  if (v.trim().length < 4) {
                                    return 'Minimo 4 caracteres.';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: cargando
                                    ? null
                                    : () => _iniciarSesion(context),
                                icon: cargando
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white))
                                    : const Icon(Icons.login_rounded),
                                label: Text(
                                    cargando ? 'Verificando...' : 'Entrar'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kAzul,
                                  minimumSize: const Size.fromHeight(52),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14)),
                                ),
                              ),
                            ]),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('No tienes cuenta?',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 14)),
                              TextButton(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const RegistroVista()),
                                ),
                                child: const Text('Registrate aqui',
                                    style: TextStyle(
                                        color: _kAzul,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTON QR
// ─────────────────────────────────────────────────────────────────────────────

class _BotonQR extends StatelessWidget {
  final VoidCallback onTap;
  const _BotonQR({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF003380), Color(0xFF3A0CA3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: _kAzul.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Escanear Carnet USM',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                Text('Acceso rapido y seguro',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12)),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white70, size: 16),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIMULADOR QR
// ─────────────────────────────────────────────────────────────────────────────

class _SimuladorQRVista extends StatefulWidget {
  const _SimuladorQRVista();

  @override
  State<_SimuladorQRVista> createState() => _SimuladorQRVistaState();
}

class _SimuladorQRVistaState extends State<_SimuladorQRVista>
    with TickerProviderStateMixin {
  late AnimationController _scanCtrl;
  late Animation<double> _scanAnim;
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;

  bool _escaneado = false;
  bool _validando = false;
  String? _cedulaLeida;

  // Cedulas demo para QR
  static const Map<String, String> _carnetsDemoQR = {
    'QR-USM-2024-26781234': '26781234',
    'QR-USM-2024-27654321': '27654321',
    'QR-USM-2024-20000001': '20000001',
  };

  final _cedulaManualCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scanCtrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _scanAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _scanCtrl, curve: Curves.easeInOut));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _pulseCtrl.dispose();
    _cedulaManualCtrl.dispose();
    super.dispose();
  }

  Future<void> _simularEscaneo(String codigoQR) async {
    if (_validando) return;
    setState(() => _validando = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    final cedula = _carnetsDemoQR[codigoQR] ?? codigoQR;
    setState(() {
      _escaneado = true;
      _cedulaLeida = cedula;
      _validando = false;
    });
    await Future.delayed(const Duration(milliseconds: 700));
    if (mounted) Navigator.of(context).pop(cedula);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escaner de Carnet USM'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Marco animado
            _MarcoQR(
                scanAnim: _scanAnim,
                pulseAnim: _pulseAnim,
                escaneado: _escaneado,
                validando: _validando),
            const SizedBox(height: 32),

            if (!_escaneado && !_validando) ...[
              const Text('Apunta al codigo QR del Carnet USM',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 28),
              const Text('DEMO - Selecciona un carnet:',
                  style: TextStyle(
                      color: Colors.white54, fontSize: 11, letterSpacing: 1)),
              const SizedBox(height: 12),
              ..._carnetsDemoQR.keys.map((qr) {
                final cedula = _carnetsDemoQR[qr]!;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 40, vertical: 4),
                  child: OutlinedButton.icon(
                    onPressed: () => _simularEscaneo(qr),
                    icon: const Icon(Icons.credit_card,
                        color: Colors.white70, size: 18),
                    label: Text('Carnet C.I. $cedula',
                        style: const TextStyle(color: Colors.white70)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.3)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _cedulaManualCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Ingresar C.I. manualmente',
                        hintStyle: const TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: Colors.white54),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () {
                      final ci = _cedulaManualCtrl.text.trim();
                      if (ci.isNotEmpty) _simularEscaneo(ci);
                    },
                    icon: const Icon(Icons.send_rounded, color: Colors.white70),
                  ),
                ]),
              ),
            ],

            if (_validando)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Column(children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 12),
                  Text('Validando carnet...',
                      style: TextStyle(color: Colors.white70)),
                ]),
              ),

            if (_escaneado)
              Column(children: [
                const Icon(Icons.check_circle_rounded,
                    color: Colors.greenAccent, size: 48),
                const SizedBox(height: 8),
                Text('C.I. $_cedulaLeida detectada',
                    style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ]),
          ],
        ),
      ),
    );
  }
}

class _MarcoQR extends StatelessWidget {
  final Animation<double> scanAnim;
  final Animation<double> pulseAnim;
  final bool escaneado;
  final bool validando;
  const _MarcoQR(
      {required this.scanAnim,
      required this.pulseAnim,
      required this.escaneado,
      required this.validando});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([scanAnim, pulseAnim]),
      builder: (_, __) {
        final color = escaneado ? Colors.greenAccent : const Color(0xFF7B5EA7);
        return ScaleTransition(
          scale: pulseAnim,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              children: [
                if (!escaneado)
                  Positioned(
                    top: 220 * scanAnim.value,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            color,
                            Colors.transparent
                          ],
                        ),
                      ),
                    ),
                  ),
                Center(
                  child: Icon(Icons.qr_code_2_rounded,
                      color: escaneado
                          ? Colors.greenAccent
                          : Colors.white.withValues(alpha: 0.15),
                      size: 80),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
