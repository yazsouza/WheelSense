import 'package:flutter/material.dart';

class LiveOverviewSection extends StatelessWidget {
  final int totalSessions;
  final int averageScore;
  final int maneuversPracticed;
  final int totalManeuvers;

  const LiveOverviewSection({
    super.key,
    required this.totalSessions,
    required this.averageScore,
    required this.maneuversPracticed,
    required this.totalManeuvers,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Overview',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: _OverviewMiniCard(
            title: 'Total Practice Sessions',
            value: '$totalSessions',
            subtitle: 'Across all maneuvers',
            icon: Icons.trending_up_rounded,
            accentColor: Colors.cyan,
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _OverviewMiniCard(
                title: 'Overall Average Score',
                value: '$averageScore%',
                subtitle: totalSessions == 0
                    ? 'Keep practicing'
                    : 'Across all tests',
                icon: Icons.military_tech_outlined,
                accentColor: Colors.teal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _OverviewMiniCard(
                title: 'Maneuvers Practiced',
                value: '$maneuversPracticed/$totalManeuvers',
                subtitle: 'Skills attempted',
                icon: Icons.adjust_rounded,
                accentColor: Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewMiniCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accentColor;

  const _OverviewMiniCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border(
            left: BorderSide(color: accentColor, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: accentColor, size: 18),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
