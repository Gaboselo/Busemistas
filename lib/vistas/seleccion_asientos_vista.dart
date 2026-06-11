// lib/vistas/seleccion_asientos_vista.dart
// Busemistas USM v6
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios v6:
//   - Max 2 asientos por viaje para estudiantes (bloqueo visual + snackbar)
//   - Asiento ya reservado propio: clic deshabilitado con aviso
//   - "Plan Usemista" renombrado a "Plan Busemistas" en toda la UI
//   - notifyListeners() en AuthProvider tras cobro para sincronizar saldo

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

const Color _kAzul = Color(0xFF003380);

enum EstadoAsiento { libre, ocupado, seleccionado }

class SeleccionAsientosVista extends StatefulWidget {
  final String camionetaId;
  const SeleccionAsientosVista({super.key, required this.camionetaId});

  @override
  State<SeleccionAsientosVista> createState() => _SeleccionAsientosVistaState();
}

class _SeleccionAsientosVistaState extends State<SeleccionAsientosVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Multi-seleccion: Set de numeros de asiento
  final Set<int> _asientosSeleccionados = {};
  bool _procesando = false;
  bool _yaFueExpulsado = false;

  EstadoAsiento _estadoAsiento(int numero, Map<String, dynamic> asientos) {
    final key = '$numero';
    if (!asientos.containsKey(key)) return EstadoAsiento.libre;
    final data = asientos[key];
    if (data is Map && data['ocupado'] == true) return EstadoAsiento.ocupado;
    return EstadoAsiento.libre;
  }

  // ── Calcular costo segun plan y rol del usuario ──────────────────
  // Plan activo: 1er asiento gratis, adicionales al precio del rol
  // Sin plan   : todos al precio del rol (Tarifas.pasaje)
  // La tarifa NUNCA se hardcodea aqui — viene de Tarifas.pasaje(rol)
  double _calcularCosto(bool tienePlan, int cantidad, RolUsuario? rol) {
    if (cantidad == 0) return 0.0;
    final precioPorAsiento = Tarifas.pasaje(rol);
    if (tienePlan) {
      // El primer asiento es gratis (cubierto por el plan mensual)
      return (cantidad - 1) * precioPorAsiento;
    }
    return cantidad * precioPorAsiento;
  }

  bool _usuarioTieneAsiento(Map<String, dynamic> asientos, String cedula) {
    return asientos.values.any((v) =>
        v is Map && v['ocupado'] == true && v['cedula_pasajero'] == cedula);
  }

  // ── Deseleccionar asiento especifico (logica del Chip X) ─────────
  void _deseleccionar(int numero) {
    setState(() {
      _asientosSeleccionados.remove(numero);
    });
  }

  // ── Transaccion ACID multi-asiento ───────────────────────────────
  Future<void> _reservar(BuildContext context) async {
    if (_asientosSeleccionados.isEmpty) return;
    final auth = context.read<AuthProvider>();
    final cedula = auth.cedulaActual;
    if (cedula == null) return;

    final tienePlan = auth.mensualidadActiva;
    final cantidad = _asientosSeleccionados.length;
    final rol = auth.rolSeleccionado;
    final costo = _calcularCosto(tienePlan, cantidad, rol);
    final nombrePlan = Tarifas.nombrePlan(rol);
    final precioPorAsiento = Tarifas.pasaje(rol);

    // Aviso cuando tiene plan y selecciona mas de un asiento
    if (tienePlan && cantidad > 1) {
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.info_outline, color: _kAzul, size: 36),
          title: Text('$nombrePlan activo'),
          content: Text(
            'Tu asiento personal es gratis.\n'
            'Se cobraran ${cantidad - 1} asiento(s) adicional(es) a \$${precioPorAsiento.toStringAsFixed(2)} c/u.\n\n'
            'Total a cobrar: \$${costo.toStringAsFixed(2)}',
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kAzul),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    setState(() => _procesando = true);

    // 1. Declaramos una variable local para almacenar el costo real según el rol
    double costoRealCobrado = 0.0;

    try {
      final auth = context.read<AuthProvider>();

      await _db.runTransaction((tx) async {
        // Leer usuario
        final userRef = _db.collection('usuarios').doc(cedula);
        final userSnap = await tx.get(userRef);
        if (!userSnap.exists) throw Exception('Usuario no encontrado.');

        final userData = userSnap.data()!;
        final saldo = (userData['saldo'] as num?)?.toDouble() ?? 0.0;
        final mensualidadActiva =
            userData['mensualidad_activa'] as bool? ?? false;

        // 2. Validar fondos usando tarifa del rol real (leída desde Firestore)
        final rolStr = userData['rol'] as String? ?? '';
        final rolFirestore = RolUsuario.values.firstWhere(
          (r) => r.name == rolStr,
          orElse: () => RolUsuario.visitante,
        );
        final costoReal =
            _calcularCosto(mensualidadActiva, cantidad, rolFirestore);
        if (saldo < costoReal) {
          throw Exception('Saldo insuficiente (\$${saldo.toStringAsFixed(2)}). '
              'Necesitas \$${costoReal.toStringAsFixed(2)}.');
        }

        // 3. Leer camioneta
        final camRef = _db.collection('camionetas').doc(widget.camionetaId);
        final camSnap = await tx.get(camRef);
        if (!camSnap.exists) throw Exception('Camioneta no encontrada.');

        final camData = camSnap.data()!;
        final asientos = (camData['asientos'] as Map<String, dynamic>?) ?? {};

        // 4. Verificar que la unidad no arrancó
        final estadoUnidad = camData['estado'] as String? ?? 'disponible';
        if (estadoUnidad == 'en_camino') {
          throw Exception('__UNIDAD_EN_CAMINO__');
        }

        // 5. Colisión: todos los asientos seleccionados deben estar libres
        for (final n in _asientosSeleccionados) {
          final key = '$n';
          final asientoData = asientos[key];
          if (asientoData is Map && asientoData['ocupado'] == true) {
            throw Exception(
                'El asiento $n fue tomado en este momento. Selecciona otro.');
          }
        }

        // 6. Control de fraude: usuario ya tiene asiento + solo seleccionó 1
        final yaReservado = _usuarioTieneAsiento(asientos, cedula);
        if (yaReservado && cantidad == 1) {
          throw Exception(
              'Ya tienes un asiento reservado. Puedes agregar más asientos para acompañantes.');
        }

        // 7. Escrituras atómicas
        final Map<String, dynamic> updates = {};
        int idx = 0;
        for (final n in _asientosSeleccionados) {
          final key = 'asientos.$n';
          final esPrimero = idx == 0 && !yaReservado;
          updates['$key.ocupado'] = true;
          updates['$key.cedula_pasajero'] = cedula;
          updates['$key.nombre_pasajero'] = auth.nombreCompleto ?? '';
          updates['$key.estado_pago'] =
              (mensualidadActiva && esPrimero) ? 'mensualidad' : 'pagado';
          idx++;
        }
        tx.update(camRef, updates);

        // 8. Descontar saldo
        if (costoReal > 0) {
          tx.update(userRef, {'saldo': FieldValue.increment(-costoReal)});
        }

        // Guardamos el valor exacto procesado para usarlo fuera de la transacción
        costoRealCobrado = costoReal;
      });

      if (!context.mounted) return;

      // Actualización optimista inmediata en el Provider local sin desfases
      auth.actualizarSaldo(auth.saldo - costoRealCobrado);

      // Luego sincroniza con Firestore para confirmar el valor real
      await auth.refrescarDatosUsuario();
      await _mostrarBoleto(context);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      if (msg.contains('__UNIDAD_EN_CAMINO__')) {
        _manejarExpulsion(context);
        return;
      }
      _mostrarErrorSnack(context, msg);
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  } // Fin del método de confirmación de reserva

  void _manejarExpulsion(BuildContext context) {
    if (_yaFueExpulsado) return;
    _yaFueExpulsado = true;

    final ahora = DateTime.now();
    final siguiente = ahora.add(const Duration(minutes: 30));
    final h12 = siguiente.hour > 12
        ? siguiente.hour - 12
        : siguiente.hour == 0
            ? 12
            : siguiente.hour;
    final ampm = siguiente.hour < 12 ? 'AM' : 'PM';
    final horaStr =
        '${h12.toString().padLeft(2, '0')}:${siguiente.minute.toString().padLeft(2, '0')} $ampm';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.directions_bus_rounded,
            color: Colors.orange, size: 44),
        title: const Text('Ya arranco!'),
        content: Text(
          'Ya arranco, lo siento :(\n\nProxima en llegar: $horaStr',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kAzul),
            onPressed: () {
              Navigator.of(_).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Volver al inicio'),
          ),
        ],
      ),
    );
  }

  void _mostrarErrorSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
      ]),
      backgroundColor: Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _mostrarBoleto(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final rol = auth.rolSeleccionado;
    final costo = _calcularCosto(
        auth.mensualidadActiva, _asientosSeleccionados.length, rol);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoBoleto(
        nombre: auth.nombreCompleto ?? '',
        camionetaId: widget.camionetaId,
        asientos: _asientosSeleccionados.toList()..sort(),
        costoTotal: costo,
        usoPlan: auth.mensualidadActiva,
        nombrePlan: Tarifas.nombrePlan(rol),
        onCerrar: () {
          Navigator.of(_).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('Asientos - ${widget.camionetaId}'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: auth.mensualidadActiva
                      ? Colors.green.withValues(alpha: 0.25)
                      : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    auth.mensualidadActiva
                        ? Icons.card_membership
                        : Icons.account_balance_wallet_outlined,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    auth.mensualidadActiva
                        ? Tarifas.nombrePlan(auth.rolSeleccionado)
                        : '\$${auth.saldo.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream:
            _db.collection('camionetas').doc(widget.camionetaId).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.data!.exists) {
            return const Center(child: Text('Unidad no encontrada.'));
          }

          final data = snap.data!.data() as Map<String, dynamic>;
          final asientos = (data['asientos'] as Map<String, dynamic>?) ?? {};
          final estadoUnidad = data['estado'] as String? ?? 'disponible';

          // Expulsion automatica via stream
          if (estadoUnidad == 'en_camino' && !_yaFueExpulsado && !_procesando) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _manejarExpulsion(context);
            });
          }

          final tienePlan = auth.mensualidadActiva;
          final rolActual = auth.rolSeleccionado;
          final costoEstimado = _calcularCosto(
              tienePlan, _asientosSeleccionados.length, rolActual);
          final saldoSuficiente = tienePlan || auth.saldo >= costoEstimado;
          final yaTieneAsiento = auth.cedulaActual != null &&
              _usuarioTieneAsiento(asientos, auth.cedulaActual!);

          return Column(children: [
            // Banner cabina si esta en movimiento
            if (estadoUnidad == 'en_camino')
              _BannerCabinaAnimado(estadoUnidad: estadoUnidad),

            // Header de la unidad
            _HeaderCamioneta(
              camionetaId: widget.camionetaId,
              destino: data['destino'] as String? ?? 'Sin destino',
              modelo: data['modelo'] as String? ?? '',
              colorUnidad: data['color'] as String? ?? '',
              yaReservado: yaTieneAsiento,
            ),

            // Leyenda clara con 3 estados
            const _LeyendaAsientos(),

            // Mapa de asientos
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: _MapaCamionetaV4(
                  asientos: asientos,
                  asientosSeleccionados: _asientosSeleccionados,
                  estadoAsientoFn: _estadoAsiento,
                  cedulaActual: auth.cedulaActual ?? '',
                  onToggleAsiento: (n) {
                    // Bloqueo 1: asiento ya reservado por el propio usuario
                    final dataAsiento = asientos['$n'];
                    if (dataAsiento is Map &&
                        dataAsiento['ocupado'] == true &&
                        dataAsiento['cedula_pasajero'] == auth.cedulaActual) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Este asiento ya fue reservado por ti.'),
                          backgroundColor: Colors.purple,
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 3),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      if (_asientosSeleccionados.contains(n)) {
                        _asientosSeleccionados.remove(n);
                      } else {
                        // Bloqueo 2: max 2 asientos por viaje para estudiantes/empleados
                        // CORRECTO: todos tienen máximo 2 asientos
// Lo que cambia para visitante NO es el límite de asientos,
// sino que no puede contratar el Plan Busemistas.
                        const maxAsientos = 2;
                        if (_asientosSeleccionados.length >= maxAsientos) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Máximo $maxAsientos asientos por viaje.'),
                              backgroundColor: Colors.orange.shade700,
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          return;
                        }
                        _asientosSeleccionados.add(n);
                      }
                    });
                  },
                ),
              ),
            ),

            // Panel de confirmacion con chips funcionales
            _PanelConfirmacionMulti(
              asientosSeleccionados: _asientosSeleccionados,
              mensualidadActiva: tienePlan,
              costoTotal: costoEstimado,
              saldo: auth.saldo,
              procesando: _procesando,
              saldoSuficiente: saldoSuficiente,
              onReservar: () => _reservar(context),
              // Callback de deseleccion funcional
              onDeseleccionar: _deseleccionar,
              tarifaAdicional: Tarifas.pasaje(rolActual),
              nombrePlan: Tarifas.nombrePlan(rolActual),
            ),
          ]);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MAPA DE CAMIONETA V4
