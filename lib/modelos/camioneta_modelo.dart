// lib/modelos/camioneta_modelo.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum EstadoCamioneta { disponible, en_camino, emergencia, desconocido }

class CamionetaModelo {
  final String id;
  final String nombre;
  final String modelo;
  final String color;
  final String patente;
  final String chofer;
  final EstadoCamioneta estado;
  final String destino;
  final GeoPoint? ubicacion;
  final Map<String, dynamic> asientos;
  final bool activa;
  final bool trafico_denso;

  const CamionetaModelo({
    required this.id,
    required this.nombre,
    required this.modelo,
    required this.color,
    required this.patente,
    required this.chofer,
    required this.estado,
    required this.destino,
    required this.ubicacion,
    required this.asientos,
    required this.activa,
    required this.trafico_denso,
  });

  factory CamionetaModelo.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final estadoStr = data['estado'] as String? ?? '';
    final estado = switch (estadoStr) {
      'disponible' => EstadoCamioneta.disponible,
      'en_camino' => EstadoCamioneta.en_camino,
      'emergencia' => EstadoCamioneta.emergencia,
      _ => EstadoCamioneta.desconocido,
    };

    final asientosRaw = data['asientos'] as Map<String, dynamic>? ?? {};

    return CamionetaModelo(
      id: doc.id,
      nombre: data['nombre'] as String? ?? doc.id,
      modelo: data['modelo'] as String? ?? 'Sin modelo',
      color: data['color'] as String? ?? '',
      patente: data['patente'] as String? ?? '',
      chofer: data['chofer'] as String? ?? '',
      estado: estado,
      destino: data['destino'] as String? ?? 'Sin destino',
      ubicacion: data['ubicacion'] as GeoPoint?,
      asientos: asientosRaw,
      activa: data['activa'] as bool? ?? false,
      trafico_denso: data['trafico_denso'] as bool? ?? false,
    );
  }

  /// Asientos libres: contados sobre el mapa de asientos
  int get asientosLibres {
    if (asientos.isEmpty) return 24;
    return asientos.values.where((v) {
      if (v is Map) return v['ocupado'] == false;
      return true;
    }).length;
  }

  int get totalAsientos => asientos.isEmpty ? 24 : asientos.length;

  /// Una unidad está activa si su estado es disponible o en_camino
  bool get estaActiva =>
      estado == EstadoCamioneta.disponible ||
      estado == EstadoCamioneta.en_camino;

  /// Una unidad es seleccionable si está disponible y tiene asientos libres
  bool get esSeleccionable =>
      estado == EstadoCamioneta.disponible && asientosLibres > 0;
}
