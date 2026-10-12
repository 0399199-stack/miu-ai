using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;

// Native composition controls the desktop reveal independently of WebView2 alpha.
internal sealed class ReadySurface : Viewbox
{
    internal ReadySurface(string color)
    {
        HorizontalAlignment = HorizontalAlignment.Center;
        VerticalAlignment = VerticalAlignment.Center;
        Stretch = Stretch.Uniform;
        Opacity = 0;
        IsHitTestVisible = false;
        Effect = new DropShadowEffect { Color = Colors.Black, Opacity = .55, BlurRadius = 20, ShadowDepth = 2 };
        var accent = (Color)ColorConverter.ConvertFromString(color);
        var accentBrush = new SolidColorBrush(accent);
        var font = new FontFamily(new Uri(AppDomain.CurrentDomain.BaseDirectory), "./web/assets/fonts/#Miu Circuit");
        var stack = new StackPanel { Width = 850 };
        stack.Children.Add(new TextBlock {
            Text = "EVERYTHING IN ITS PLACE.", FontFamily = font, FontSize = 11,
            FontWeight = FontWeights.Medium, Foreground = accentBrush,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 26)
        });
        var title = new StackPanel { HorizontalAlignment = HorizontalAlignment.Center };
        title.Children.Add(new TextBlock {
            Text = "Miu AI", FontFamily = font, FontSize = 42,
            FontWeight = FontWeights.Bold, Foreground = accentBrush,
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 8)
        });
        title.Children.Add(new TextBlock {
            Text = "READY", FontFamily = font, FontSize = 112,
            FontWeight = FontWeights.Bold, Foreground = accentBrush, HorizontalAlignment = HorizontalAlignment.Center
        });
        stack.Children.Add(title);
        stack.Children.Add(new Border {
            Width = 135, Height = 1, Margin = new Thickness(0, 28, 0, 28),
            Background = new LinearGradientBrush(new GradientStopCollection {
                new GradientStop(Colors.Transparent, 0), new GradientStop(accent, .5), new GradientStop(Colors.Transparent, 1)
            }, 0)
        });
        stack.Children.Add(new TextBlock {
            Text = "Miu AI已就绪，陪你开始今天", FontFamily = new FontFamily("Microsoft YaHei UI"),
            FontSize = 18, Foreground = accentBrush, HorizontalAlignment = HorizontalAlignment.Center
        });
        Child = stack;
        RenderTransformOrigin = new Point(.5, .5);
        RenderTransform = new ScaleTransform(.97, .97);
    }

    internal void Play()
    {
        var ease = new QuinticEase { EasingMode = EasingMode.EaseInOut };
        var opacity = new DoubleAnimationUsingKeyFrames();
        opacity.KeyFrames.Add(new DiscreteDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(.9))));
        opacity.KeyFrames.Add(new EasingDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(1.7)), ease));
        opacity.KeyFrames.Add(new DiscreteDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(2.9))));
        opacity.KeyFrames.Add(new EasingDoubleKeyFrame(0, KeyTime.FromTimeSpan(TimeSpan.FromSeconds(4)), ease));
        BeginAnimation(OpacityProperty, opacity);
        var scale = new DoubleAnimation(.97, 1.035, TimeSpan.FromSeconds(4)) { EasingFunction = ease };
        RenderTransform.BeginAnimation(ScaleTransform.ScaleXProperty, scale);
        RenderTransform.BeginAnimation(ScaleTransform.ScaleYProperty, scale);
    }
}
