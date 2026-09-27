import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../auth_validators.dart';

const _allRequirements = [
  'At least 8 characters',
  'At least one lowercase letter',
  'At least one uppercase letter',
  'At least one digit',
  'At least one special character',
];

/// Live checklist of the password rules, ticking each one off as the user
/// types. Met rules turn green *and* switch to a check mark, so progress is
/// never conveyed by colour alone.
class PasswordRequirementsList extends StatelessWidget {
  const PasswordRequirementsList({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final unmet = AuthValidators.passwordRequirementIssues(password).toSet();
    final c = context.colors;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: c.backgroundSecondary.withValues(alpha: c.isDark ? 0.7 : 1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final requirement in _allRequirements)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      unmet.contains(requirement) ? Icons.circle_outlined : Icons.check_circle_rounded,
                      key: ValueKey(unmet.contains(requirement)),
                      size: 16,
                      color: unmet.contains(requirement) ? c.textMuted : c.success,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      requirement,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: unmet.contains(requirement) ? c.textSecondary : c.textPrimary,
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
