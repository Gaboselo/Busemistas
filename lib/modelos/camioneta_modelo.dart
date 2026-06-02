// lib/modelos/camioneta_modelo.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum EstadoCamioneta { disponible, en_camino, emergencia, desconocido }

class CamionetaModelo {
  final String id;
  final String modelo;
  final String color;
  final String patente;
  final EstadoCamioneta estado;
  final String destino;
  final GeoPoint? ubicacion;
  final Map<String, dynamic> asientos;

  const CamionetaModelo({
    required this.id,
    required this.modelo,
    required this.color,
    required this.patente,
    required this.estado,
    required this.destino,
    required this.ubicacion,
    required this.asientos,
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
      modelo: data['modelo'] as String? ?? 'Sin modelo',
      color: data['color'] as String? ?? '',
      patente: data['patente'] as String? ?? '',
      estado: estado,
      destino: data['destino'] as String? ?? 'Sin destino',
      ubicacion: data['ubicacion'] as GeoPoint?,
      asientos: asientosRaw,
    );
  }

  /// Cuenta cuántos asientos tienen ocupado == false
  int get asientosLibres {
    if (asientos.isEmpty) return 0;
    return asientos.values.where((v) {
      if (v is Map) return v['ocupado'] == false;
      return false;
    }).length;
  }

  int get totalAsientos => asientos.length;

  bool get estaActiva =>
      estado == EstadoCamioneta.disponible ||
      estado == EstadoCamioneta.en_camino;
}
