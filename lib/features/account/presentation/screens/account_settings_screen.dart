import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/back_arrow_header.dart';
import '../cubit/account_settings_cubit.dart';

/// Tela 6 — Configurações, Story 2.4's real build: a header + exactly one
/// toggle (Acceptance Criteria: "shows only the biometric toggle —
/// minimal, Epic 8 extends it, never rebuilds it"). Replaces the former
/// `ConfiguracoesPlaceholderScreen`.
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({required this.cubit, super.key});

  final AccountSettingsCubit cubit;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Review finding: clears a leftover error from a previous visit's
    // failed toggle — this cubit is a DI singleton, so without this a
    // stale message would still be showing on an unrelated later visit.
    widget.cubit.clearStaleError();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: widget.cubit,
      child: Scaffold(
        backgroundColor: DesignTokens.colorSurfaceBg,
        body: Column(
          children: [
            const BackArrowHeader(title: 'Configurações'),
            Padding(
              padding: DesignTokens.screenPadding,
              child: BlocBuilder<AccountSettingsCubit, AccountSettingsState>(
                builder: (context, state) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Entrar com biometria',
                              style: DesignTokens.textBodyLg.copyWith(
                                color: DesignTokens.colorTextPrimary,
                              ),
                            ),
                          ),
                          Switch(
                            value: state.biometricEnabled,
                            // Boundaries: "no new tokens" — reuses
                            // `colorAccent` (Design Notes).
                            activeThumbColor: DesignTokens.colorAccent,
                            // Review finding: `null` while a toggle is
                            // already in flight (`state.isSaving`) — a
                            // disabled `Switch` can't be tapped again, so
                            // a double-tap can never start a second,
                            // overlapping `toggleBiometric` call.
                            onChanged: state.isSaving
                                ? null
                                : (value) => context
                                      .read<AccountSettingsCubit>()
                                      .toggleBiometric(value),
                          ),
                        ],
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: DesignTokens.spacingSm),
                        Text(
                          state.errorMessage!,
                          style: DesignTokens.textBodyMd.copyWith(
                            color: DesignTokens.colorError,
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
