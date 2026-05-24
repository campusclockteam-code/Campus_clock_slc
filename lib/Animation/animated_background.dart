// animated_background.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

class ParticleData {
  double x, y, size, speed, opacity;
  ParticleData({required this.x, required this.y, required this.size, required this.speed, required this.opacity});
}

class AnimatedBackground extends StatefulWidget {
  final Widget child;
  const AnimatedBackground({super.key, required this.child});

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with SingleTickerProviderStateMixin {
  late AnimationController _particleController;
  List<ParticleData> _particles = [];

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _initParticles();
  }

  void _initParticles() {
    for (int i = 0; i < 25; i++) {
      _particles.add(ParticleData(
        x: math.Random().nextDouble() * 100,
        y: math.Random().nextDouble() * 100,
        size: math.Random().nextDouble() * 3 + 1,
        speed: math.Random().nextDouble() * 0.5 + 0.1,
        opacity: math.Random().nextDouble() * 0.3 + 0.1,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient background
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F1B2F), Color(0xFF1E3C72), Color(0xFF2A5298)],
            ),
          ),
        ),
        // Particles
        ..._particles.map((p) {
          final offset = _particleController.value * p.speed;
          return Positioned(
            left: (p.x + offset) % MediaQuery.of(context).size.width,
            top: (p.y + offset * 0.5) % MediaQuery.of(context).size.height,
            child: Opacity(
              opacity: p.opacity,
              child: Container(
                width: p.size,
                height: p.size,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              ),
            ),
          );
        }).toList(),
        // Content
        widget.child,
      ],
    );
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }
}
