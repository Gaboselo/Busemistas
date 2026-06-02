// lib/vistas/seleccion_asientos_vista.dart
// Parte 4: Selección de asientos, reserva y pago ($1)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ESTADOS POSIBLES DE UN ASIENTO
// ─────────────────────────────────────────────────────────────────────────────

enum EstadoAsiento { libre, ocupado, seleccionado }

// ─────────────────────────────────────────────────────────────────────────────
// VISTA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class SeleccionAsientosVista extends StatefulWidget {
  final String camionetaId;
  const SeleccionAsientosVista({super.key, required this.camionetaId});

  @override
  State<SeleccionAsientosVista> createState() => _SeleccionAsientosVistaState();
}

class _SeleccionAsientosVistaState extends State<SeleccionAsientosVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  int? _asientoSeleccionado; // número de 1 a 24, null = ninguno
  bool _procesando = false;

  // ── Calcular estado de cada asiento desde Firestore ──────────────
  EstadoAsiento _estadoAsiento(int numero, Map<String, dynamic> asientos) {
    final key = '$numero';
    if (!asientos.containsKey(key)) return EstadoAsiento.libre;
    final data = asientos[key];
    if (data is Map && data['ocupado'] == true) return EstadoAsiento.ocupado;
    return EstadoAsiento.libre;
  }

  // ── Reservar asiento ─────────────────────────────────────────────
  Future<void> _reservar(BuildContext context) async {
    if (_asientoSeleccionado == null) return;

    final auth = context.read<AuthProvider>();
    final cedula = auth.cedulaActual;
    if (cedula == null) return;

    setState(() => _procesando = true);

    try {
      // Leer saldo actual del usuario
      final userDoc = await _db.collection('usuarios').doc(cedula).get();
      if (!userDoc.exists) throw Exception('Usuario no encontrado.');

      final saldoActual = (userDoc.data()?['saldo'] as num?)?.toDouble() ?? 0;
      if (saldoActual < 1) {
        throw Exception(
          'Saldo insuficiente. Tu saldo actual es \$$saldoActual.',
        );
      }

      // Verificar que el asiento siga libre antes de escribir
      final camDoc =
          await _db.collection('camionetas').doc(widget.camionetaId).get();
      if (!camDoc.exists) throw Exception('Camioneta no encontrada.');

      final asientos =
          (camDoc.data()?['asientos'] as Map<String, dynamic>?) ?? {};
      final key = '${_asientoSeleccionado!}';
      final asientoData = asientos[key];
      if (asientoData is Map && asientoData['ocupado'] == true) {
        throw Exception(
          'El asiento $_asientoSeleccionado acaba de ser ocupado. Elige otro.',
        );
      }

      // ── Transacción atómica ──────────────────────────────────────
      await _db.runTransaction((tx) async {
        final userRef = _db.collection('usuarios').doc(cedula);
        final camRef = _db.collection('camionetas').doc(widget.camionetaId);

        tx.update(userRef, {'saldo': FieldValue.increment(-1)});
        tx.update(camRef, {
          'asientos.$key.ocupado': true,
          'asientos.$key.cedula_pasajero': cedula,
        });
      });

      if (!context.mounted) return;

      // ── Mostrar boleto digital ───────────────────────────────────
      await _mostrarBoleto(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${e.toString().replaceAll('Exception: ', '')}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  // ── Boleto digital en diálogo ────────────────────────────────────
  Future<void> _mostrarBoleto(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DialogoBoleto(
        nombre: auth.nombreCompleto ?? '',
        camionetaId: widget.camionetaId,
        numeroAsiento: _asientoSeleccionado!,
        onCerrar: () {
          Navigator.of(_).pop(); // cierra diálogo
          Navigator.of(context).pop(); // regresa al home
        },
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asientos — ${widget.camionetaId}'),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream:
            _db.collection('camionetas').doc(widget.camionetaId).snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snap.hasError || !snap.hasData || !snap.data!.exists) {
            return const Center(child: Text('No se pudo cargar la camioneta.'));
          }

          final data = snap.data!.data() as Map<String, dynamic>;
          final asientos = (data['asientos'] as Map<String, dynamic>?) ?? {};
          final destino = data['destino'] as String? ?? '';

          // Si el asiento que el usuario tenía seleccionado se ocupa
          // mientras está mirando, lo deseleccionamos automáticamente.
          if (_asientoSeleccionado != null) {
            final key = '$_asientoSeleccionado';
            final aData = asientos[key];
            if (aData is Map && aData['ocupado'] == true) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) setState(() => _asientoSeleccionado = null);
              });
            }
          }

          return Column(
            children: [
              // ── Info camioneta ──────────────────────────────────
              _HeaderCamioneta(
                camionetaId: widget.camionetaId,
                destino: destino,
              ),

              // ── Leyenda de colores ──────────────────────────────
              const _LeyendaAsientos(),

              // ── Cabina del conductor ────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 4,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.drive_eta, size: 18, color: Colors.grey),
                    const SizedBox(width: 6),
                    Text(
                      'Conductor',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '← Frente del vehículo',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Cuadrícula de asientos ──────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CuadriculaAsientos(
                    asientos: asientos,
                    asientoSeleccionado: _asientoSeleccionado,
                    estadoAsiento: (n) => _estadoAsiento(n, asientos),
                    onTap: (n) {
                      final estado = _estadoAsiento(n, asientos);
                      if (estado == EstadoAsiento.ocupado) return;
                      setState(() {
                        _asientoSeleccionado =
                            _asientoSeleccionado == n ? null : n;
                      });
                    },
                  ),
                ),
              ),

              // ── Botón reservar ──────────────────────────────────
              _BarraReserva(
                asientoSeleccionado: _asientoSeleccionado,
                procesando: _procesando,
                onReservar: () => _reservar(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER INFO CAMIONETA
// ─────────────────────────────────────────────────────────────────────────────

class _HeaderCamioneta extends StatelessWidget {
  final String camionetaId;
  final String destino;
  const _HeaderCamioneta({required this.camionetaId, required this.destino});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: colors.primaryContainer,
      child: Row(
        children: [
          Icon(Icons.airport_shuttle_outlined, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  camionetaId,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  destino,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LEYENDA DE ASIENTOS
// ─────────────────────────────────────────────────────────────────────────────

class _LeyendaAsientos extends StatelessWidget {
  const _LeyendaAsientos();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ItemLeyenda(color: Colors.green.shade400, texto: 'Libre'),
          const SizedBox(width: 16),
          _ItemLeyenda(color: Colors.red.shade400, texto: 'Ocupado'),
          const SizedBox(width: 16),
          _ItemLeyenda(color: Colors.blue.shade400, texto: 'Seleccionado'),
        ],
      ),
    );
  }
}

class _ItemLeyenda extends StatelessWidget {
  final Color color;
  final String texto;
  const _ItemLeyenda({required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 5),
        Text(texto, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CUADRÍCULA DE ASIENTOS
// Distribución: 6 filas × 4 columnas con pasillo central (col 1|2 _ col 3|4)
// Asientos del 1 al 24 numerados fila por fila de izquierda a derecha
// ─────────────────────────────────────────────────────────────────────────────

class _CuadriculaAsientos extends StatelessWidget {
  final Map<String, dynamic> asientos;
  final int? asientoSeleccionado;
  final EstadoAsiento Function(int) estadoAsiento;
  final void Function(int) onTap;

  const _CuadriculaAsientos({
    required this.asientos,
    required this.asientoSeleccionado,
    required this.estadoAsiento,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 6 filas, cada fila: [asientoA, asientoB, PASILLO, asientoC, asientoD]
    // Numeración: fila 1 → 1,2,3,4 | fila 2 → 5,6,7,8 ... fila 6 → 21,22,23,24
    return ListView.builder(
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, filaIdx) {
        final base = filaIdx * 4; // primer asiento de la fila (0-based)
        final numeros = [base + 1, base + 2, base + 3, base + 4];

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              // Etiqueta de fila
              SizedBox(
                width: 24,
                child: Text(
                  '${filaIdx + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ),
              const SizedBox(width: 4),
              // Asiento izquierdo A
              Expanded(
                child: _Asiento(
                  numero: numeros[0],
                  estado: asientoSeleccionado == numeros[0]
                      ? EstadoAsiento.seleccionado
                      : estadoAsiento(numeros[0]),
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 4),
              // Asiento izquierdo B
              Expanded(
                child: _Asiento(
                  numero: numeros[1],
                  estado: asientoSeleccionado == numeros[1]
                      ? EstadoAsiento.seleccionado
                      : estadoAsiento(numeros[1]),
                  onTap: onTap,
                ),
              ),
              // Pasillo
              const SizedBox(width: 24),
              // Asiento derecho C
              Expanded(
                child: _Asiento(
                  numero: numeros[2],
                  estado: asientoSeleccionado == numeros[2]
                      ? EstadoAsiento.seleccionado
                      : estadoAsiento(numeros[2]),
                  onTap: onTap,
                ),
              ),
              const SizedBox(width: 4),
              // Asiento derecho D
              Expanded(
                child: _Asiento(
                  numero: numeros[3],
                  estado: asientoSeleccionado == numeros[3]
                      ? EstadoAsiento.seleccionado
                      : estadoAsiento(numeros[3]),
                  onTap: onTap,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET INDIVIDUAL DE ASIENTO
// ─────────────────────────────────────────────────────────────────────────────

class _Asiento extends StatelessWidget {
  final int numero;
  final EstadoAsiento estado;
  final void Function(int) onTap;

  const _Asiento({
    required this.numero,
    required this.estado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (bgColor, borderColor, textColor, icono) = switch (estado) {
      EstadoAsiento.libre => (
          Colors.green.shade50,
          Colors.green.shade400,
          Colors.green.shade700,
          Icons.event_seat_outlined,
        ),
      EstadoAsiento.ocupado => (
          Colors.red.shade50,
          Colors.red.shade300,
          Colors.red.shade400,
          Icons.event_seat,
        ),
      EstadoAsiento.seleccionado => (
          Colors.blue.shade100,
          Colors.blue.shade600,
          Colors.blue.shade800,
          Icons.event_seat,
        ),
    };

    return GestureDetector(
      onTap: estado == EstadoAsiento.ocupado ? null : () => onTap(numero),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: estado == EstadoAsiento.seleccionado
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 22, color: textColor),
            const SizedBox(height: 2),
            Text(
              '$numero',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARRA INFERIOR DE RESERVA
// ─────────────────────────────────────────────────────────────────────────────

class _BarraReserva extends StatelessWidget {
  final int? asientoSeleccionado;
  final bool procesando;
  final VoidCallback onReservar;

  const _BarraReserva({
    required this.asientoSeleccionado,
    required this.procesando,
    required this.onReservar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (asientoSeleccionado != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.event_seat, color: colors.primary, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Asiento $asientoSeleccionado seleccionado',
                    style: TextStyle(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (asientoSeleccionado == null || procesando)
                  ? null
                  : onReservar,
              icon: procesando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.confirmation_number_outlined),
              label: Text(
                procesando
                    ? 'Procesando...'
                    : asientoSeleccionado == null
                        ? 'Selecciona un asiento'
                        : 'Reservar Asiento por \$1',
                style: const TextStyle(fontSize: 16),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGO BOLETO DIGITAL
// ─────────────────────────────────────────────────────────────────────────────

class _DialogoBoleto extends StatelessWidget {
  final String nombre;
  final String camionetaId;
  final int numeroAsiento;
  final VoidCallback onCerrar;

  const _DialogoBoleto({
    required this.nombre,
    required this.camionetaId,
    required this.numeroAsiento,
    required this.onCerrar,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ahora = DateTime.now();
    final horaStr =
        '${ahora.hour.toString().padLeft(2, '0')}:${ahora.minute.toString().padLeft(2, '0')}';
    final fechaStr =
        '${ahora.day.toString().padLeft(2, '0')}/${ahora.month.toString().padLeft(2, '0')}/${ahora.year}';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ícono de éxito
            CircleAvatar(
              radius: 32,
              backgroundColor: Colors.green.shade50,
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.green.shade600,
                size: 40,
              ),
            ),
            const SizedBox(height: 16),

            Text(
              '¡Reserva Confirmada!',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
            ),
            const SizedBox(height: 20),

            // Tarjeta boleto
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.primary.withOpacity(0.3),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  _FilaBoleto(
                    icono: Icons.person_outline,
                    label: 'Pasajero',
                    valor: nombre,
                  ),
                  const Divider(height: 16),
                  _FilaBoleto(
                    icono: Icons.airport_shuttle_outlined,
                    label: 'Unidad',
                    valor: camionetaId,
                  ),
                  const Divider(height: 16),
                  _FilaBoleto(
                    icono: Icons.event_seat_outlined,
                    label: 'Asiento',
                    valor: '$numeroAsiento',
                  ),
                  const Divider(height: 16),
                  _FilaBoleto(
                    icono: Icons.schedule,
                    label: 'Hora',
                    valor: '$horaStr · $fechaStr',
                  ),
                  const Divider(height: 16),
                  _FilaBoleto(
                    icono: Icons.attach_money,
                    label: 'Pagado',
                    valor: '\$1',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCerrar,
                icon: const Icon(Icons.home_outlined),
                label: const Text('Volver al Inicio'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilaBoleto extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  const _FilaBoleto({
    required this.icono,
    required this.label,
    required this.valor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icono, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 13, color: Colors.grey),
        ),
        Expanded(
          child: Text(
            valor,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
