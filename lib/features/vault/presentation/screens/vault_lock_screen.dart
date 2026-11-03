import 'package:flutter/material.dart';

import '../../../../core/design_tokens.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/repositories/vault_repository.dart';

/// `/vault` — the epic's one lock screen, shown whenever
/// `VaultRepository.currentStatus` isn't `VaultStatus.unlocked`
/// (`core/navigation/app_router.dart`'s `_redirect`). Auto-triggers the OS
/// biometric prompt once in [initState]; a successful
/// [VaultRepository.authenticate] call flips `currentStatus` to `unlocked`,
/// which — via `statusStream`/`refreshListenable` — re-runs the redirect and
/// navigates away from here on its own, so this widget never navigates
/// imperatively itself. No PIN entry UI (Story 2.2).
class VaultLockScreen extends StatefulWidget {
  const VaultLockScreen({required this.vaultRepository, super.key});

  final VaultRepository vaultRepository;

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  bool _authenticating = false;
  bool _showRetry = false;

  @override
  void initState() {
    super.initState();
    _attemptAuthenticate();
  }

  Future<void> _attemptAuthenticate() async {
    if (_authenticating) {
      return;
    }
    setState(() {
      _authenticating = true;
      _showRetry = false;
    });

    final result = await widget.vaultRepository.authenticate();
    if (!mounted) {
      return;
    }

    // On success, `currentStatus` is already `unlocked` and the router's
    // own `refreshListenable` will navigate away from `/vault` on its own —
    // this widget has nothing further to do (and may already be in the
    // process of being disposed by the time that happens).
    result.match(
      (_) => setState(() {
        _authenticating = false;
        _showRetry = true;
      }),
      (_) => setState(() {
        _authenticating = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Center(
        child: Padding(
          padding: DesignTokens.screenPadding,
          // `liveRegion: true` so a screen reader announces the subtree's
          // content whenever it changes — in particular the "autenticando"
          // -> retry-button transition below (_showRetry flipping true),
          // instead of staying silent about that state change.
          child: Semantics(
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: DesignTokens.spacing2xl,
                  color: DesignTokens.colorTextSecondary,
                ),
                const SizedBox(height: DesignTokens.spacingMd),
                Text(
                  'Cerne bloqueado',
                  textAlign: TextAlign.center,
                  style: DesignTokens.textHeadlineMd.copyWith(
                    color: DesignTokens.colorTextPrimary,
                  ),
                ),
                const SizedBox(height: DesignTokens.spacingSm),
                Text(
                  'Use a biometria do seu dispositivo para continuar.',
                  textAlign: TextAlign.center,
                  style: DesignTokens.textBodyMd.copyWith(
                    color: DesignTokens.colorTextSecondary,
                  ),
                ),
                if (_showRetry) ...[
                  const SizedBox(height: DesignTokens.spacingLg),
                  AppButton(
                    label: 'Tentar novamente',
                    onPressed: _attemptAuthenticate,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
