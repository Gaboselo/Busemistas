// lib/providers/auth_provider.dart
<<<<<<< HEAD
// Busemistas USM v6
// REGLA: sin tildes, sin enies, sin caracteres especiales en comentarios ni variables.
// Cambios v6:
//   - Nuevo rol 'empleado' agregado al enum RolUsuario
//   - Metodos estaticos tarifaPasaje(rol) y tarifaPlan(rol) centralizan tarifas
//     Estudiante: pasaje $1.00 / Plan Busemistas $14.00
=======
// Busemistas USM v5
// REGLA: sin tildes, sin enies, sin caracteres especiales en comentarios ni variables.
// Cambios v5:
//   - Nuevo rol 'empleado' agregado al enum RolUsuario
//   - Metodos estaticos tarifaPasaje(rol) y tarifaPlan(rol) centralizan tarifas
//     Estudiante: pasaje $1.00 / Plan Usemista $14.00
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
//     Empleado  : pasaje $0.50 / Plan Empleado  $7.00
//     Visitante : pasaje $1.00 / sin plan mensual
//   - verificarCedula consulta tambien 'lista_oficial_profesor_empleado'
//   - registrarUsuario soporta rol empleado

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AuthEstado { inicial, cargando, exito, error }

enum RolUsuario { estudiante, conductor, visitante, empleado }

// Resultado del primer paso: verificacion de cedula
enum ResultadoVerificacion {
  esEstudiante,
  esConductor,
  esEmpleado,
  noAutorizado,
  yaRegistrado,
  error,
}

// ── Tarifas centralizadas (unica fuente de verdad) ───────────────────────────
// Cualquier modulo que necesite cobrar DEBE llamar estos metodos.
// Nunca usar valores hardcodeados de $1.00 en otro archivo.
// ─────────────────────────────────────────────────────────────────────────────
class Tarifas {
  // Costo de un pasaje individual segun el rol del usuario
  static double pasaje(RolUsuario? rol) {
    switch (rol) {
      case RolUsuario.empleado:
        return 0.50;
      case RolUsuario.estudiante:
      case RolUsuario.visitante:
      case RolUsuario.conductor:
      case null:
        return 1.00;
    }
  }

  // Costo del plan mensual segun rol (0 = no aplica plan para ese rol)
  static double plan(RolUsuario? rol) {
    switch (rol) {
      case RolUsuario.empleado:
        return 7.00;
      case RolUsuario.estudiante:
        return 14.00;
      case RolUsuario.visitante:
      case RolUsuario.conductor:
      case null:
        return 0.0; // No aplica plan mensual
    }
  }

  // Nombre del plan segun rol
  static String nombrePlan(RolUsuario? rol) {
    switch (rol) {
      case RolUsuario.empleado:
        return 'Plan Empleado';
      case RolUsuario.estudiante:
<<<<<<< HEAD
        return 'Plan Busemistas';
=======
        return 'Plan Usemista';
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
      default:
        return 'Sin Plan';
    }
  }

  // Indica si el rol puede contratar un plan mensual
  static bool tienePlanDisponible(RolUsuario? rol) {
    return rol == RolUsuario.estudiante || rol == RolUsuario.empleado;
  }
}

class AuthProvider extends ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  AuthEstado _estado = AuthEstado.inicial;
  AuthEstado get estado => _estado;

  String? _mensajeError;
  String? get mensajeError => _mensajeError;

  String? _cedulaActual;
  String? get cedulaActual => _cedulaActual;

  String? _nombreCompleto;
  String? get nombreCompleto => _nombreCompleto;

  RolUsuario? _rolSeleccionado;
  RolUsuario? get rolSeleccionado => _rolSeleccionado;

  String? _camionetaAsignada;
  String? get camionetaAsignada => _camionetaAsignada;

  double _saldo = 0.0;
  double get saldo => _saldo;

  bool _mensualidadActiva = false;
  bool get mensualidadActiva => _mensualidadActiva;

  // Nombre bloqueado: vino de lista oficial, no editable por el usuario
  bool _nombreBloqueado = false;
  bool get nombreBloqueado => _nombreBloqueado;

  // ── Helpers ─────────────────────────────────────────────────────
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
    if (rol == RolUsuario.visitante) {
      _nombreCompleto = null;
      _nombreBloqueado = false;
    }
    notifyListeners();
  }

  void actualizarSaldo(double nuevoSaldo) {
    _saldo = nuevoSaldo;
    notifyListeners();
  }

  void actualizarMensualidad(bool activa) {
    _mensualidadActiva = activa;
    notifyListeners();
  }

<<<<<<< HEAD
  void actualizarCamionetaAsignada(String id) {
    _camionetaAsignada = id;
    notifyListeners();
  }

