import 'package:expense_tracker/core/theme/app_theme.dart';
import 'package:expense_tracker/features/theme/cubit/theme_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ThemeSettingsPage extends StatelessWidget {
  const ThemeSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Theme settings'),
            actions: [
              TextButton(
                onPressed: () => context.read<ThemeCubit>().resetDefaults(),
                child: const Text('Reset'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              DropdownButtonFormField<ThemeFamily>(
                initialValue: state.family,
                decoration: const InputDecoration(labelText: 'Theme family'),
                items: ThemeFamily.values
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(_familyLabel(f)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) {
                    context.read<ThemeCubit>().setFamily(value);
                  }
                },
              ),
              const SizedBox(height: 16),
              SegmentedButton<ThemeVariant>(
                segments: ThemeVariant.values
                    .map(
                      (v) => ButtonSegment(
                        value: v,
                        label: Text(_variantLabel(v)),
                      ),
                    )
                    .toList(growable: false),
                selected: {state.variant},
                onSelectionChanged: (selection) {
                  context.read<ThemeCubit>().setVariant(selection.first);
                },
              ),
              const SizedBox(height: 20),
              Text(
                'Live preview',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              _PreviewCard(state: state),
              if (state.variant == ThemeVariant.custom) ...[
                const SizedBox(height: 20),
                Text(
                  'Custom accent',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: const [
                    _AccentButton(Color(0xFF26A17B)),
                    _AccentButton(Color(0xFF7AA2F7)),
                    _AccentButton(Color(0xFFFF6B6B)),
                    _AccentButton(Color(0xFFE8A317)),
                    _AccentButton(Color(0xFF9D7CFF)),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _familyLabel(ThemeFamily family) {
    return switch (family) {
      ThemeFamily.splitwise => 'Splitwise',
      ThemeFamily.tokyoNight => 'Tokyo Night',
      ThemeFamily.mint => 'Mint',
    };
  }

  static String _variantLabel(ThemeVariant variant) {
    return switch (variant) {
      ThemeVariant.light => 'Light',
      ThemeVariant.dark => 'Dark',
      ThemeVariant.highContrast => 'High Contrast',
      ThemeVariant.custom => 'Custom',
    };
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state});

  final ThemeState state;

  @override
  Widget build(BuildContext context) {
    final previewTheme = AppThemeFactory.build(state);
    final colors = previewTheme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${state.family.name} • ${state.variant.name}',
              style: previewTheme.textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _ColorSwatchBox(label: 'Primary', color: colors.primary),
                const SizedBox(width: 10),
                _ColorSwatchBox(label: 'Secondary', color: colors.secondary),
                const SizedBox(width: 10),
                _ColorSwatchBox(label: 'Surface', color: colors.surface),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatchBox extends StatelessWidget {
  const _ColorSwatchBox({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.black12),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AccentButton extends StatelessWidget {
  const _AccentButton(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.read<ThemeCubit>().setCustomAccent(color),
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