// Conductor IZQUIERDA, Puerta delantera DERECHA
// ─────────────────────────────────────────────────────────────────────────────

class _MapaCamionetaV4 extends StatelessWidget {
  final Map<String, dynamic> asientos;
  final Set<int> asientosSeleccionados;
  final EstadoAsiento Function(int, Map<String, dynamic>) estadoAsientoFn;
  final String cedulaActual;
  final void Function(int) onToggleAsiento;

  const _MapaCamionetaV4({
    required this.asientos,
    required this.asientosSeleccionados,
    required this.estadoAsientoFn,
    required this.cedulaActual,
    required this.onToggleAsiento,
  });

  bool _esMiAsiento(int numero) {
    final data = asientos['$numero'];
    if (data is Map) {
      return data['ocupado'] == true && data['cedula_pasajero'] == cedulaActual;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300, width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        // Fila cabecera: CONDUCTOR IZQUIERDA, PUERTA DELANTERA DERECHA
        Row(children: [
          _AsientoConductor(),
          const Spacer(),
          _CeldaPuerta(label: 'Puerta delantera', color: Colors.blue.shade100),
        ]),
        const SizedBox(height: 10),

        // Filas 1-5: asientos 1-20
        ...List.generate(5, (filaIdx) {
          final base = filaIdx * 4;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _AsientoWidget(
                  numero: base + 1,
                  estado: estadoAsientoFn(base + 1, asientos),
                  seleccionado: asientosSeleccionados.contains(base + 1),
                  esMio: _esMiAsiento(base + 1),
                  onTap: () => onToggleAsiento(base + 1),
                ),
                _AsientoWidget(
                  numero: base + 2,
                  estado: estadoAsientoFn(base + 2, asientos),
                  seleccionado: asientosSeleccionados.contains(base + 2),
                  esMio: _esMiAsiento(base + 2),
                  onTap: () => onToggleAsiento(base + 2),
                ),
                const SizedBox(width: 20), // Pasillo
                _AsientoWidget(
                  numero: base + 3,
                  estado: estadoAsientoFn(base + 3, asientos),
                  seleccionado: asientosSeleccionados.contains(base + 3),
                  esMio: _esMiAsiento(base + 3),
                  onTap: () => onToggleAsiento(base + 3),
                ),
                _AsientoWidget(
                  numero: base + 4,
                  estado: estadoAsientoFn(base + 4, asientos),
                  seleccionado: asientosSeleccionados.contains(base + 4),
                  esMio: _esMiAsiento(base + 4),
                  onTap: () => onToggleAsiento(base + 4),
                ),
              ],
            ),
          );
        }),

        // Ultima fila: asientos 21-22 + Puerta trasera
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AsientoWidget(
                numero: 21,
                estado: estadoAsientoFn(21, asientos),
                seleccionado: asientosSeleccionados.contains(21),
                esMio: _esMiAsiento(21),
                onTap: () => onToggleAsiento(21),
              ),
              _AsientoWidget(
                numero: 22,
                estado: estadoAsientoFn(22, asientos),
                seleccionado: asientosSeleccionados.contains(22),
                esMio: _esMiAsiento(22),
                onTap: () => onToggleAsiento(22),
              ),
              const SizedBox(width: 20),
              _CeldaPuerta(
                  label: 'Puerta trasera', color: Colors.green.shade100),
            ],
          ),
        ),
      ]),
    );
  }
}

