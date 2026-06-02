// lib/vistas/conductor_home_vista.dart
// Parte 5: Pantalla principal del conductor

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RUTA SIMULADA: coordenadas reales Caracas
// La California → Petare → Av. Rómulo Gallegos → Entrada USM
// ─────────────────────────────────────────────────────────────────────────────
const List<GeoPoint> _rutaSimulada = [
  GeoPoint(10.4900, -66.8450), // La California Norte
  GeoPoint(10.4850, -66.8280), // Av. Francisco de Miranda (entre)
  GeoPoint(10.4780, -66.8100), // Petare - Entrada
  GeoPoint(10.4720, -66.7980), // Av. Rómulo Gallegos
  GeoPoint(10.4680, -66.7850), // Entrada USM Caracas
];

// ─────────────────────────────────────────────────────────────────────────────
// VISTA PRINCIPAL
// ─────────────────────────────────────────────────────────────────────────────

class ConductorHomeVista extends StatefulWidget {
  const ConductorHomeVista({super.key});

  @override
  State<ConductorHomeVista> createState() => _ConductorHomeVistaState();
}

class _ConductorHomeVistaState extends State<ConductorHomeVista> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _rutaActiva = false;
  bool _simulando = false;
  int _pasoSimulacion = 0;
  Timer? _timerSimulacion;

  // El ID de camioneta viene del campo `camioneta_asignada` del conductor
  // en `lista_oficial_conductores`. Si no está, fallback a 'camioneta_01'.
  String get _camionetaId {
    final auth = context.read<AuthProvider>();
    return auth.camionetaAsignada ?? 'camioneta_01';
  }

  @override
  void dispose() {
    _timerSimulacion?.cancel();
    super.dispose();
  }

  // ── Activar / desactivar ruta ────────────────────────────────────
  Future<void> _toggleRuta(bool valor) async {
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'activa': valor,
        'estado': valor ? 'en_camino' : 'disponible',
      });
      setState(() {
        _rutaActiva = valor;
        // Detener simulación si se apaga la ruta
        if (!valor) _detenerSimulacion();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cambiar estado de ruta: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  // ── Iniciar simulación GPS ───────────────────────────────────────
  void _iniciarSimulacion() {
    if (_simulando) {
      _detenerSimulacion();
      return;
    }

    setState(() {
      _simulando = true;
      _pasoSimulacion = 0;
    });

    // Escribir primer punto inmediatamente
    _escribirUbicacion(_pasoSimulacion);

    _timerSimulacion = Timer.periodic(const Duration(seconds: 3), (timer) {
      _pasoSimulacion++;

      if (_pasoSimulacion >= _rutaSimulada.length) {
        // Llegó al destino — reiniciar desde el principio (loop)
        _pasoSimulacion = 0;
      }

      _escribirUbicacion(_pasoSimulacion);
    });
  }

  Future<void> _escribirUbicacion(int paso) async {
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'ubicacion': _rutaSimulada[paso],
      });
    } catch (e) {
      debugPrint('Error simulación GPS: $e');
    }
  }

  void _detenerSimulacion() {
    _timerSimulacion?.cancel();
    _timerSimulacion = null;
    setState(() {
      _simulando = false;
      _pasoSimulacion = 0;
    });
  }

  // ── Cerrar sesión ────────────────────────────────────────────────
  Future<void> _cerrarSesion(BuildContext context) async {
    _detenerSimulacion();
    // Desactivar ruta al salir
    try {
      await _db.collection('camionetas').doc(_camionetaId).update({
        'activa': false,
        'estado': 'disponible',
      });
    } catch (_) {}
    if (!context.mounted) return;
    context.read<AuthProvider>().cerrarSesion();
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Build ────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final colors = Theme.of(context).colorScheme;
    final nombre = auth.nombreCompleto ?? 'Conductor';
    final camId = auth.camionetaAsignada ?? 'camioneta_01';

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ── Encabezado ─────────────────────────────────────────
            _EncabezadoConductor(
              nombre: nombre,
              camionetaId: camId,
              onCerrarSesion: () => _cerrarSesion(context),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Estado de ruta ──────────────────────────────
                    _TarjetaEstadoRuta(
                      rutaActiva: _rutaActiva,
                      onToggle: _toggleRuta,
                    ),
                    const SizedBox(height: 16),

                    // ── Simulador GPS ───────────────────────────────
                    _TarjetaSimulador(
                      rutaActiva: _rutaActiva,
                      simulando: _simulando,
                      pasoActual: _pasoSimulacion,
                      totalPasos: _rutaSimulada.length,
                      onIniciar: _iniciarSimulacion,
                    ),
                    const SizedBox(height: 16),

                    // ── Contador asientos (stream) ──────────────────
                    _TarjetaAsientosStream(camionetaId: camId),
                    const SizedBox(height: 16),

                    // ── Lista de paradas de la ruta ─────────────────
                    const _TarjetaParadas(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ENCABEZADO
// ─────────────────────────────────────────────────────────────────────────────

class _EncabezadoConductor extends StatelessWidget {
  final String nombre;
  final String camionetaId;
  final VoidCallback onCerrarSesion;

  const _EncabezadoConductor({
    required this.nombre,
    required this.camionetaId,
    required this.onCerrarSesion,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        boxShadow: [
          BoxShadow(
              color: colors.shadow.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colors.primary,
            child: const Icon(Icons.drive_eta, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nombre,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  camionetaId,
                  style: TextStyle(
                      fontSize: 12,
                      color: colors.primary,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onCerrarSesion,
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Cerrar sesión',
            style: IconButton.styleFrom(foregroundColor: colors.error),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA: ESTADO DE RUTA
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaEstadoRuta extends StatelessWidget {
  final bool rutaActiva;
  final void Function(bool) onToggle;

  const _TarjetaEstadoRuta({
    required this.rutaActiva,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = rutaActiva ? Colors.green : colors.outline;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.route_outlined, color: color),
                const SizedBox(width: 8),
                Text('Estado de la Ruta',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                // Indicador visual grande
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: rutaActiva
                        ? [
                            BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 8)
                          ]
                        : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rutaActiva
                        ? 'Ruta activa — visible para estudiantes'
                        : 'Ruta inactiva — no visible en el mapa',
                    style: TextStyle(
                      color: rutaActiva
                          ? Colors.green.shade700
                          : colors.onSurface.withOpacity(0.5),
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                Switch.adaptive(
                  value: rutaActiva,
                  onChanged: onToggle,
                  activeColor: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA: SIMULADOR GPS
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaSimulador extends StatelessWidget {
  final bool rutaActiva;
  final bool simulando;
  final int pasoActual;
  final int totalPasos;
  final VoidCallback onIniciar;

  const _TarjetaSimulador({
    required this.rutaActiva,
    required this.simulando,
    required this.pasoActual,
    required this.totalPasos,
    required this.onIniciar,
  });

  static const _etiquetasPasos = [
    'La California Norte',
    'Av. Francisco de Miranda',
    'Petare — Entrada',
    'Av. Rómulo Gallegos',
    'Entrada USM Caracas',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.navigation_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Text('Simulador GPS',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (simulando)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.orange.shade600),
                        ),
                        const SizedBox(width: 5),
                        Text('EN VIVO',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange.shade700)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Actualiza el GeoPoint en Firestore cada 3 segundos para que el mapa del estudiante muestre el movimiento.',
              style: TextStyle(
                  fontSize: 12, color: colors.onSurface.withOpacity(0.55)),
            ),

            // Progreso de pasos cuando está simulando
            if (simulando) ...[
              const SizedBox(height: 16),
              _BarraProgreso(
                  pasoActual: pasoActual,
                  totalPasos: totalPasos,
                  etiquetas: _etiquetasPasos),
            ],

            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: simulando
                  ? OutlinedButton.icon(
                      onPressed: onIniciar,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Detener Simulación'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: colors.error,
                        side: BorderSide(color: colors.error),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: rutaActiva ? onIniciar : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Simular Recorrido (Ruta USM)'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: Colors.orange.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
            ),

            if (!rutaActiva && !simulando)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '⚠ Activa la ruta primero para simular.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: colors.onSurface.withOpacity(0.45)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarraProgreso extends StatelessWidget {
  final int pasoActual;
  final int totalPasos;
  final List<String> etiquetas;

  const _BarraProgreso({
    required this.pasoActual,
    required this.totalPasos,
    required this.etiquetas,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Barra linear
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (pasoActual + 1) / totalPasos,
            minHeight: 6,
            backgroundColor: colors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
          ),
        ),
        const SizedBox(height: 8),
        // Ubicación actual
        Row(
          children: [
            const Icon(Icons.location_pin, size: 14, color: Colors.orange),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                pasoActual < etiquetas.length
                    ? etiquetas[pasoActual]
                    : 'En ruta...',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${pasoActual + 1}/$totalPasos',
              style: TextStyle(
                  fontSize: 11, color: colors.onSurface.withOpacity(0.5)),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA: CONTADOR DE ASIENTOS EN TIEMPO REAL (STREAM)
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaAsientosStream extends StatelessWidget {
  final String camionetaId;

  const _TarjetaAsientosStream({required this.camionetaId});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final db = FirebaseFirestore.instance;

    return StreamBuilder<DocumentSnapshot>(
      stream: db.collection('camionetas').doc(camionetaId).snapshots(),
      builder: (context, snap) {
        int ocupados = 0;
        int total = 24;
        bool cargando = snap.connectionState == ConnectionState.waiting;

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>;
          final asientos = (data['asientos'] as Map<String, dynamic>?) ?? {};
          total = asientos.length > 0 ? asientos.length : 24;
          ocupados = asientos.values.where((v) {
            if (v is Map) return v['ocupado'] == true;
            return false;
          }).length;
        }

        final libres = total - ocupados;
        final porcentaje = total > 0 ? ocupados / total : 0.0;

        return Card(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.event_seat_outlined, color: colors.primary),
                    const SizedBox(width: 8),
                    Text('Ocupación en Tiempo Real',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (cargando)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 20),

                // Números grandes
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ContadorBloque(
                        valor: ocupados,
                        etiqueta: 'Ocupados',
                        color: Colors.red.shade400),
                    Container(
                        width: 1, height: 50, color: colors.outlineVariant),
                    _ContadorBloque(
                        valor: libres,
                        etiqueta: 'Libres',
                        color: Colors.green.shade500),
                    Container(
                        width: 1, height: 50, color: colors.outlineVariant),
                    _ContadorBloque(
                        valor: total, etiqueta: 'Total', color: colors.primary),
                  ],
                ),
                const SizedBox(height: 16),

                // Barra de ocupación
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Ocupación',
                            style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurface.withOpacity(0.6))),
                        Text(
                          '${(porcentaje * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _colorOcupacion(porcentaje)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: porcentaje,
                        minHeight: 8,
                        backgroundColor: colors.surfaceVariant,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            _colorOcupacion(porcentaje)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _colorOcupacion(double p) {
    if (p >= 0.9) return Colors.red.shade500;
    if (p >= 0.6) return Colors.orange.shade500;
    return Colors.green.shade500;
  }
}

class _ContadorBloque extends StatelessWidget {
  final int valor;
  final String etiqueta;
  final Color color;

  const _ContadorBloque({
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$valor',
          style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.bold, color: color),
        ),
        Text(etiqueta,
            style: TextStyle(
                fontSize: 12,
                color:
                    Theme.of(context).colorScheme.onSurface.withOpacity(0.6))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TARJETA: PARADAS DE LA RUTA (informativa)
// ─────────────────────────────────────────────────────────────────────────────

class _TarjetaParadas extends StatelessWidget {
  const _TarjetaParadas();

  static const _paradas = [
    (icono: Icons.trip_origin, nombre: 'La California Norte', tipo: 'Origen'),
    (icono: Icons.more_vert, nombre: 'Av. Francisco de Miranda', tipo: ''),
    (icono: Icons.more_vert, nombre: 'Petare — Entrada', tipo: ''),
    (icono: Icons.more_vert, nombre: 'Av. Rómulo Gallegos', tipo: ''),
    (
      icono: Icons.school_outlined,
      nombre: 'Entrada USM Caracas',
      tipo: 'Destino'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.map_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Text('Ruta Simulada',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            ..._paradas.map((p) => _FilaParada(
                  icono: p.icono,
                  nombre: p.nombre,
                  tipo: p.tipo,
                  esUltimo: p == _paradas.last,
                )),
          ],
        ),
      ),
    );
  }
}

class _FilaParada extends StatelessWidget {
  final IconData icono;
  final String nombre;
  final String tipo;
  final bool esUltimo;

  const _FilaParada({
    required this.icono,
    required this.nombre,
    required this.tipo,
    required this.esUltimo,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final esDestino = tipo == 'Destino';
    final esOrigen = tipo == 'Origen';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(icono,
                size: 20,
                color: esDestino
                    ? colors.primary
                    : esOrigen
                        ? Colors.green
                        : colors.outline),
            if (!esUltimo)
              Container(width: 2, height: 20, color: colors.outlineVariant),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(nombre,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: (esOrigen || esDestino)
                              ? FontWeight.bold
                              : FontWeight.normal)),
                ),
                if (tipo.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: (esDestino
                          ? colors.primaryContainer
                          : Colors.green.shade50),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(tipo,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: esDestino
                                ? colors.primary
                                : Colors.green.shade700)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
