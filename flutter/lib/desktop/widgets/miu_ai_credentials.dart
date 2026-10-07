import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

base class _FileTime extends Struct {
  @Uint32()
  external int low;

  @Uint32()
  external int high;
}

base class _Credential extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Utf16> targetName;
  external Pointer<Utf16> comment;
  external _FileTime lastWritten;

  @Uint32()
  external int blobSize;

  external Pointer<Uint8> blob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;
  external Pointer<Utf16> targetAlias;
  external Pointer<Utf16> userName;
}

typedef _CredReadNative = Int32 Function(
    Pointer<Utf16>, Uint32, Uint32, Pointer<Pointer<_Credential>>);
typedef _CredReadDart = int Function(
    Pointer<Utf16>, int, int, Pointer<Pointer<_Credential>>);
typedef _CredWriteNative = Int32 Function(Pointer<_Credential>, Uint32);
typedef _CredWriteDart = int Function(Pointer<_Credential>, int);
typedef _CredDeleteNative = Int32 Function(Pointer<Utf16>, Uint32, Uint32);
typedef _CredDeleteDart = int Function(Pointer<Utf16>, int, int);
typedef _CredFreeNative = Void Function(Pointer<Void>);
typedef _CredFreeDart = void Function(Pointer<Void>);

class MiuAiCredentialStore {
  static const targetName = 'MiuAI/DeepSeekApiKey';
  static const _generic = 1;
  static const _localMachine = 2;

  MiuAiCredentialStore({this.target = targetName});

  final String target;
  static final DynamicLibrary? _library =
      Platform.isWindows ? DynamicLibrary.open('advapi32.dll') : null;

  DynamicLibrary get _advapi32 {
    final library = _library;
    if (library == null) throw UnsupportedError('仅支持 Windows 凭据管理器');
    return library;
  }

  String? read() {
    final targetPtr = target.toNativeUtf16();
    final result = calloc<Pointer<_Credential>>();
    try {
      final read =
          _advapi32.lookupFunction<_CredReadNative, _CredReadDart>('CredReadW');
      if (read(targetPtr, _generic, 0, result) == 0) return null;
      final credential = result.value.ref;
      if (credential.blobSize == 0 || credential.blob == nullptr) return null;
      return utf8.decode(credential.blob.asTypedList(credential.blobSize));
    } finally {
      if (result.value != nullptr) {
        _advapi32.lookupFunction<_CredFreeNative, _CredFreeDart>('CredFree')(
            result.value.cast<Void>());
      }
      calloc.free(result);
      calloc.free(targetPtr);
    }
  }

  void write(String key) {
    final value = key.trim();
    final bytes = utf8.encode(value);
    if (bytes.isEmpty || bytes.length > 2048) {
      throw const FormatException('API Key 长度无效');
    }
    final targetPtr = target.toNativeUtf16();
    final userPtr = 'Miu AI'.toNativeUtf16();
    final blob = calloc<Uint8>(bytes.length);
    final credential = calloc<_Credential>();
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      credential.ref
        ..flags = 0
        ..type = _generic
        ..targetName = targetPtr
        ..comment = nullptr
        ..blobSize = bytes.length
        ..blob = blob
        ..persist = _localMachine
        ..attributeCount = 0
        ..attributes = nullptr
        ..targetAlias = nullptr
        ..userName = userPtr;
      final write = _advapi32
          .lookupFunction<_CredWriteNative, _CredWriteDart>('CredWriteW');
      if (write(credential, 0) == 0) {
        throw StateError('无法将 API Key 保存到 Windows 凭据管理器');
      }
    } finally {
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(credential);
      calloc.free(blob);
      calloc.free(userPtr);
      calloc.free(targetPtr);
    }
  }

  void delete() {
    final targetPtr = target.toNativeUtf16();
    try {
      final delete = _advapi32
          .lookupFunction<_CredDeleteNative, _CredDeleteDart>('CredDeleteW');
      delete(targetPtr, _generic, 0);
    } finally {
      calloc.free(targetPtr);
    }
  }
}
