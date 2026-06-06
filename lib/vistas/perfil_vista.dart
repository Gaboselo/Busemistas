// lib/vistas/perfil_vista.dart
// Busemistas USM v2 — Vista de Perfil de Cuenta
// Permite (simulado): cambiar correo, teléfono y foto de perfil

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../servicios/validadores.dart';
import '../widgets/campo_texto.dart';

const Color _kAzul = Color(0xFF0E004A);

class PerfilVista extends StatefulWidget {
  const PerfilVista({super.key});

  @override
  State<PerfilVista> createState() => _PerfilVistaState();
}

class _PerfilVistaState extends State<PerfilVista> {
  final _formKey = GlobalKey<FormState>();
  final _correoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  bool _editando = false;
  bool _guardando = false;

  // Avatar seleccionado (simulado — índice de avatar predefinido)
  int _avatarIdx = 0;
  static const List<IconData> _avatares = [
    Icons.person_rounded,
    Icons.face_rounded,
    Icons.face_2_rounded,
    Icons.face_3_rounded,
    Icons.face_4_rounded,
    Icons.face_5_rounded,
    Icons.face_6_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  void _cargarDatos() {
    final auth = context.read<AuthProvider>();
    // Los datos se cargan via StreamBuilder desde Firestore
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarCambios(BuildContext context, String cedula) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(cedula)
          .update({
        'correo': _correoCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'avatar_idx': _avatarIdx,
      });

      if (!context.mounted) return;
      setState(() {
        _editando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✅ Perfil actualizado correctamente.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Error al guardar: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  void _mostrarSelectorAvatar() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Selecciona tu avatar',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16, color: _kAzul)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List.generate(_avatares.length, (i) {
                final sel = i == _avatarIdx;
                return GestureDetector(
                  onTap: () {
                    setState(() => _avatarIdx = i);
                    Navigator.pop(context);
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: sel ? _kAzul : Colors.grey.shade100,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: sel ? _kAzul : Colors.grey.shade300, width: 2),
                    ),
                    child: Icon(_avatares[i],
                        color: sel ? Colors.white : Colors.grey.shade600,
                        size: 34),
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),
            Text(
              '* En producción, aquí se integraría un selector de foto de galería/cámara.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cedula = auth.cedulaActual ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        backgroundColor: _kAzul,
        foregroundColor: Colors.white,
        actions: [
          if (!_editando)
            TextButton(
              onPressed: () => setState(() => _editando = true),
              child:
                  const Text('Editar', style: TextStyle(color: Colors.white)),
            )
          else
            TextButton(
              onPressed: () => setState(() => _editando = false),
              child: const Text('Cancelar',
                  style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(cedula)
            .snapshots(),
        builder: (context, snap) {
          Map<String, dynamic> datos = {};
          if (snap.hasData && snap.data!.exists) {
            datos = snap.data!.data() as Map<String, dynamic>;
            // Cargar en controllers si aún no editando
            if (!_editando) {
              _correoCtrl.text = datos['correo'] as String? ?? '';
              _telefonoCtrl.text = datos['telefono'] as String? ?? '';
              _avatarIdx = (datos['avatar_idx'] as int?) ?? 0;
            }
          }

          final nombre =
              datos['nombre_completo'] as String? ?? auth.nombreCompleto ?? '—';
          final rol =
              datos['rol'] as String? ?? auth.rolSeleccionado?.name ?? '—';
          final saldo = (datos['saldo'] as num?)?.toDouble() ?? 0.0;
          final mensualidad = datos['mensualidad_activa'] as bool? ?? false;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // ── Avatar ────────────────────────────────────────────
                GestureDetector(
                  onTap: _editando ? _mostrarSelectorAvatar : null,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: _kAzul,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: _kAzul.withValues(alpha: 0.4),
                                blurRadius: 16,
                                offset: const Offset(0, 6))
                          ],
                        ),
                        child: Icon(_avatares[_avatarIdx],
                            color: Colors.white, size: 52),
                      ),
                      if (_editando)
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: _kAzul, width: 2),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: _kAzul, size: 18),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Nombre
                Text(nombre,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kAzul)),
                const SizedBox(height: 4),
                _BadgeRol(rol: rol),
                const SizedBox(height: 20),

                // ── Tarjeta de saldo ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0E004A), Color(0xFF3A0CA3)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: _kAzul.withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Saldo disponible',
                                style: TextStyle(
                                    color: Colors.white60, fontSize: 12)),
                            Text('\$${saldo.toStringAsFixed(2)}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 28,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      if (mensualidad)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: Colors.greenAccent.withValues(alpha: 0.5)),
                          ),
                          child: const Column(children: [
                            Icon(Icons.card_membership,
                                color: Colors.greenAccent, size: 18),
                            SizedBox(height: 2),
                            Text('Plan activo',
                                style: TextStyle(
                                    color: Colors.greenAccent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold)),
                          ]),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Formulario de datos ───────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SeccionLabel(label: 'Información personal'),
                      const SizedBox(height: 12),

                      // Cédula (solo lectura)
                      _CampoInfo(
                          icono: Icons.badge_outlined,
                          label: 'Cédula',
                          valor: cedula),
                      const SizedBox(height: 10),

                      // Nombre (solo lectura)
                      _CampoInfo(
                          icono: Icons.person_outline,
                          label: 'Nombre completo',
                          valor: nombre),
                      const SizedBox(height: 10),

                      // Correo (editable)
                      _editando
                          ? CampoTexto(
                              controller: _correoCtrl,
                              etiqueta: 'Correo electrónico',
                              hint: 'correo@ejemplo.com',
                              icono: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              validator: Validadores.correo,
                            )
                          : _CampoInfo(
                              icono: Icons.email_outlined,
                              label: 'Correo',
                              valor: _correoCtrl.text.isEmpty
                                  ? '—'
                                  : _correoCtrl.text),
                      const SizedBox(height: 10),

                      // Teléfono (editable)
                      _editando
                          ? CampoTexto(
                              controller: _telefonoCtrl,
                              etiqueta: 'Teléfono',
                              hint: '+584141234567',
                              icono: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9+]'))
                              ],
                              validator: Validadores.telefono,
                            )
                          : _CampoInfo(
                              icono: Icons.phone_outlined,
                              label: 'Teléfono',
                              valor: _telefonoCtrl.text.isEmpty
                                  ? '—'
                                  : _telefonoCtrl.text),

                      if (_editando) ...[
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _guardando
                                ? null
                                : () => _guardarCambios(context, cedula),
                            icon: _guardando
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded),
                            label: Text(_guardando
                                ? 'Guardando...'
                                : 'Guardar Cambios'),
                            style: FilledButton.styleFrom(
                              backgroundColor: _kAzul,
                              minimumSize: const Size.fromHeight(52),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                Text(
                  '* Los cambios de nombre y cédula están bloqueados\n'
                  'por seguridad institucional.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BadgeRol extends StatelessWidget {
  final String rol;
  const _BadgeRol({required this.rol});

  @override
  Widget build(BuildContext context) {
    final icon = rol == 'conductor'
        ? Icons.drive_eta_rounded
        : rol == 'visitante'
            ? Icons.badge_outlined
            : Icons.school_rounded;
    final color = rol == 'conductor'
        ? Colors.orange
        : rol == 'visitante'
            ? Colors.grey
            : _kAzul;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            rol.substring(0, 1).toUpperCase() + rol.substring(1),
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _SeccionLabel extends StatelessWidget {
  final String label;
  const _SeccionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontWeight: FontWeight.bold, fontSize: 14, color: _kAzul));
  }
}

class _CampoInfo extends StatelessWidget {
  final IconData icono;
  final String label;
  final String valor;
  const _CampoInfo(
      {required this.icono, required this.label, required this.valor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icono, color: Colors.grey.shade500, size: 18),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              Text(valor,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}
