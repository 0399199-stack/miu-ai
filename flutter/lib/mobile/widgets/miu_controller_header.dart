import 'package:flutter/material.dart';

class MiuControllerHeader extends StatelessWidget {
  const MiuControllerHeader({super.key, required this.onPair});
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12, bottom: 16),
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFF12254B), Color(0xFF235FC8)]),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Miu AI', style: TextStyle(color: Colors.white,
          fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: 1)),
      const SizedBox(height: 8),
      const Text('你的电脑，随手掌控', style: TextStyle(color: Colors.white, fontSize: 17)),
      const SizedBox(height: 8),
      const Text('输入 Windows 电脑的设备 ID，开始安全连接。',
          style: TextStyle(color: Color(0xFFCCDFFF), height: 1.5)),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: onPair,
        style: OutlinedButton.styleFrom(foregroundColor: Colors.white,
            backgroundColor: const Color(0xFF163A73),
            side: const BorderSide(color: Color(0xFF9BBFFF))),
        icon: const Icon(Icons.key_rounded, size: 18), label: const Text('首次配对密钥')),
    ]),
  );
}
