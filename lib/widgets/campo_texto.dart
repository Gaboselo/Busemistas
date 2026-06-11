// lib/widgets/campo_texto.dart
// TextFormField estilizado y reutilizable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String etiqueta;
  final String? hint;
  final IconData? icono;
  final bool bloqueado;
  final bool obscureText;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final int? maxLength;

  const CampoTexto({
    super.key,
    required this.controller,
    required this.etiqueta,
    this.hint,
    this.icono,
    this.bloqueado = false,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return TextFormField(
      controller: controller,
      readOnly: bloqueado,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLength: maxLength,
      validator: validator,
      onChanged: onChanged,
      style: TextStyle(
        color: bloqueado
            ? colors.onSurface.withValues(alpha: 0.5)
            : colors.onSurface,
      ),
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: hint,
        counterText: '',
        prefixIcon: icono != null ? Icon(icono) : null,
        suffixIcon: bloqueado
            ? const Tooltip(
                message: 'Este campo fue completado automáticamente.',
                child: Icon(Icons.lock_outline, size: 18),
              )
            : null,
        filled: true,
        fillColor: bloqueado
            ? colors.surfaceContainerHighest.withValues(alpha: 0.4)
            : colors.surfaceContainerHighest.withValues(alpha: 0.2),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error, width: 2),
        ),
      ),
    );
  }
}