class _AsientoWidget extends StatelessWidget {
  final int numero;
  final EstadoAsiento estado;
  final bool seleccionado;
  final bool esMio;
  final VoidCallback onTap;

  const _AsientoWidget({
    required this.numero,
    required this.estado,
    required this.seleccionado,
    required this.esMio,
    required this.onTap,
  });

  Color get _bg {
    if (esMio) return Colors.purple.shade200;
    if (seleccionado) return _kAzul;
    return estado == EstadoAsiento.ocupado
        ? Colors.red.shade100
        : Colors.green.shade100;
  }

  Color get _border {
    if (esMio) return Colors.purple.shade400;
    if (seleccionado) return _kAzul;
    return estado == EstadoAsiento.ocupado
        ? Colors.red.shade400
        : Colors.green.shade400;
  }

  Color get _fg {
    if (esMio) return Colors.purple.shade800;
    if (seleccionado) return Colors.white;
    return estado == EstadoAsiento.ocupado
        ? Colors.red.shade700
        : Colors.green.shade800;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: estado == EstadoAsiento.ocupado && !esMio ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border, width: 1.5),
          boxShadow: seleccionado
              ? [BoxShadow(color: _kAzul.withValues(alpha: 0.4), blurRadius: 6)]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              esMio
                  ? Icons.person_pin_rounded
                  : estado == EstadoAsiento.ocupado
                      ? Icons.person_rounded
                      : Icons.event_seat_rounded,
              size: 20,
              color: _fg,
            ),
            Text('$numero',
                style: TextStyle(
                    fontSize: 10, color: _fg, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

class _AsientoConductor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: _kAzul,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(color: _kAzul.withValues(alpha: 0.5), blurRadius: 8)
        ],
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.settings_input_svideo_rounded,
              color: Colors.white, size: 22),
          Text('Chofer',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _CeldaPuerta extends StatelessWidget {
  final String label;
  final Color color;
  const _CeldaPuerta({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200.withValues(alpha: 0.5)),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEYENDA (3 estados)
// ─────────────────────────────────────────────────────────────────────────────

class _LeyendaAsientos extends StatelessWidget {
  const _LeyendaAsientos();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ItemLeyenda(
              colorFondo: Colors.green.shade100,
              colorBorde: Colors.green.shade400,
              texto: 'Libre',
              icono: Icons.event_seat_rounded,
              colorIcono: Colors.green.shade700),
          const SizedBox(width: 14),
          _ItemLeyenda(
              colorFondo: Colors.red.shade100,
              colorBorde: Colors.red.shade400,
              texto: 'Ocupado',
              icono: Icons.person_rounded,
              colorIcono: Colors.red.shade700),
          const SizedBox(width: 14),
          const _ItemLeyenda(
              colorFondo: _kAzul,
              colorBorde: _kAzul,
              texto: 'Seleccionado',
              icono: Icons.event_seat_rounded,
              colorIcono: Colors.white),
        ],
      ),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  final Color colorFondo;
  final Color colorBorde;
  final String texto;
  final IconData icono;
  final Color colorIcono;

  const _ItemLeyenda({
    required this.colorFondo,
    required this.colorBorde,
    required this.texto,
    required this.icono,
    required this.colorIcono,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colorFondo,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: colorBorde),
        ),
        child: Icon(icono, size: 14, color: colorIcono),
      ),
      const SizedBox(width: 5),
      Text(texto, style: const TextStyle(fontSize: 11)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER CAMIONETA
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCamioneta extends StatelessWidget {
  final String camionetaId;
  final String destino;
  final String modelo;
  final String colorUnidad;
  final bool yaReservado;

  const _HeaderCamioneta({
    required this.camionetaId,
    required this.destino,
    required this.modelo,
    required this.colorUnidad,
    required this.yaReservado,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFEEEAF8),
      child: Row(children: [
        const Icon(Icons.airport_shuttle_outlined, color: _kAzul),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$modelo - $camionetaId',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: _kAzul)),
              Text('$destino  |  Color: $colorUnidad',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        if (yaReservado)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.shade300),
            ),
            child: const Text('Asiento reservado',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.purple,
                    fontWeight: FontWeight.bold)),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANEL DE CONFIRMACION MULTI - con onDeleted funcional
// ─────────────────────────────────────────────────────────────────────────────

class _PanelConfirmacionMulti extends StatelessWidget {
  final Set<int> asientosSeleccionados;
  final bool mensualidadActiva;
  final double costoTotal;
  final double saldo;
  final bool procesando;
  final bool saldoSuficiente;
  final VoidCallback onReservar;
  // Callback que recibe el numero de asiento a deseleccionar
  final void Function(int) onDeseleccionar;
  // Tarifa por asiento adicional (viene de Tarifas.pasaje)
  final double tarifaAdicional;
  // Nombre del plan activo del usuario (viene de Tarifas.nombrePlan)
  final String nombrePlan;

  const _PanelConfirmacionMulti({
    required this.asientosSeleccionados,
    required this.mensualidadActiva,
    required this.costoTotal,
    required this.saldo,
    required this.procesando,
    required this.saldoSuficiente,
    required this.onReservar,
    required this.onDeseleccionar,
    required this.tarifaAdicional,
    required this.nombrePlan,
  });

  String get _textoBoton {
    if (procesando) return 'Procesando...';
    if (asientosSeleccionados.isEmpty) return 'Selecciona asiento(s)';
    if (mensualidadActiva && costoTotal == 0) {
      return 'Reservar ${asientosSeleccionados.length} asiento(s) - $nombrePlan';
    }
    return 'Reservar ${asientosSeleccionados.length} asiento(s) - \$${costoTotal.toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    final listaOrdenada = asientosSeleccionados.toList()..sort();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, -2))
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (asientosSeleccionados.isNotEmpty) ...[
          // Chips con onDeleted FUNCIONAL: remueve el asiento del Set
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: listaOrdenada.map((n) {
              return Chip(
                label: Text('Asiento $n',
                    style: const TextStyle(fontSize: 11, color: _kAzul)),
                backgroundColor: const Color(0xFFEEEAF8),
                side: const BorderSide(color: _kAzul),
                padding: EdgeInsets.zero,
                deleteIcon: const Icon(Icons.close, size: 14, color: _kAzul),
                // onDeleted funcional: llama al callback con el numero
                onDeleted: () => onDeseleccionar(n),
              );
            }).toList(),
          ),
          if (mensualidadActiva)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                asientosSeleccionados.length > 1
                    ? '$nombrePlan: 1 gratis + ${asientosSeleccionados.length - 1} adicional(es) a \$${tarifaAdicional.toStringAsFixed(2)}'
                    : '$nombrePlan: asiento gratis',
                style: TextStyle(
                    color: Colors.green.shade700,
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
        ],
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: (asientosSeleccionados.isEmpty ||
                    procesando ||
                    !saldoSuficiente)
                ? null
                : onReservar,
            icon: procesando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.confirmation_number_outlined),
            label: Text(_textoBoton, style: const TextStyle(fontSize: 15)),
            style: FilledButton.styleFrom(
              backgroundColor: _kAzul,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BANNER CABINA ANIMADO
// ─────────────────────────────────────────────────────────────────────────────

class _BannerCabinaAnimado extends StatefulWidget {
  final String estadoUnidad;
  const _BannerCabinaAnimado({required this.estadoUnidad});

  @override
  State<_BannerCabinaAnimado> createState() => _BannerCabinaAnimadoState();
}

class _BannerCabinaAnimadoState extends State<_BannerCabinaAnimado>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.85, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF003380), Color(0xFF3A0CA3)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: const Row(children: [
            Icon(Icons.directions_bus_rounded, color: Colors.white70, size: 20),
            SizedBox(width: 10),
            Text(
              'Puertas Aseguradas / Iniciando Viaje',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOLETO DIGITAL MULTI-ASIENTO
// ─────────────────────────────────────────────────────────────────────────────

class _DialogoBoleto extends StatelessWidget {
  final String nombre;
  final String camionetaId;
  final List<int> asientos;
  final double costoTotal;
  final bool usoPlan;
  // Nombre dinamico del plan: "Plan Usemista" o "Plan Empleado"
  final String nombrePlan;
  final VoidCallback onCerrar;

  const _DialogoBoleto({
    required this.nombre,
    required this.camionetaId,
    required this.asientos,
    required this.costoTotal,
    required this.usoPlan,
    required this.nombrePlan,
    required this.onCerrar,
  });

  @override
  Widget build(BuildContext context) {
    final ahora = DateTime.now();
    final h12 = ahora.hour > 12
        ? ahora.hour - 12
        : ahora.hour == 0
            ? 12
            : ahora.hour;
    final ampm = ahora.hour < 12 ? 'AM' : 'PM';
    final horaStr =
        '${h12.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')} $ampm';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.green.shade50,
            child: Icon(Icons.check_circle_rounded,
                color: Colors.green.shade600, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Reserva Confirmada!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEEEAF8),
              borderRadius: BorderRadius.circular(12),
              border:
                  Border.all(color: _kAzul.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(children: [
              _FilaBoleto(
                  icono: Icons.person_outline,
                  label: 'Pasajero',
                  valor: nombre),
              const Divider(height: 16),
              _FilaBoleto(
                  icono: Icons.airport_shuttle_outlined,
                  label: 'Unidad',
                  valor: camionetaId),
              const Divider(height: 16),
              _FilaBoleto(
                  icono: Icons.event_seat_outlined,
                  label: 'Asiento(s)',
                  valor: asientos.join(', ')),
              const Divider(height: 16),
              _FilaBoleto(icono: Icons.schedule, label: 'Hora', valor: horaStr),
              const Divider(height: 16),
              _FilaBoleto(
                  icono: Icons.attach_money,
                  label: 'Total',
                  valor: usoPlan && costoTotal == 0
                      ? nombrePlan
                      : '\$${costoTotal.toStringAsFixed(2)}'),
            ]),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCerrar,
              icon: const Icon(Icons.home_outlined),
              label: const Text('Volver al Inicio'),
              style: FilledButton.styleFrom(
                backgroundColor: _kAzul,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _FilaBoleto extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  const _FilaBoleto(
      {required this.icono, required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icono, size: 16, color: _kAzul),
      const SizedBox(width: 8),
      Text('$label: ',
          style: const TextStyle(fontSize: 13, color: Colors.grey)),
      Expanded(
          child: Text(valor,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right)),
    ]);
  }
}
