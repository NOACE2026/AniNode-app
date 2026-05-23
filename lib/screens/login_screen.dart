import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../theme/cp.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text.trim();
    if (u.isEmpty || p.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username and password required')),
      );
      return;
    }
    await ref.read(authProvider.notifier).login(u, p);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 700;

    return Scaffold(
      backgroundColor: CP.bg,
      body: Stack(
        children: [
          // Grid background
          const Positioned.fill(child: _GridBackground()),
          // Glow orbs
          Positioned(
            top: -120,
            left: -80,
            child: _GlowOrb(color: CP.cyan, size: 320),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _GlowOrb(color: CP.magenta, size: 260),
          ),
          // Main content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 0 : 28,
                  vertical: 40,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Logo
                      _Logo(),
                      const SizedBox(height: 8),
                      Text(
                        'SYSTEM ACCESS REQUIRED',
                        style: CP.mono(size: 11, color: CP.textDim),
                      ),
                      const SizedBox(height: 48),

                      // Divider line
                      CP.neonDivider(color: CP.cyan, opacity: 0.4),
                      const SizedBox(height: 32),

                      // Username
                      _FieldLabel('USERNAME'),
                      const SizedBox(height: 8),
                      _CyberField(
                        controller: _userCtrl,
                        hint: 'Enter identifier',
                        icon: Icons.person_outline_rounded,
                      ),
                      const SizedBox(height: 20),

                      // Password
                      _FieldLabel('PASSWORD'),
                      const SizedBox(height: 8),
                      _CyberField(
                        controller: _passCtrl,
                        hint: 'Enter access key',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscure,
                        onToggle: () => setState(() => _obscure = !_obscure),
                      ),

                      // Error
                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: CP.magenta, size: 14),
                            const SizedBox(width: 6),
                            Text(auth.errorMessage!,
                                style: CP.mono(size: 11, color: CP.magenta)),
                          ],
                        ),
                      ],

                      const SizedBox(height: 40),
                      CP.neonDivider(color: CP.cyan, opacity: 0.2),
                      const SizedBox(height: 32),

                      // Login button
                      _LoginButton(
                        loading: auth.isLoading,
                        onTap: _login,
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: Text(
                          '[ ANINODE v3.0.0 — RESTRICTED ACCESS ]',
                          style: CP.mono(size: 10, color: CP.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Logo ─────────────────────────────────────────────────────────────────────

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 5,
              height: 40,
              decoration: BoxDecoration(
                color: CP.cyan,
                boxShadow: CP.glow(CP.cyan, r: 12),
              ),
            ),
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (b) => const LinearGradient(
                colors: [CP.cyan, Color(0xFF00AACC)],
              ).createShader(b),
              child: Text(
                'ANINODE',
                style: CP.orbitron(size: 42, weight: FontWeight.w900).copyWith(
                  shadows: [
                    Shadow(color: CP.cyan.withValues(alpha: 0.6), blurRadius: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: CP.mono(size: 11, color: CP.textDim),
      );
}

// ── Cyber text field ──────────────────────────────────────────────────────────

class _CyberField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscure;
  final VoidCallback? onToggle;

  const _CyberField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.onToggle,
  });

  @override
  State<_CyberField> createState() => _CyberFieldState();
}

class _CyberFieldState extends State<_CyberField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _focused ? CP.cyan : CP.cyan.withValues(alpha: 0.2);
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: CP.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
          boxShadow: _focused ? CP.glow(CP.cyan, r: 10, a: 0.2) : null,
        ),
        child: TextField(
          controller: widget.controller,
          obscureText: widget.obscure,
          style: CP.mono(size: 14, color: CP.text),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: CP.mono(size: 13, color: CP.textMuted),
            prefixIcon: Icon(widget.icon, color: CP.textDim, size: 18),
            suffixIcon: widget.onToggle != null
                ? IconButton(
                    icon: Icon(
                      widget.obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: CP.textDim,
                      size: 18,
                    ),
                    onPressed: widget.onToggle,
                  )
                : null,
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
        ),
      ),
    );
  }
}

// ── Login button ──────────────────────────────────────────────────────────────

class _LoginButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onTap;
  const _LoginButton({required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: CP.cyan.withValues(alpha: loading ? 0.06 : 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: CP.cyan.withValues(alpha: loading ? 0.2 : 0.7),
          ),
          boxShadow: loading ? null : CP.glow(CP.cyan, r: 16, a: 0.3),
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: CP.cyan.withValues(alpha: 0.6),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.login_rounded, color: CP.cyan, size: 18,
                        shadows: [Shadow(color: CP.cyan.withValues(alpha: 0.8), blurRadius: 10)]),
                    const SizedBox(width: 10),
                    Text('AUTHENTICATE',
                        style: CP.orbitron(size: 12, color: CP.cyan)),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Grid background ───────────────────────────────────────────────────────────

class _GridBackground extends StatelessWidget {
  const _GridBackground();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = CP.cyan.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Glow orb ──────────────────────────────────────────────────────────────────

class _GlowOrb extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowOrb({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.04),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 80, spreadRadius: 30),
        ],
      ),
    );
  }
}
