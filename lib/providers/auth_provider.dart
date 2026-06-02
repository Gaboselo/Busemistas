import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthEstado { inicial, cargando, exito, error }

enum RolUsuario { estudiante, conductor, visitante }

class AuthProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Estado general ──────────────────────────────────────────────
  AuthEstado _estado = AuthEstado.inicial;
  AuthEstado get estado => _estado;

  String? _mensajeError;
  String? get mensajeError => _mensajeError;

  // ── Datos del usuario autenticado / en registro ─────────────────
  String? _cedulaActual;
  String? get cedulaActual => _cedulaActual;

  String? _nombreCompleto;
  String? get nombreCompleto => _nombreCompleto;

  RolUsuario? _rolSeleccionado;
  RolUsuario? get rolSeleccionado => _rolSeleccionado;

  /// ID del documento en camionetas asignado al conductor (null para otros roles)
  String? _camionetaAsignada;
  String? get camionetaAsignada => _camionetaAsignada;

  /// true = el nombre vino de Firestore y no debe editarse
  bool _nombreBloqueado = false;
  bool get nombreBloqueado => _nombreBloqueado;

  // ── Helpers internos ────────────────────────────────────────────
  void _setEstado(AuthEstado e, {String? error}) {
    _estado = e;
    _mensajeError = error;
    notifyListeners();
  }

  void limpiarError() {
    _mensajeError = null;
    notifyListeners();
  }

  void seleccionarRol(RolUsuario rol) {
    _rolSeleccionado = rol;
    // Al cambiar a visitante, desbloquear nombre
    if (rol == RolUsuario.visitante) {
      _nombreCompleto = null;
      _nombreBloqueado = false;
    }
    notifyListeners();
  }

  // ── PASO 1: Validar cédula en listas institucionales ────────────
  /// Devuelve true si se encontró en alguna lista.
  /// Carga [_nombreCompleto] y bloquea el campo si existe.
  Future<bool> validarCedulaInstitucional(String cedula) async {
    _setEstado(AuthEstado.cargando);
    _cedulaActual = cedula;
    _nombreBloqueado = false;
    _nombreCompleto = null;

    try {
      // Buscar en estudiantes
      final docEst =
          await _db.collection('lista_oficial_estudiantes').doc(cedula).get();

      if (docEst.exists) {
        _nombreCompleto = docEst.data()?['nombre_completo'] as String?;
        _nombreBloqueado = true;
        _rolSeleccionado = RolUsuario.estudiante;
        _setEstado(AuthEstado.exito);
        return true;
      }

      // Buscar en conductores
      final docCon =
          await _db.collection('lista_oficial_conductores').doc(cedula).get();

      if (docCon.exists) {
        _nombreCompleto = docCon.data()?['nombre_completo'] as String?;
        _nombreBloqueado = true;
        _rolSeleccionado = RolUsuario.conductor;
        _setEstado(AuthEstado.exito);
        return true;
      }

      // No está en ninguna lista institucional
      _setEstado(AuthEstado.inicial);
      return false;
    } catch (e) {
      _setEstado(AuthEstado.error,
          error: 'Error al consultar las listas institucionales: $e');
      return false;
    }
  }

  // ── PASO 2: Registrar usuario en Firestore ──────────────────────
  Future<bool> registrarUsuario({
    required String cedula,
    required String nombreCompleto,
    required String correo,
    required String telefono,
    required RolUsuario rol,
    String razonSocial = '',
  }) async {
    _setEstado(AuthEstado.cargando);

    try {
      // Verificar que la cédula no exista ya en usuarios
      final docExistente = await _db.collection('usuarios').doc(cedula).get();
      if (docExistente.exists) {
        _setEstado(AuthEstado.error,
            error: 'Esta cédula ya está registrada. Por favor inicia sesión.');
        return false;
      }

      await _db.collection('usuarios').doc(cedula).set({
        'nombre_completo': nombreCompleto,
        'correo': correo,
        'telefono': telefono,
        'saldo': 0,
        'rol': rol.name, // 'estudiante' | 'conductor' | 'visitante'
        'mensualidad_activa': false,
        'vencimiento_mensualidad': null,
        'razon_social': razonSocial,
        'fecha_registro': FieldValue.serverTimestamp(),
      });

      _cedulaActual = cedula;
      _nombreCompleto = nombreCompleto;
      _rolSeleccionado = rol;
      _setEstado(AuthEstado.exito);
      return true;
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al registrar usuario: $e');
      return false;
    }
  }

  // ── LOGIN ───────────────────────────────────────────────────────
  /// Devuelve el [RolUsuario] si la cédula existe en `usuarios`, null si no.
  Future<RolUsuario?> login(String cedula) async {
    _setEstado(AuthEstado.cargando);

    try {
      final doc = await _db.collection('usuarios').doc(cedula).get();

      if (!doc.exists) {
        _setEstado(AuthEstado.error,
            error: 'No existe una cuenta con esta cédula.');
        return null;
      }

      final data = doc.data()!;
      final rolStr = data['rol'] as String? ?? '';
      final rol = RolUsuario.values.firstWhere(
        (r) => r.name == rolStr,
        orElse: () => RolUsuario.visitante,
      );

      _cedulaActual = cedula;
      _nombreCompleto = data['nombre_completo'] as String?;
      _rolSeleccionado = rol;
      _camionetaAsignada = data['camioneta_asignada'] as String?;
      _setEstado(AuthEstado.exito);
      return rol;
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al iniciar sesión: $e');
      return null;
    }
  }

  // ── Cerrar sesión ───────────────────────────────────────────────
  void cerrarSesion() {
    _cedulaActual = null;
    _nombreCompleto = null;
    _rolSeleccionado = null;
    _camionetaAsignada = null;
    _nombreBloqueado = false;
    _setEstado(AuthEstado.inicial);
  }
}
