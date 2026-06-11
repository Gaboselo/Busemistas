// lib/providers/camioneta_provider.dart
<<<<<<< HEAD
// Busemistas USM v5
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambios v5:
//   - auto-inicializa 24 asientos via WriteBatch cuando
//     el documento tiene menos de 24 nodos en el mapa de asientos.
//   - sembrarUnidades(): crea unidad_01 y unidad_02 si no existen, para demo.
=======
// Busemistas USM v4
// REGLA: sin tildes, sin enies, sin caracteres especiales.
// Cambio principal: auto-inicializa 24 asientos via WriteBatch cuando
// el documento tiene menos de 24 nodos en el mapa de asientos.
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelos/camioneta_modelo.dart';

class CamionetaProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String kIdPrincipal = 'camioneta_01';

  List<CamionetaModelo> _camionetas = [];
  List<CamionetaModelo> get camionetas => _camionetas;

  List<CamionetaModelo> get camionetasActivas =>
      _camionetas.where((c) => c.estaActiva).toList();

  bool _cargando = true;
  bool get cargando => _cargando;

  String? _error;
  String? get error => _error;

  StreamSubscription? _sub;

  // Evita multiples llamadas concurrentes de inicializacion
  final Set<String> _inicializando = {};

  // ── Poblar 24 asientos atomicamente si el doc tiene menos ────────
  Future<void> _poblarAsientosSiFaltan(
      String docId, Map<String, dynamic> asientosActuales) async {
    if (_inicializando.contains(docId)) return;
    if (asientosActuales.length >= 24) return;

    _inicializando.add(docId);
    debugPrint('[Provider] Inicializando asientos en $docId...');

    try {
      final batch = _db.batch();
      final ref = _db.collection('camionetas').doc(docId);
      final Map<String, dynamic> updates = {};

      for (int i = 1; i <= 24; i++) {
        final key = '$i';
        if (!asientosActuales.containsKey(key)) {
          updates['asientos.$key.ocupado'] = false;
          updates['asientos.$key.cedula_pasajero'] = '';
          updates['asientos.$key.nombre_pasajero'] = '';
          updates['asientos.$key.estado_pago'] = '';
        }
      }

      if (updates.isNotEmpty) {
        batch.update(ref, updates);
        await batch.commit();
        debugPrint('[Provider] 24 asientos escritos en Firestore.');
      }
    } catch (e) {
      debugPrint('[Provider] Error inicializando asientos: $e');
      _inicializando.remove(docId);
    }
  }

  // ── Stream coleccion completa ────────────────────────────────────
  void iniciarStream() {
    _sub?.cancel();
    _sub = _db.collection('camionetas').snapshots().listen(
      (snap) {
        final lista = <CamionetaModelo>[];
        for (final doc in snap.docs) {
          final model = CamionetaModelo.fromDoc(doc);
          lista.add(model);
          if (model.asientos.length < 24) {
            _poblarAsientosSiFaltan(doc.id, model.asientos);
          }
        }
        _camionetas = lista;
        _cargando = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error al cargar camionetas: $e';
        _cargando = false;
        notifyListeners();
      },
    );
  }

  // ── Stream documento unico (prototipo) ───────────────────────────
  void iniciarStreamUnico({String docId = kIdPrincipal}) {
    _sub?.cancel();
    _sub = _db.collection('camionetas').doc(docId).snapshots().listen(
      (docSnap) {
        if (docSnap.exists) {
          final model = CamionetaModelo.fromDoc(docSnap);
          _camionetas = [model];
          if (model.asientos.length < 24) {
            _poblarAsientosSiFaltan(docId, model.asientos);
          }
        } else {
          _camionetas = [];
        }
        _cargando = false;
        _error = null;
        notifyListeners();
      },
      onError: (e) {
        _error = 'Error al cargar camioneta: $e';
        _cargando = false;
        notifyListeners();
      },
    );
  }

  void detenerStream() {
    _sub?.cancel();
    _sub = null;
  }

<<<<<<< HEAD
  // ── Sembrar unidades de demo si no existen ───────────────────────
  // Llama esto una vez al arrancar la app (p.ej. en main.dart o initState).
  // Crea unidad_01 (Hacia La California) y unidad_02 (Hacia la USM)
  // para la demo con dos unidades activas yendo en sentidos opuestos.
  Future<void> sembrarUnidades() async {
    final col = _db.collection('camionetas');

    final Map<String, Map<String, dynamic>> defaults = {
      'unidad_01': {
        'modelo': 'JAC',
        'color': 'azul',
        'patente': 'ABCD12',
        'destino': 'Hacia La California',
        'estado': 'disponible',
        'activa': false,
        'chofer': 'David Burguillos',
        'latitud': 10.491360,
        'longitud': -66.780178,
        'trafico_denso': false,
        'nivel_trafico': 'bajo',
      },
      'unidad_02': {
        'modelo': 'Yutong',
        'color': 'rojo',
        'patente': 'LLPB45',
        'destino': 'Hacia la USM',
        'estado': 'disponible',
        'activa': false,
        'chofer': 'Alessandra Damico',
        'latitud': 10.483376,
        'longitud': -66.819402,
        'trafico_denso': false,
        'nivel_trafico': 'bajo',
      },
    };

    for (final entry in defaults.entries) {
      final docRef = col.doc(entry.key);
      final snap = await docRef.get();
      if (!snap.exists) {
        final data = Map<String, dynamic>.from(entry.value);
        data['asientos'] = _asientosVacios24();
        data['ubicacion'] = GeoPoint((data['latitud'] as num).toDouble(),
            (data['longitud'] as num).toDouble());
        await docRef.set(data);
        debugPrint('[Provider] Creada unidad demo: ${entry.key}');
      } else {
        // Si existe pero le faltan asientos, poblarlos
        final existing = snap.data()!;
        final asientos = (existing['asientos'] as Map<String, dynamic>?) ?? {};
        if (asientos.length < 24) {
          await _poblarAsientosSiFaltan(entry.key, asientos);
        }
      }
    }
  }

  static Map<String, dynamic> _asientosVacios24() {
    final m = <String, dynamic>{};
    for (int i = 1; i <= 24; i++) {
      m['$i'] = {
        'ocupado': false,
        'cedula_pasajero': '',
        'nombre_pasajero': '',
        'estado_pago': '',
      };
    }
    return m;
  }

=======
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  @override
  void dispose() {
    detenerStream();
    super.dispose();
  }
}
