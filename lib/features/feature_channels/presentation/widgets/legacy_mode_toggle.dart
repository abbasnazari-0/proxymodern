import 'package:flutter/material.dart';

class LegacyModeToggle extends StatelessWidget {
  const LegacyModeToggle({
    super.key,
    required this.enabled,
    required this.onChanged,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;

  static const _accent = Color(0xFF3DDC97);
  static const _muted = Color(0xFF8B97A6);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: enabled ? "حالت لیست فعال است" : "حالت لیست غیرفعال است",
      child: Material(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => onChanged(!enabled),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "لیست",
                  style: TextStyle(
                    fontFamily: "vazir",
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: enabled ? _accent : _muted,
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  height: 22,
                  child: Switch(
                    value: enabled,
                    onChanged: onChanged,
                    activeThumbColor: _accent,
                    activeTrackColor: _accent.withValues(alpha: 0.35),
                    inactiveThumbColor: Colors.white54,
                    inactiveTrackColor: const Color(0xFF243140),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
