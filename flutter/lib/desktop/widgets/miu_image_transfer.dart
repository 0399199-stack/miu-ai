import 'dart:async';
import 'dart:io';

import 'package:flutter_hbb/models/file_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:image/image.dart' as image;
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'miu_remote_task_executor.dart';

const miuImageMaxBytes = 25 * 1024 * 1024;
const _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.webp',
  '.gif',
  '.bmp'
};

String miuImageExtension(String filePath) {
  final extension = path.extension(filePath).toLowerCase();
  if (!_imageExtensions.contains(extension)) {
    throw const FormatException('请选择 PNG、JPG、WebP、GIF 或 BMP 图片');
  }
  return extension;
}

String miuRemoteImagePath(String home, String extension, String uniqueId) {
  if (home.isEmpty || !path.windows.isAbsolute(home)) {
    throw const FormatException('无法确定 B 机的图片保存位置');
  }
  if (!_imageExtensions.contains(extension) ||
      !RegExp(r'^[0-9a-f]{32}$').hasMatch(uniqueId)) {
    throw const FormatException('图片文件名无效');
  }
  return path.windows.join(home, 'MiuAI-$uniqueId$extension');
}

Future<void> validateMiuImageFile(File file) async {
  miuImageExtension(file.path);
  if (!await file.exists()) throw const FormatException('图片文件不存在');
  final size = await file.length();
  if (size == 0 || size > miuImageMaxBytes) {
    throw const FormatException('图片必须小于 25 MB');
  }
  final bytes = await file.readAsBytes();
  final header = image.findDecoderForData(bytes)?.startDecode(bytes);
  if (header == null ||
      header.width < 1 ||
      header.height < 1 ||
      header.width > 12000 ||
      header.height > 12000) {
    throw const FormatException('无法读取图片或图片尺寸过大');
  }
}

/// Transfers the original image through RustDesk's file-transfer connection.
/// The remote file is opened only after the transfer job reports completion.
Future<String> sendAndOpenMiuImage({
  required FFI controller,
  required File source,
  void Function(double)? onProgress,
}) async {
  if (controller.closed ||
      controller.connType != ConnType.defaultConn ||
      !controller.ffiModel.miuPeerAuthenticated ||
      !controller.ffiModel.isPeerWindows) {
    throw StateError('请先连接 Windows 被控设备');
  }
  if (controller.ffiModel.permissions['file'] == false) {
    throw StateError('B 机未授权文件传输');
  }
  if (!controller.ffiModel.keyboard) {
    throw StateError('B 机未授权打开图片所需的任务权限');
  }
  await validateMiuImageFile(source);
  final token = bind.sessionGetConnToken(sessionId: controller.sessionId);
  if (token == null || token.isEmpty) {
    throw StateError('当前连接没有可复用的配对凭证');
  }

  final transfer = FFI(null);
  final ready = Completer<String>();
  final completed = Completer<String?>();
  StreamSubscription<FileDirectory>? directorySubscription;
  StreamSubscription<List<JobProgress>>? jobSubscription;
  void checkReady() {
    if (ready.isCompleted || !transfer.ffiModel.miuPeerAuthenticated) return;
    final remote = transfer.fileModel.remoteController;
    final home = remote.homePath.isNotEmpty
        ? remote.homePath
        : remote.directory.value.path;
    if (home.isNotEmpty) ready.complete(home);
  }

  void failConnection(String message) {
    if (!ready.isCompleted) {
      ready.completeError(StateError(message));
    } else if (!completed.isCompleted) {
      completed.complete(message);
    }
  }

  transfer.onTaskConnectionError = failConnection;
  transfer.ffiModel.addListener(checkReady);
  directorySubscription =
      transfer.fileModel.remoteController.directory.listen((_) => checkReady());
  try {
    transfer.start(controller.id, isFileTransfer: true, connToken: token);
    final home = await ready.future.timeout(const Duration(seconds: 40));
    final extension = miuImageExtension(source.path);
    final remotePath = miuRemoteImagePath(
        home, extension, const Uuid().v4().replaceAll('-', ''));
    final jobController = transfer.fileModel.jobController;
    final localEntry = Entry()
      ..path = source.path
      ..name = path.basename(source.path)
      ..size = await source.length();
    final jobId = jobController.addTransferJob(localEntry, false);
    jobSubscription = jobController.jobTable.listen((jobs) {
      if (completed.isCompleted) return;
      final matches = jobs.where((job) => job.id == jobId);
      if (matches.isEmpty) return;
      final job = matches.first;
      onProgress?.call(job.percent.clamp(0.0, 1.0));
      if (job.state == JobState.error || job.err.isNotEmpty) {
        completed.complete(
            job.err.isEmpty ? 'B 机未接收图片' : 'B 机未接收图片：${job.err}');
      } else if (job.state == JobState.done) {
        completed.complete(null);
      }
    });
    jobController.registerTransferConflictBatch([jobId]);
    await bind.sessionSendFiles(
      sessionId: transfer.sessionId,
      actId: jobId,
      path: source.path,
      to: remotePath,
      fileNum: 0,
      includeHidden: false,
      isRemote: false,
      isDir: false,
    );
    final transferError =
        await completed.future.timeout(const Duration(minutes: 20));
    if (transferError != null) throw StateError(transferError);
    if (controller.closed || !controller.ffiModel.miuPeerAuthenticated) {
      throw StateError('远程连接已断开，图片已传送但尚未打开');
    }
    final opened = await executeMiuRemoteTask(
        controller: controller,
        kind: MiuRemoteTaskKind.program,
        value: remotePath);
    if (!opened.succeeded) {
      throw StateError('图片已保存到 B 机，但打开失败：${opened.output}');
    }
    return remotePath;
  } finally {
    await jobSubscription?.cancel();
    await directorySubscription.cancel();
    transfer.ffiModel.removeListener(checkReady);
    transfer.onTaskConnectionError = null;
    await transfer.fileModel.close();
    await transfer.close();
  }
}
