import 'dart:async';

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../widgets/back_arrow_header.dart';

/// Shown while `SessionRepository.statusStream` has no data yet. Moved
/// verbatim from `main.dart`'s old `_BootLoadingScreen` (Story 1.4):
/// blank for the happy path (RNF01: no loading UI below 300ms), but
/// surfaces a centered spinner once the wait crosses that threshold.
class BootSplashScreen extends StatefulWidget {
  const BootSplashScreen({super.key});

  @override
  State<BootSplashScreen> createState() => _BootSplashScreenState();
}

class _BootSplashScreenState extends State<BootSplashScreen> {
  static const _threshold = Duration(milliseconds: 300);

  bool _showIndicator = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_threshold, () {
      if (mounted) {
        setState(() => _showIndicator = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Center(
        child: _showIndicator
            ? const CircularProgressIndicator(color: DesignTokens.colorPrimary)
            : const SizedBox.shrink(),
      ),
    );
  }
}

/// Throwaway placeholder — Epic 2's biometric/PIN re-auth flow deletes this
/// wholesale (moved verbatim from `main.dart`'s old
/// `_BiometricReauthPlaceholder`, Story 1.5). Exists only so the expiry
/// overlay's "Entrar novamente" has somewhere to route to (`/reauth`).
class BiometricReauthPlaceholderScreen extends StatelessWidget {
  const BiometricReauthPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: const Center(
        child: Text('Biometria', style: DesignTokens.textHeadlineMd),
      ),
    );
  }
}

/// Tela 5 — Planos de Ação **[ext]**. An explicit, never-implemented
/// extension feature (AGENTS.md: "a menu entry may exist as a placeholder,
/// nothing functional behind it") — the prototype's exact static 3-column
/// kanban, zero backend calls, zero drag/drop.
class ActionPlansPlaceholderScreen extends StatelessWidget {
  const ActionPlansPlaceholderScreen({super.key});

  static const List<_KanbanColumnData> _columns = [
    _KanbanColumnData(
      title: 'A Fazer',
      dotColor: DesignTokens.colorSecondary,
      cards: ['Organizar registros da semana', 'Revisar metas do mês'],
    ),
    _KanbanColumnData(
      title: 'Em Andamento',
      dotColor: DesignTokens.colorAccent,
      cards: ['Praticar escrita livre 3x por semana'],
    ),
    _KanbanColumnData(
      title: 'Concluído',
      dotColor: DesignTokens.colorSuccess,
      cards: ['Configurar lembretes diários', 'Primeira semana de registros'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.colorSurfaceBg,
      body: Column(
        children: [
          const BackArrowHeader(title: 'Planos de Ação'),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: DesignTokens.kanbanBoardPadding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < _columns.length; i++) ...[
                    _KanbanColumn(data: _columns[i]),
                    if (i < _columns.length - 1)
                      const SizedBox(width: DesignTokens.kanbanColumnGap),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KanbanColumnData {
  const _KanbanColumnData({
    required this.title,
    required this.dotColor,
    required this.cards,
  });

  final String title;
  final Color dotColor;
  final List<String> cards;
}

class _KanbanColumn extends StatelessWidget {
  const _KanbanColumn({required this.data});

  final _KanbanColumnData data;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DesignTokens.kanbanColumnMinWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: DesignTokens.kanbanDotSize,
                height: DesignTokens.kanbanDotSize,
                decoration: BoxDecoration(
                  color: data.dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Expanded(
                child: Text(
                  data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DesignTokens.textLabelMd.copyWith(
                    color: DesignTokens.colorTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: DesignTokens.spacingSm),
              Text(
                '${data.cards.length}',
                style: DesignTokens.textMonoCaption.copyWith(
                  color: DesignTokens.colorTextSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: DesignTokens.kanbanColumnHeaderGap),
          for (var i = 0; i < data.cards.length; i++) ...[
            _KanbanCard(text: data.cards[i], spineColor: data.dotColor),
            if (i < data.cards.length - 1)
              const SizedBox(height: DesignTokens.spacingSm),
          ],
        ],
      ),
    );
  }
}

class _KanbanCard extends StatelessWidget {
  const _KanbanCard({required this.text, required this.spineColor});

  final String text;
  final Color spineColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: DesignTokens.colorSurfaceElevated,
        borderRadius: BorderRadius.all(Radius.circular(DesignTokens.radiusMd)),
        boxShadow: DesignTokens.elevation1,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(
          Radius.circular(DesignTokens.radiusMd),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: DesignTokens.kanbanCardSpineWidth,
              child: ColoredBox(color: spineColor),
            ),
            Padding(
              padding: DesignTokens.kanbanCardPadding,
              child: Text(
                text,
                style: DesignTokens.textBodyMd.copyWith(
                  color: DesignTokens.colorTextPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
