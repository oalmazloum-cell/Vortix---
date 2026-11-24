import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';

/// شعار فورتكس.
class VortexLogo extends StatelessWidget {
  const VortexLogo({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [VColors.blueBright, VColors.blue],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(size * 0.3),
          boxShadow: [BoxShadow(color: VColors.blue.withValues(alpha: 0.4), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Icon(Icons.cyclone, color: Colors.white, size: size * 0.6),
      );
}
