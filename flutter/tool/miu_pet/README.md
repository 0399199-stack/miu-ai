# Miu 透明宠物动画序列

本版沿用 `assets/miu_cat_head.png` 的蓝白猫头纹理，逐帧绘制眼睑、眼球、嘴型、情绪符号，左右耳朵独立轻摆。这里是正式二维序列的生成源；应用不加载 3D 模型，也不播放 GIF。

每种情绪一张 3328 × 3328 RGBA 图集，13 × 13 格，每格 256 × 256。编号：0 开心、1 眨眼、2 好奇、3 思考、4 困倦、5 惊讶、6 害羞、7 兴奋、8 疑惑、9 难过。

- 0–143：144 帧循环，60 fps，2.4 秒。
- 144–168：25 帧从开心到该情绪的连续形变。倒放用于回到开心。
- 换情绪时先到循环接缝，再播放过渡，不使用两张脸叠加淡化。
- 应用只保留当前和目标图集，最多约 85 MiB 解码像素；鼠标跟随、悬浮和兴奋位移独立响应。
- PNG 四角和猫头外侧保持 alpha 透明，图集打包不缩放、不加背景。

在 `flutter` 目录中，使用项目的 Flutter 3.24.5 和装有 Pillow 的 Python：

```powershell
flutter test --no-pub tool/miu_pet/generate_sequences.dart
python tool/miu_pet/pack_sequences.py build/miu-pet-frames assets/miu_pet_sequences
```

生成器借助 Flutter 的离屏绘制输出真实帧，不需要打开桌面窗口。生成后应检查眨眼帧、循环首尾、过渡首尾和透明边缘；生成动作与运行时播放器的帧数/图集尺寸须同步更新。
