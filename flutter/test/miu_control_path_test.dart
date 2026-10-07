import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/desktop/widgets/miu_image_transfer.dart';

void main() {
  const home = r'C:\Users\Friend';
  const name = 'MiuAI-0123456789abcdef0123456789abcdef.jpg';

  test('remote image may only open from the host user home', () {
    expect(miuRemoteImagePath(home, '.jpg',
            '0123456789abcdef0123456789abcdef'), '$home\\$name');
    expect(isMiuImageInHome('$home\\$name', home), isTrue);
    expect(isMiuImageInHome('C:\\Users\\Other\\$name', home), isFalse);
    expect(isMiuImageInHome('$home\\Sub\\$name', home), isFalse);
    expect(isMiuImageInHome('$home\\Sub\\..\\$name', home), isFalse);
    expect(isMiuImageInHome('$home\\ordinary.jpg', home), isFalse);
    expect(isMiuImageInHome('$home\\$name:extra', home), isFalse);
    expect(isMiuImageInHome(name, home), isFalse);
  });
}
