import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/device_services.dart';
import '../../services/session.dart';
import '../../services/sync_service.dart';
import '../widgets/brand.dart';
import 'shell.dart';

/// شاشة اختيار المستخدم: المالك (بالرمز أو البصمة/الوجه) أو العامل (برمزه).
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  List<AppUser> _users = [];
  AppUser? _selected;
  String _pin = '';
  String? _error;
  bool _bio = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final users = await Session.users(activeOnly: true);
    if (users.isEmpty) return;
    final bio = await BiometricService.enabled() && await BiometricService.available();
    setState(() {
      _users = users;
      _bio = bio;
      _selected = users.firstWhere((u) => u.isOwner, orElse: () => users.first);
    });
    if (bio && _selected?.isOwner == true) _biometric();
  }

  void _enter() {
    SyncService.start();
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const Shell()), (_) => false);
  }

  Future<void> _biometric() async {
    final owner = _users.where((u) => u.isOwner).firstOrNull;
    if (owner == null) return;
    if (await BiometricService.authenticate('افتح فورتكس بالبصمة أو الوجه')) {
      await Session.loginBiometric(owner);
      if (mounted) _enter();
    }
  }

  Future<void> _tap(String d) async {
    if (_selected == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _error = null;
      if (d == '<') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < 12) {
        _pin += d;
      }
    });
  }

  Future<void> _submit() async {
    if (_selected == null || _pin.isEmpty) return;
    final ok = await Session.login(_selected!, _pin);
    if (ok) {
      if (mounted) _enter();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _pin = '';
        _error = 'الرمز غير صحيح';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VColors.navy,
      body: SafeArea(
        child: Column(children: [
          const SizedBox(height: 24),
          const VortexLogo(size: 56),
          const SizedBox(height: 12),
          Text(Session.shop?.name ?? 'فورتكس للمحاسبة',
              style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('اختر المستخدم وأدخل الرمز', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 16),
          SizedBox(
            height: 92,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final u in _users)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _selected = u;
                        _pin = '';
                        _error = null;
                      }),
                      child: Column(children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: _selected?.id == u.id ? VColors.blue : Colors.white12,
                          child: Icon(u.isOwner ? Icons.workspace_premium_outlined : Icons.badge_outlined, color: Colors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(u.name,
                            style: TextStyle(
                                color: _selected?.id == u.id ? Colors.white : Colors.white60,
                                fontWeight: FontWeight.w600)),
                        Text(u.isOwner ? 'المالك' : 'عامل', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ]),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _pin.length.clamp(_selected?.isOwner == true ? 6 : 4, 12),
              (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? VColors.blueBright : Colors.white24,
                ),
              ),
            ),
          ),
          SizedBox(
            height: 28,
            child: _error == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(color: VColors.coralSoft)),
                  ),
          ),
          const Spacer(),
          _pad(),
          const SizedBox(height: 16),
        ]),
      ),
    );
  }

  Widget _pad() {
    Widget key(String label, {IconData? icon, VoidCallback? onTap}) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: AspectRatio(
              aspectRatio: 1.6,
              child: Material(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap ?? () => _tap(label),
                  child: Center(
                    child: icon != null
                        ? Icon(icon, color: Colors.white, size: 26)
                        : Text(label, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ),
          ),
        );

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    final showBio = _bio && _selected?.isOwner == true;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(children: [
          for (final r in rows) Row(children: [for (final d in r) key(d)]),
          Row(children: [
            key('<', icon: Icons.backspace_outlined),
            key('0'),
            key('ok', icon: Icons.check_circle, onTap: _submit),
          ]),
          if (showBio)
            TextButton.icon(
              onPressed: _biometric,
              icon: const Icon(Icons.fingerprint, color: Colors.white),
              label: const Text('الدخول بالبصمة أو الوجه', style: TextStyle(color: Colors.white)),
            ),
        ]),
      ),
    );
  }
}
