// lib/vistas/monedero_vista.dart
// Busemistas USM v5
// REGLA: variables/comentarios sin tildes. Textos de UI con ortografia correcta.
// Cambios v5:
//   - Plan renombrado a "Plan Busemistas" en toda la UI
//   - Precio del plan es dinamico via Tarifas.plan(rol): $14 estudiante / $7 empleado
//   - Visitantes no pueden activar el Plan Busemistas (solo pasajes individuales)
//   - notifyListeners() en AuthProvider tras cada cobro para sincronizar saldo

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';

const Color _kAzul = Color(0xFF0E004A);

// Precio oficial del plan ahora es dinamico via Tarifas.plan(rol).
// Esta constante se mantiene solo como fallback de compatibilidad.
const double kPrecioPlanFallback = 14.00;

class MonederoVista extends StatefulWidget {
  const MonederoVista({super.key});

  @override
  State<MonederoVista> createState() => _MonederoVistaState();
}

class _MonederoVistaState extends State<MonederoVista>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late TabController _tabCtrl;
  bool _procesando = false;

  final _formRecarga = GlobalKey<FormState>();
  final _referenciaCtrl = TextEditingController();
  final _telefonoEmisorCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();

  static const _bancos = [
    'Banco de Venezuela',
    'Banesco',
    'Mercantil',
    'BNC',
    'BBVA Provincial',
    'Bicentenario',
    'Exterior',
    'Banplus',
    'Otro',
  ];
  String? _bancoSeleccionado;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _referenciaCtrl.dispose();
    _telefonoEmisorCtrl.dispose();
    _montoCtrl.dispose();
    super.dispose();
  }

  // ── Recarga ──────────────────────────────────────────────────────
  Future<void> _procesarRecarga(BuildContext context) async {
    if (!_formRecarga.currentState!.validate()) return;
    if (_bancoSeleccionado == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Selecciona tu banco emisor.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final monto = double.tryParse(_montoCtrl.text.trim()) ?? 0;
    if (monto <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ingresa un monto valido.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    setState(() => _procesando = true);
    final auth = context.read<AuthProvider>();
    final cedula = auth.cedulaActual;
    if (cedula == null) return;

    try {
      await _db.runTransaction((tx) async {
        final userRef = _db.collection('usuarios').doc(cedula);
        final snap = await tx.get(userRef);
        if (!snap.exists) throw Exception('Usuario no encontrado.');

        final recargaRef = _db.collection('recargas_pendientes').doc();
        tx.set(recargaRef, {
          'cedula': cedula,
          'nombre': auth.nombreCompleto ?? '',
          'monto': monto,
          'referencia': _referenciaCtrl.text.trim(),
          'banco_emisor': _bancoSeleccionado,
          'telefono_emisor': _telefonoEmisorCtrl.text.trim(),
          'estado': 'aprobado',
          'fecha': FieldValue.serverTimestamp(),
        });
        tx.update(userRef, {'saldo': FieldValue.increment(monto)});
      });

      if (!context.mounted) return;
      await auth.refrescarDatosUsuario();

      _referenciaCtrl.clear();
      _telefonoEmisorCtrl.clear();
      _montoCtrl.clear();
      setState(() => _bancoSeleccionado = null);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Recarga de \$${monto.toStringAsFixed(2)} aplicada.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceAll('Exception: ', '')),
        backgroundColor: Colors.red.shade700,
      ));
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // ── Activar Plan Busemistas con transaccion ACID ────────────────
  // Precio: dinamico segun rol (Tarifas.plan): $14 estudiante / $7 empleado
  // Visitantes: bloqueados - solo pueden comprar pasajes individuales
  // Validaciones:
  //   1. Rol visitante -> bloqueo con mensaje explicativo
  //   2. Si mensualidad_activa == true en Firestore -> aviso SnackBar
  //   3. Si saldo < precio del plan -> bloquear con mensaje
  //   4. Si ok -> descontar saldo y activar plan 30 dias via transaccion
  Future<void> _activarPlanUsemista(BuildContext context) async {
    setState(() => _procesando = true);
    final auth = context.read<AuthProvider>();
    final cedula = auth.cedulaActual;
    final rol = auth.rolSeleccionado;
    if (cedula == null) {
      setState(() => _procesando = false);
      return;
    }

    // Validacion 0: visitantes no pueden contratar el plan
    if (!Tarifas.tienePlanDisponible(rol)) {
      setState(() => _procesando = false);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
          'Los visitantes solo pueden adquirir pasajes individuales. '
          'El Plan Busemistas está disponible para estudiantes y empleados.',
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 5),
      ));
      return;
    }

    // Precio dinamico segun el rol del usuario
    final precioPlan = Tarifas.plan(rol);
    final nombrePlan = Tarifas.nombrePlan(rol);

    try {
      // Leer estado actual directo de Firestore (fuente de verdad)
      final snap = await _db.collection('usuarios').doc(cedula).get();
      if (!snap.exists) throw Exception('Usuario no encontrado.');

      final data = snap.data()!;
      final planYaActivo = data['mensualidad_activa'] as bool? ?? false;
      final saldoActual = (data['saldo'] as num?)?.toDouble() ?? 0.0;

      // Validacion 1: ya tiene plan activo
      if (planYaActivo) {
        setState(() => _procesando = false);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ya posees el $nombrePlan activo en tu cuenta.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      // Validacion 2: saldo insuficiente
      if (saldoActual < precioPlan) {
        setState(() => _procesando = false);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Saldo insuficiente (\$${saldoActual.toStringAsFixed(2)}). '
            'Necesitas \$${precioPlan.toStringAsFixed(2)} para el $nombrePlan.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        return;
      }

      // Mostrar dialogo de confirmacion con precio correcto
      if (!context.mounted) return;
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.card_membership, color: _kAzul, size: 36),
          title: Text('Activar $nombrePlan'),
          content: Text(
            'Se descontarán \$${precioPlan.toStringAsFixed(2)} de tu saldo.\n'
            'Tu plan quedará activo por 30 días.\n'
            'Tu asiento será GRATIS en cada viaje.\n\n'
            '¿Confirmar?',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAzul),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Activar'),
            ),
          ],
        ),
      );

      if (confirmar != true) {
        setState(() => _procesando = false);
        return;
      }

      // Transaccion ACID: descontar saldo y activar plan
      await _db.runTransaction((tx) async {
        final userRef = _db.collection('usuarios').doc(cedula);
        final txSnap = await tx.get(userRef);
        if (!txSnap.exists) throw Exception('Usuario no encontrado.');

        final txData = txSnap.data()!;
        final txPlanActivo = txData['mensualidad_activa'] as bool? ?? false;
        final txSaldo = (txData['saldo'] as num?)?.toDouble() ?? 0.0;

        // Re-verificar en la transaccion (evita condicion de carrera)
        if (txPlanActivo) throw Exception('__PLAN_YA_ACTIVO__');
        if (txSaldo < precioPlan) {
          throw Exception('Saldo insuficiente dentro de la transaccion.');
        }

        final vencimiento =
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 30)));

        tx.update(userRef, {
          'saldo': FieldValue.increment(-precioPlan),
          'mensualidad_activa': true,
          'vencimiento_mensualidad': vencimiento,
        });
      });

      if (!context.mounted) return;
      // Refrescar saldo en el Provider para que toda la app se actualice
      await auth.refrescarDatosUsuario();
      auth.actualizarMensualidad(true);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$nombrePlan activado. ¡Vigencia: 30 días!'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg == '__PLAN_YA_ACTIVO__') {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Ya posees el $nombrePlan activo en tu cuenta.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
          backgroundColor: Colors.red.shade700,
        ));
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cedula = auth.cedulaActual ?? '';
    final rol = auth.rolSeleccionado;
    final nombrePlan = Tarifas.nombrePlan(rol);
    final precioPlan = Tarifas.plan(rol);
    final puedeContratarPlan = Tarifas.tienePlanDisponible(rol);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monedero Virtual'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: [
            const Tab(icon: Icon(Icons.add_card_outlined), text: 'Recargar'),
            Tab(
                icon: const Icon(Icons.card_membership_outlined),
                text: nombrePlan),
          ],
        ),
      ),
      body: Column(
        children: [
          // Saldo en tiempo real via StreamBuilder
          StreamBuilder<DocumentSnapshot>(
            stream: _db.collection('usuarios').doc(cedula).snapshots(),
            builder: (context, snap) {
              double saldo = auth.saldo;
              bool planActivo = auth.mensualidadActiva;
              DateTime? vencimiento;

              if (snap.hasData && snap.data!.exists) {
                final data = snap.data!.data() as Map<String, dynamic>;
                saldo = (data['saldo'] as num?)?.toDouble() ?? 0.0;
                planActivo = data['mensualidad_activa'] as bool? ?? false;
                final ts = data['vencimiento_mensualidad'] as Timestamp?;
                if (ts != null) vencimiento = ts.toDate();

                // Auto-desactivar plan vencido
                if (planActivo &&
                    vencimiento != null &&
                    DateTime.now().isAfter(vencimiento)) {
                  planActivo = false;
                  _db
                      .collection('usuarios')
                      .doc(cedula)
                      .update({'mensualidad_activa': false});
                }
              }

              return _TarjetaSaldo(
                saldo: saldo,
                planActivo: planActivo,
                vencimiento: vencimiento,
                nombre: auth.nombreCompleto ?? '',
                nombrePlan: nombrePlan,
              );
            },
          ),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // Tab 1: Recarga
                _TabRecarga(
                  formKey: _formRecarga,
                  referenciaCtrl: _referenciaCtrl,
                  telefonoEmisorCtrl: _telefonoEmisorCtrl,
                  montoCtrl: _montoCtrl,
                  bancos: _bancos,
                  bancoSeleccionado: _bancoSeleccionado,
                  procesando: _procesando,
                  onBancoChanged: (v) => setState(() => _bancoSeleccionado = v),
                  onProcesar: () => _procesarRecarga(context),
                ),
                // Tab 2: Plan Busemistas (rol-dinamico)
                _TabPlanBusemistas(
                  planActivo: auth.mensualidadActiva,
                  procesando: _procesando,
                  saldo: auth.saldo,
                  precioPlan: precioPlan,
                  nombrePlan: nombrePlan,
                  puedeContratarPlan: puedeContratarPlan,
                  onActivar: () => _activarPlanUsemista(context),
                ),
              ],
            ),
          ),

          // Pie de pagina legal
          const _PiePagina(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA DE SALDO
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaSaldo extends StatelessWidget {
  final double saldo;
  final bool planActivo;
  final DateTime? vencimiento;
  final String nombre;
  // Nombre dinamico del plan para mostrar en el badge
  final String nombrePlan;

  const _TarjetaSaldo({
    required this.saldo,
    required this.planActivo,
    required this.vencimiento,
    required this.nombre,
    required this.nombrePlan,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E004A), Color(0xFF3A0CA3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: _kAzul.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nombre.split(' ').first,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 4),
                  const Text('Saldo disponible',
                      style: TextStyle(color: Colors.white60, fontSize: 12)),
                  Text('\$${saldo.toStringAsFixed(2)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet_rounded,
                  color: Colors.white, size: 28),
            ),
          ]),
          if (planActivo) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.card_membership,
                    color: Colors.greenAccent, size: 16),
                const SizedBox(width: 6),
                Text(
                  vencimiento != null
                      ? '$nombrePlan hasta ${vencimiento!.day}/${vencimiento!.month}/${vencimiento!.year}'
                      : '$nombrePlan activo',
                  style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB RECARGA
// ─────────────────────────────────────────────────────────────────────────────

class _TabRecarga extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController referenciaCtrl;
  final TextEditingController telefonoEmisorCtrl;
  final TextEditingController montoCtrl;
  final List<String> bancos;
  final String? bancoSeleccionado;
  final bool procesando;
  final void Function(String?) onBancoChanged;
  final VoidCallback onProcesar;

  const _TabRecarga({
    required this.formKey,
    required this.referenciaCtrl,
    required this.telefonoEmisorCtrl,
    required this.montoCtrl,
    required this.bancos,
    required this.bancoSeleccionado,
    required this.procesando,
    required this.onBancoChanged,
    required this.onProcesar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Datos de recarga',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: _kAzul)),
            const SizedBox(height: 4),
            Text('Realiza un pago movil y registra los datos aqui.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 20),

            // Info cuenta destino
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 18),
                    const SizedBox(width: 8),
                    const Text('Cuenta destino Busemistas',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  const _FilaInfo(label: 'Banco:', valor: 'Banesco'),
                  const _FilaInfo(label: 'Telefono:', valor: '0412-0000000'),
                  const _FilaInfo(label: 'RIF:', valor: 'J-305390042'),
                  const _FilaInfo(
                      label: 'Titular:', valor: 'Busemistas USM C.A.'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              initialValue: bancoSeleccionado,
              decoration: InputDecoration(
                labelText: 'Banco emisor',
                prefixIcon: const Icon(Icons.account_balance_outlined),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              ),
              items: bancos
                  .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                  .toList(),
              onChanged: onBancoChanged,
              validator: (v) => v == null ? 'Selecciona tu banco.' : null,
            ),
            const SizedBox(height: 14),

            CampoTexto(
              controller: telefonoEmisorCtrl,
              etiqueta: 'Tu telefono emisor',
              hint: '0414-1234567',
              icono: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: Validadores.telefono,
            ),
            const SizedBox(height: 14),

            CampoTexto(
              controller: referenciaCtrl,
              etiqueta: 'Numero de referencia',
              hint: 'Ej: 0123456789',
              icono: Icons.confirmation_number_outlined,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (v) => v == null || v.isEmpty
                  ? 'Ingresa el numero de referencia.'
                  : null,
            ),
            const SizedBox(height: 14),

            CampoTexto(
              controller: montoCtrl,
              etiqueta: 'Monto transferido (\$)',
              hint: 'Ej: 10.00',
              icono: Icons.attach_money,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Ingresa el monto.';
                final d = double.tryParse(v);
                if (d == null || d <= 0) return 'Monto invalido.';
                return null;
              },
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: procesando ? null : onProcesar,
              icon: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add_card),
              label: Text(procesando ? 'Procesando...' : 'Confirmar Recarga'),
              style: FilledButton.styleFrom(
                backgroundColor: _kAzul,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'En produccion las recargas quedan pendientes hasta '
              'aprobacion del administrador.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaInfo extends StatelessWidget {
  final String label;
  final String valor;
  const _FilaInfo({required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(width: 6),
        Text(valor,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB PLAN BUSEMISTAS (rol-dinamico)
// ─────────────────────────────────────────────────────────────────────────────

class _TabPlanBusemistas extends StatelessWidget {
  final bool planActivo;
  final bool procesando;
  final double saldo;
  // Precio correcto segun rol (viene de Tarifas.plan)
  final double precioPlan;
  // Nombre del plan ("Plan Busemistas" o "Plan Empleado")
  final String nombrePlan;
  // Si el rol puede contratar el plan (visitante = false)
  final bool puedeContratarPlan;
  final VoidCallback onActivar;

  const _TabPlanBusemistas({
    required this.planActivo,
    required this.procesando,
    required this.saldo,
    required this.precioPlan,
    required this.nombrePlan,
    required this.puedeContratarPlan,
    required this.onActivar,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        // Banner del plan
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: planActivo
                ? const LinearGradient(
                    colors: [Colors.green, Color(0xFF00A878)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : !puedeContratarPlan
                    ? LinearGradient(
                        colors: [Colors.grey.shade600, Colors.grey.shade400],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : const LinearGradient(
                        colors: [Color(0xFF0E004A), Color(0xFF3A0CA3)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: _kAzul.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(children: [
            Icon(
              planActivo
                  ? Icons.verified_rounded
                  : !puedeContratarPlan
                      ? Icons.block_rounded
                      : Icons.card_membership_rounded,
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              planActivo
                  ? '$nombrePlan ACTIVO'
                  : !puedeContratarPlan
                      ? 'No disponible para Visitantes'
                      : nombrePlan,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            if (puedeContratarPlan)
              Text(
                '\$${precioPlan.toStringAsFixed(2)} / mes',
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
          ]),
        ),
        const SizedBox(height: 20),

        // Mensaje bloqueante para visitantes
        if (!puedeContratarPlan) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade300),
            ),
            child: Column(children: [
              Row(children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Plan no disponible para Visitantes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Los visitantes pueden adquirir pasajes individuales. '
                'El plan mensual está disponible únicamente para '
                'estudiantes y empleados de la USM.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ]),
          ),
        ] else ...[
          // Beneficios
          const _FilaBeneficio(
              icono: Icons.event_seat_rounded,
              texto: 'Tu asiento personal GRATIS en cada viaje'),
          _FilaBeneficio(
              icono: Icons.person_add_alt_1_rounded,
              texto: 'Asientos adicionales para acompañantes a tarifa normal'),
          const _FilaBeneficio(
              icono: Icons.calendar_month_rounded,
              texto: 'Vigencia de 30 días continuos'),
          const _FilaBeneficio(
              icono: Icons.savings_rounded,
              texto: 'Ahorro estimado vs pago individual'),
          const SizedBox(height: 20),

          if (!planActivo) ...[
            Text(
              'Saldo actual: \$${saldo.toStringAsFixed(2)} / Necesitas: \$${precioPlan.toStringAsFixed(2)}',
              style: TextStyle(
                  color: saldo >= precioPlan
                      ? Colors.green.shade700
                      : Colors.red.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: (procesando || saldo < precioPlan) ? null : onActivar,
              icon: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.card_membership_rounded),
              label: Text(procesando
                  ? 'Activando...'
                  : saldo < precioPlan
                      ? 'Saldo insuficiente'
                      : 'Activar $nombrePlan - \$${precioPlan.toStringAsFixed(2)}'),
              style: FilledButton.styleFrom(
                backgroundColor: _kAzul,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '¡Tu $nombrePlan está activo! Disfruta de viajes con descuento.',
                    style: const TextStyle(
                        color: Colors.green, fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ),
          ],
        ],
      ]),
    );
  }
}

class _FilaBeneficio extends StatelessWidget {
  final IconData icono;
  final String texto;
  const _FilaBeneficio({required this.icono, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _kAzul.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icono, color: _kAzul, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PIE DE PAGINA LEGAL
// ─────────────────────────────────────────────────────────────────────────────

class _PiePagina extends StatelessWidget {
  const _PiePagina();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.grey.shade100,
      child: Text(
        'Contacto: +58-4241231561  |  RIF: J-305390042  |  Busemistas USM C.A.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
      ),
    );
  }
}
