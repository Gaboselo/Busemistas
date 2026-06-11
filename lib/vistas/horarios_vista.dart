// lib/vistas/horarios_vista.dart
// Busemistas USM v4
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios:
//   - Conectado con estado real de la camioneta via StreamBuilder
//   - Si la unidad reporta retraso, las proximas 3 salidas muestran
//     "Retrasado +20min" o "Retrasado +30min" segun el ETA calculado

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

const Color _kAzul = Color(0xFF0E004A);

// Coordenadas de referencia
const double _latUSM = 10.491360068207142;
const double _lngUSM = -66.78017873573735;
const double _latLaCalif = 10.483376;
const double _lngLaCalif = -66.819402;

class HorariosVista extends StatefulWidget {
  const HorariosVista({super.key});

  @override
  State<HorariosVista> createState() => _HorariosVistaState();
}

class _HorariosVistaState extends State<HorariosVista>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _tabs = const ['Manana (Pico)', 'Mediodia', 'Tarde/Noche'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horarios de Buses'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          indicatorColor: Colors.white,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: Column(children: [
        // Encabezado de ruta
        Container(
          color: _kAzul.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            const Icon(Icons.swap_horiz_rounded, color: _kAzul),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Estacion La California <-> USM Sede La Florencia',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: _kAzul)),
                    Text(
                      'Operacion: 06:20 AM - 10:10 PM  |  Lunes a Viernes',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ]),
            ),
          ]),
        ),

        // Banner de estado en tiempo real
        StreamBuilder<QuerySnapshot>(
          stream:
              FirebaseFirestore.instance.collection('camionetas').snapshots(),
          builder: (context, snap) {
            // Calcular nivel de retraso de la flota activa
            int nivelRetraso = 0; // 0=ninguno, 1=moderado(>20), 2=alto(>30)

            if (snap.hasData) {
              for (final doc in snap.data!.docs) {
                final data = doc.data() as Map<String, dynamic>;
                final estado = data['estado'] as String? ?? '';
                if (estado != 'en_camino') continue;

                final lat = (data['latitud'] as num?)?.toDouble();
                final lng = (data['longitud'] as num?)?.toDouble();
                final destino = data['destino'] as String? ?? '';
                if (lat == null || lng == null) continue;

                // Calcular ETA
                final esHaciaUSM = destino.toLowerCase().contains('usm') ||
                    destino.toLowerCase().contains('florencia');
                final distMetros = Geolocator.distanceBetween(
                  lat,
                  lng,
                  esHaciaUSM ? _latUSM : _latLaCalif,
                  esHaciaUSM ? _lngUSM : _lngLaCalif,
                );
                final etaMin = (distMetros / 1000 / 40.0) * 60;

                if (etaMin > 30 && nivelRetraso < 2) nivelRetraso = 2;
                if (etaMin > 20 && nivelRetraso < 1) nivelRetraso = 1;
              }
            }

            if (nivelRetraso == 0) return const SizedBox.shrink();

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: nivelRetraso == 2
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: nivelRetraso == 2
                        ? Colors.red.shade300
                        : Colors.orange.shade300),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: nivelRetraso == 2
                        ? Colors.red.shade700
                        : Colors.orange.shade700,
                    size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    nivelRetraso == 2
                        ? 'Alto retraso detectado: proximas 3 salidas afectadas +30min'
                        : 'Retraso moderado: proximas 3 salidas afectadas +20min',
                    style: TextStyle(
                        color: nivelRetraso == 2
                            ? Colors.red.shade800
                            : Colors.orange.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            );
          },
        ),
        const SizedBox(height: 4),

        // Tablas de horarios
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance.collection('camionetas').snapshots(),
            builder: (context, snap) {
              // Calcular nivel de retraso para pasar a las tablas
              int nivelRetraso = 0;

              if (snap.hasData) {
                for (final doc in snap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final estado = data['estado'] as String? ?? '';
                  if (estado != 'en_camino') continue;

                  final lat = (data['latitud'] as num?)?.toDouble();
                  final lng = (data['longitud'] as num?)?.toDouble();
                  final destino = data['destino'] as String? ?? '';
                  if (lat == null || lng == null) continue;

                  final esHaciaUSM = destino.toLowerCase().contains('usm') ||
                      destino.toLowerCase().contains('florencia');
                  final distMetros = Geolocator.distanceBetween(
                    lat,
                    lng,
                    esHaciaUSM ? _latUSM : _latLaCalif,
                    esHaciaUSM ? _lngUSM : _lngLaCalif,
                  );
                  final etaMin = (distMetros / 1000 / 40.0) * 60;

                  if (etaMin > 30 && nivelRetraso < 2) nivelRetraso = 2;
                  if (etaMin > 20 && nivelRetraso < 1) nivelRetraso = 1;
                }
              }

              return TabBarView(
                controller: _tabCtrl,
                children: [
                  _TablaHorarios(
                      filas: _horariosManana, nivelRetraso: nivelRetraso),
                  _TablaHorarios(
                      filas: _horariosMediadia, nivelRetraso: nivelRetraso),
                  _TablaHorarios(
                      filas: _horariosNoche, nivelRetraso: nivelRetraso),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLA DE HORARIOS
// ─────────────────────────────────────────────────────────────────────────────

class _TablaHorarios extends StatelessWidget {
  final List<_FilaHorario> filas;
  final int nivelRetraso; // 0=ninguno, 1=+20min, 2=+30min

  const _TablaHorarios({required this.filas, required this.nivelRetraso});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          // Encabezado de columnas
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _kAzul,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(children: [
              SizedBox(
                  width: 50,
                  child: Text('#',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              Expanded(
                  child: Text('Salida La Calif.',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              Expanded(
                  child: Text('Llegada USM',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              Expanded(
                  child: Text('Regreso USM',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
              SizedBox(
                  width: 70,
                  child: Text('Estado',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12))),
            ]),
          ),
          const SizedBox(height: 8),
          ...filas.asMap().entries.map((entry) {
            final idx = entry.key;
            final f = entry.value;
            // Afectar las proximas 3 filas con el retraso
            final afectada = nivelRetraso > 0 && idx < 3;
            return _FilaTabla(
                fila: f,
                par: idx.isEven,
                retrasoOverride: afectada ? nivelRetraso : 0);
          }),
        ]),
      ),
    );
  }
}

class _FilaTabla extends StatelessWidget {
  final _FilaHorario fila;
  final bool par;
  final int retrasoOverride; // 0=sin override, 1=+20min, 2=+30min

  const _FilaTabla(
      {required this.fila, required this.par, required this.retrasoOverride});

  Color _colorEstado(String e) => switch (e) {
        'Puntual' => Colors.green.shade700,
        'Pico' => Colors.orange.shade700,
        'Frecuente' => Colors.blue.shade700,
        _ => Colors.grey.shade600,
      };

  @override
  Widget build(BuildContext context) {
    // Determinar etiqueta y color del estado
    final String etiqueta;
    final Color colorEstado;

    if (retrasoOverride == 2) {
      etiqueta = 'Retrasado +30min';
      colorEstado = Colors.red.shade700;
    } else if (retrasoOverride == 1) {
      etiqueta = 'Retrasado +20min';
      colorEstado = Colors.orange.shade700;
    } else {
      etiqueta = fila.estado;
      colorEstado = _colorEstado(fila.estado);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: retrasoOverride > 0
            ? (retrasoOverride == 2
                ? Colors.red.shade50
                : Colors.orange.shade50)
            : (par ? Colors.white : const Color(0xFFF5F0FF)),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: retrasoOverride > 0
                ? colorEstado.withValues(alpha: 0.3)
                : Colors.grey.shade200),
      ),
      child: Row(children: [
        SizedBox(
          width: 50,
          child: Text('${fila.numero}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 12, color: _kAzul)),
        ),
        Expanded(
            child:
                Text(fila.salidaCalif, style: const TextStyle(fontSize: 12))),
        Expanded(
            child: Text(fila.llegadaUSM, style: const TextStyle(fontSize: 12))),
        Expanded(
            child: Text(fila.regresoUSM, style: const TextStyle(fontSize: 12))),
        SizedBox(
          width: 70,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: colorEstado.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              etiqueta,
              style: TextStyle(
                  fontSize: retrasoOverride > 0 ? 9 : 10,
                  color: colorEstado,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATOS DE HORARIOS
// ─────────────────────────────────────────────────────────────────────────────

class _FilaHorario {
  final int numero;
  final String salidaCalif;
  final String llegadaUSM;
  final String regresoUSM;
  final String estado;
  const _FilaHorario(this.numero, this.salidaCalif, this.llegadaUSM,
      this.regresoUSM, this.estado);
}

const _horariosManana = [
  _FilaHorario(1, '06:20 AM', '06:55 AM', '07:30 AM', 'Puntual'),
  _FilaHorario(2, '06:45 AM', '07:20 AM', '07:50 AM', 'Puntual'),
  _FilaHorario(3, '07:00 AM', '07:40 AM', '08:15 AM', 'Pico'),
  _FilaHorario(4, '07:15 AM', '08:00 AM', '08:40 AM', 'Pico'),
  _FilaHorario(5, '07:30 AM', '08:10 AM', '08:50 AM', 'Pico'),
  _FilaHorario(6, '07:45 AM', '08:25 AM', '09:05 AM', 'Pico'),
  _FilaHorario(7, '08:00 AM', '08:40 AM', '09:20 AM', 'Pico'),
  _FilaHorario(8, '08:30 AM', '09:10 AM', '09:45 AM', 'Frecuente'),
  _FilaHorario(9, '09:00 AM', '09:35 AM', '10:10 AM', 'Puntual'),
  _FilaHorario(10, '09:30 AM', '10:00 AM', '10:35 AM', 'Puntual'),
  _FilaHorario(11, '10:00 AM', '10:30 AM', '11:00 AM', 'Puntual'),
];

const _horariosMediadia = [
  _FilaHorario(12, '11:00 AM', '11:35 AM', '12:10 PM', 'Puntual'),
  _FilaHorario(13, '11:30 AM', '12:05 PM', '12:40 PM', 'Puntual'),
  _FilaHorario(14, '12:00 PM', '12:35 PM', '01:10 PM', 'Frecuente'),
  _FilaHorario(15, '12:30 PM', '01:05 PM', '01:40 PM', 'Pico'),
  _FilaHorario(16, '01:00 PM', '01:40 PM', '02:20 PM', 'Pico'),
  _FilaHorario(17, '01:30 PM', '02:05 PM', '02:45 PM', 'Puntual'),
  _FilaHorario(18, '02:00 PM', '02:35 PM', '03:10 PM', 'Puntual'),
  _FilaHorario(19, '02:30 PM', '03:05 PM', '03:40 PM', 'Puntual'),
];

const _horariosNoche = [
  _FilaHorario(20, '03:30 PM', '04:10 PM', '04:50 PM', 'Frecuente'),
  _FilaHorario(21, '04:00 PM', '04:45 PM', '05:30 PM', 'Pico'),
  _FilaHorario(22, '04:30 PM', '05:15 PM', '06:00 PM', 'Pico'),
  _FilaHorario(23, '05:00 PM', '05:45 PM', '06:30 PM', 'Pico'),
  _FilaHorario(24, '05:30 PM', '06:10 PM', '06:50 PM', 'Frecuente'),
  _FilaHorario(25, '06:00 PM', '06:35 PM', '07:10 PM', 'Puntual'),
  _FilaHorario(26, '07:00 PM', '07:35 PM', '08:10 PM', 'Puntual'),
  _FilaHorario(27, '08:00 PM', '08:40 PM', '09:15 PM', 'Puntual'),
  _FilaHorario(28, '09:00 PM', '09:35 PM', '10:10 PM', 'Puntual'),
];