=======
>>>>>>> 270597324932842ceccb48803ec812f0fa20dcce
  // ────────────────────────────────────────────────────────────────
  // PASO 1: Verificar cedula (antes del registro)
  // Retorna si es estudiante, conductor, ya registrado o no autorizado.
  // Si encontrado en lista oficial -> guarda _nombreCompleto para el form.
  // ────────────────────────────────────────────────────────────────
  Future<ResultadoVerificacion> verificarCedula(String cedula) async {
    _setEstado(AuthEstado.cargando);
    _cedulaActual = cedula;
    _nombreCompleto = null;
    _nombreBloqueado = false;

    try {
      // Verificar si ya existe en usuarios (ya tiene cuenta)
      final docUsuario = await _db.collection('usuarios').doc(cedula).get();
      if (docUsuario.exists) {
        _setEstado(AuthEstado.inicial);
        return ResultadoVerificacion.yaRegistrado;
      }

      // Buscar en lista de estudiantes
      final docEst =
          await _db.collection('lista_oficial_estudiantes').doc(cedula).get();
      if (docEst.exists) {
        final data = docEst.data()!;
        _nombreCompleto =
            (data['nombre_completo'] ?? data['nombre']) as String?;
        _nombreBloqueado = true;
        _rolSeleccionado = RolUsuario.estudiante;
        _setEstado(AuthEstado.inicial);
        return ResultadoVerificacion.esEstudiante;
      }

      // Buscar en lista de conductores
      final docCon =
          await _db.collection('lista_oficial_conductores').doc(cedula).get();
      if (docCon.exists) {
        final data = docCon.data()!;
        _nombreCompleto =
            (data['nombre_completo'] ?? data['nombre']) as String?;
        _nombreBloqueado = true;
        _rolSeleccionado = RolUsuario.conductor;
        _setEstado(AuthEstado.inicial);
        return ResultadoVerificacion.esConductor;
      }

      // Buscar en lista de profesores/empleados
      final docEmp = await _db
          .collection('lista_oficial_profesor_empleado')
          .doc(cedula)
          .get();
      if (docEmp.exists) {
        final data = docEmp.data()!;
        _nombreCompleto =
            (data['nombre_completo'] ?? data['nombre']) as String?;
        _nombreBloqueado = true;
        _rolSeleccionado = RolUsuario.empleado;
        _setEstado(AuthEstado.inicial);
        return ResultadoVerificacion.esEmpleado;
      }

      // No autorizado por la institucion
      _setEstado(AuthEstado.inicial);
      return ResultadoVerificacion.noAutorizado;
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al consultar listas: $e');
      return ResultadoVerificacion.error;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // PASO 2: Registrar usuario con contrasenia
  // nombre_completo siempre se copia de la lista oficial (nunca del campo de texto).
  // ────────────────────────────────────────────────────────────────
  Future<bool> registrarUsuario({
    required String cedula,
    required String correo,
    required String telefono,
    required String contrasenia,
    required RolUsuario rol,
    String razonSocial = '',
    // Solo para visitantes que si tipean su nombre
    String? nombreManual,
  }) async {
    _setEstado(AuthEstado.cargando);

    try {
      // Validacion de seguridad: verificar que la cedula no exista ya
      final existe = await _db.collection('usuarios').doc(cedula).get();
      if (existe.exists) {
        _setEstado(AuthEstado.error,
            error: 'Esta cedula ya tiene una cuenta. Inicia sesion.');
        return false;
      }

      // El nombre viene de la lista oficial (guardado en _nombreCompleto)
      // Para visitantes viene del campo manual
      final nombreFinal = (rol == RolUsuario.visitante)
          ? (nombreManual ?? 'Visitante')
          : (_nombreCompleto ?? 'Usuario');

      // Hash simple de contrasenia para prototipo (en produccion: bcrypt/SHA256)
      // Se almacena directamente como string (demo academico)
      final Map<String, dynamic> datos = {
        'nombre_completo': nombreFinal,
        'correo': correo,
        'telefono': telefono,
        'password_hash': contrasenia, // Prototipo: texto plano (demo)
        'saldo': 0.0,
        'rol': rol.name,
        'mensualidad_activa': false,
        'vencimiento_mensualidad': null,
        'razon_social': razonSocial,
        'fecha_registro': FieldValue.serverTimestamp(),
      };

      if (rol == RolUsuario.conductor) {
        // Para conductor: leer camioneta asignada de la lista oficial
        final docCon =
            await _db.collection('lista_oficial_conductores').doc(cedula).get();
        if (docCon.exists) {
          final camioneta = docCon.data()!['camioneta_asignada'] as String?;
          if (camioneta != null) datos['camioneta_asignada'] = camioneta;
        }
      }

      await _db.collection('usuarios').doc(cedula).set(datos);

      _cedulaActual = cedula;
      _nombreCompleto = nombreFinal;
      _rolSeleccionado = rol;
      _saldo = 0.0;
      _mensualidadActiva = false;
      _setEstado(AuthEstado.exito);
      return true;
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al registrar: $e');
      return false;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // LOGIN: cedula + contrasenia
  // ────────────────────────────────────────────────────────────────
  Future<RolUsuario?> login(String cedula, String contrasenia) async {
    _setEstado(AuthEstado.cargando);

    try {
      final doc = await _db.collection('usuarios').doc(cedula).get();

      if (!doc.exists) {
        _setEstado(AuthEstado.error,
            error: 'No existe cuenta con esta cedula. Registrate primero.');
        return null;
      }

      final data = doc.data()!;
      final passwordGuardado = data['password_hash'] as String? ?? '';

      // Validar contrasenia
      if (passwordGuardado != contrasenia) {
        _setEstado(AuthEstado.error,
            error: 'Contrasenia incorrecta. Intenta de nuevo.');
        return null;
      }

      return _cargarDatosUsuario(cedula, data);
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al iniciar sesion: $e');
      return null;
    }
  }

  // ────────────────────────────────────────────────────────────────
  // LOGIN via QR: cedula leida del carnet
  // Solo valida que exista en 'usuarios' con contrasenia ya configurada.
  // Si no tiene cuenta todavia, retorna null y la app lo redirige a registro.
  // ────────────────────────────────────────────────────────────────
  Future<RolUsuario?> loginQR(String cedula) async {
    _setEstado(AuthEstado.cargando);

    try {
      final doc = await _db.collection('usuarios').doc(cedula).get();

      if (!doc.exists) {
        // No tiene cuenta: verificar si esta en lista oficial para registro
        final docEst =
            await _db.collection('lista_oficial_estudiantes').doc(cedula).get();
        final docCon =
            await _db.collection('lista_oficial_conductores').doc(cedula).get();

        if (!docEst.exists && !docCon.exists) {
          // Revisar lista de empleados antes de rechazar
          final docEmp = await _db
              .collection('lista_oficial_profesor_empleado')
              .doc(cedula)
              .get();
          if (!docEmp.exists) {
            _setEstado(AuthEstado.error,
                error: 'Carnet no autorizado por la institucion.');
            return null;
          }
          final data = docEmp.data()!;
          _nombreCompleto =
              (data['nombre_completo'] ?? data['nombre']) as String?;
          _nombreBloqueado = true;
          _rolSeleccionado = RolUsuario.empleado;
          _cedulaActual = cedula;
          _setEstado(AuthEstado.error, error: '__NECESITA_REGISTRO__');
          return null;
        }

        // Esta en la lista pero no tiene cuenta: pedir registro
        if (docEst.exists) {
          final data = docEst.data()!;
          _nombreCompleto =
              (data['nombre_completo'] ?? data['nombre']) as String?;
          _nombreBloqueado = true;
          _rolSeleccionado = RolUsuario.estudiante;
        } else {
          final data = docCon.data()!;
          _nombreCompleto =
              (data['nombre_completo'] ?? data['nombre']) as String?;
          _nombreBloqueado = true;
          _rolSeleccionado = RolUsuario.conductor;
        }
        _cedulaActual = cedula;
        _setEstado(AuthEstado.error, error: '__NECESITA_REGISTRO__');
        return null;
      }

      // Tiene cuenta: acceso directo via QR (sin contrasenia)
      // El QR del carnet fisico ya es el factor de autenticacion
      return _cargarDatosUsuario(cedula, doc.data()!);
    } catch (e) {
      _setEstado(AuthEstado.error, error: 'Error al verificar QR: $e');
      return null;
    }
  }

  // ── Carga datos desde doc de usuario ───────────────────────────
  RolUsuario _cargarDatosUsuario(String cedula, Map<String, dynamic> data) {
    final rolStr = data['rol'] as String? ?? '';
    final rol = RolUsuario.values.firstWhere(
      (r) => r.name == rolStr,
      orElse: () => RolUsuario.visitante,
    );
    _cedulaActual = cedula;
    _nombreCompleto = data['nombre_completo'] as String?;
    _rolSeleccionado = rol;
    _camionetaAsignada = data['camioneta_asignada'] as String?;
    _saldo = (data['saldo'] as num?)?.toDouble() ?? 0.0;
    _mensualidadActiva = data['mensualidad_activa'] as bool? ?? false;
    _setEstado(AuthEstado.exito);
    return rol;
  }

  // ── Refresca datos desde Firestore ─────────────────────────────
  Future<void> refrescarDatosUsuario() async {
    if (_cedulaActual == null) return;
    try {
      final doc = await _db.collection('usuarios').doc(_cedulaActual).get();
      if (doc.exists) {
        final data = doc.data()!;
        _saldo = (data['saldo'] as num?)?.toDouble() ?? 0.0;
        _mensualidadActiva = data['mensualidad_activa'] as bool? ?? false;
        _nombreCompleto = data['nombre_completo'] as String? ?? _nombreCompleto;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ── Cerrar sesion ───────────────────────────────────────────────
  void cerrarSesion() {
    _cedulaActual = null;
    _nombreCompleto = null;
    _rolSeleccionado = null;
    _camionetaAsignada = null;
    _nombreBloqueado = false;
    _saldo = 0.0;
    _mensualidadActiva = false;
    _setEstado(AuthEstado.inicial);
  }
}
