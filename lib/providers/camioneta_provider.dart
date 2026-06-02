// lib/providers/camioneta_provider.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../modelos/camioneta_modelo.dart';

class CamionetaProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<CamionetaModelo> _camionetas = [];
  List<CamionetaModelo> get camionetas => _camionetas;

  /// Solo las activas (disponible o en_camino)
  List<CamionetaModelo> get camionetasActivas =>
      _camionetas.where((c) => c.estaActiva).toList();

  bool _cargando = true;
  bool get cargando => _cargando;

  String? _error;
  String? get error => _error;

  StreamSubscription<QuerySnapshot>? _sub;

  // ── Iniciar stream ──────────────────────────────────────────────
  void iniciarStream() {
    _sub?.cancel();

    _sub = _db.collection('camionetas').snapshots().listen(
      (snapshot) {
        _camionetas =
            snapshot.docs.map((d) => CamionetaModelo.fromDoc(d)).toList();
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

  // ── Detener stream ──────────────────────────────────────────────
  void detenerStream() {
    _sub?.cancel();
    _sub = null;
  }

  @override
  void dispose() {
    detenerStream();
    super.dispose();
  }
}
