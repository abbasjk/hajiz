import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/colors.dart';

/// اختيار الجنس عند التسجيل: ذكر أو أنثى، إجباري.
/// يحدد أي صالونات تظهر أولاً في الرئيسية.
class GenderField extends FormField<String> {
  GenderField({super.key, super.onSaved, ValueChanged<String>? onChanged})
      : super(
          validator: (v) => v == null ? '' : null,
          builder: (state) {
            final l = AppLocalizations.of(state.context);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.genderLabel, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Row(children: [
                for (final (value, label, icon) in [('male', l.genderMale, Icons.face), ('female', l.genderFemale, Icons.face_3)]) ...[
                  if (value == 'female') const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      avatar: Icon(icon, size: 18, color: state.value == value ? Colors.white : AppColors.primary),
                      label: Text(label),
                      selected: state.value == value,
                      showCheckmark: false,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: state.value == value ? Colors.white : AppColors.primary,
                      ),
                      onSelected: (_) {
                        state.didChange(value);
                        onChanged?.call(value);
                      },
                    ),
                  ),
                ],
              ]),
              if (state.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(l.genderRequired, style: const TextStyle(fontSize: 12, color: AppColors.danger)),
                ),
            ]);
          },
        );
}
