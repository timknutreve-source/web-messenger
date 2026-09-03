import 'package:flutter/material.dart';

import '../auth_validators.dart';

const _allRequirements = [
  'At least 8 characters',
  'At least one lowercase letter',
  'At least one uppercase letter',
  'At least one digit',
  'At least one special character',
];

/// Live checklist of the password rules, ticking each one off as the user types.
class PasswordRequirementsList extends StatelessWidget {
  const PasswordRequirementsList({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final unmet = AuthValidators.passwordRequirementIssues(password).toSet();
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final requirement in _allRequirements)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  unmet.contains(requirement) ? Icons.circle_outlined : Icons.check_circle,
                  size: 16,
                  color: unmet.contains(requirement)
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(requirement, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
