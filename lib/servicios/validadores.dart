// lib/servicios/validadores.dart
// Centraliza todas las reglas de validación de la app.

class Validadores {
  Validadores._();

  // ── Regex ──────────────────────────────────────────────────────
  /// Solo dígitos, sin puntos, espacios, letras ni signos.
  static final RegExp soloDigitos = RegExp(r'^\d+$');

  /// Correo electrónico básico.
  static final RegExp correoValido = RegExp(r'^[\w.-]+@[\w.-]+\.[a-zA-Z]{2,}$');

  /// Teléfono: opcional + al inicio, luego dígitos (7-15 caracteres).
  static final RegExp telefonoValido = RegExp(r'^\+?\d{7,15}$');

  // ── Validadores de campo (usados en TextFormField.validator) ────

  static String? cedula(String? value) {
    if (value == null || value.isEmpty) return 'La cédula es obligatoria.';
    if (!soloDigitos.hasMatch(value)) {
      return 'Solo se permiten números. Sin puntos, letras ni espacios.';
    }
    if (value.length < 5 || value.length > 12) {
      return 'La cédula debe tener entre 5 y 12 dígitos.';
    }
    return null;
  }

  static String? nombreCompleto(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'El nombre completo es obligatorio.';
    }
    if (value.trim().length < 3) return 'El nombre es demasiado corto.';
    return null;
  }

  static String? correo(String? value) {
    if (value == null || value.isEmpty) return 'El correo es obligatorio.';
    if (!correoValido.hasMatch(value)) return 'Ingresa un correo válido.';
    return null;
  }

  static String? telefono(String? value) {
    if (value == null || value.isEmpty) return 'El teléfono es obligatorio.';
    if (!telefonoValido.hasMatch(value)) {
      return 'Ingresa un teléfono válido (ej: +56912345678).';
    }
    return null;
  }

  static String? razonSocial(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Debes indicar el motivo de tu visita.';
    }
    if (value.trim().length < 5) return 'Sé más descriptivo por favor.';
    return null;
  }

  static String? requerido(String? value, {String campo = 'Este campo'}) {
    if (value == null || value.trim().isEmpty) return '$campo es obligatorio.';
    return null;
  }
}
