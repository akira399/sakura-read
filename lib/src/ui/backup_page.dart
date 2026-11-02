import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/backup_service.dart';
import '../data/jianguoyun_login.dart';
import '../data/prefs.dart';
import '../data/webdav_client.dart';
import '../platform/native_bridge.dart';
import '../util/format.dart';
import 'widgets/cute.dart';

/// 备份与恢复：本地 zip 备份 / 指定文件恢复 / WebDAV 云备份。
///
/// 只依赖 [AppPrefs]，不碰书架等其它 Store：恢复完的旧文件由
/// [BackupService] 留成 `.bak`，页面只负责提示「重启 App 生效」。
class BackupPage extends StatefulWidget {
  const BackupPage({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<BackupPage> {
  late final BackupService _backup;

  final TextEditingController _pathCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _userCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _dirCtrl = TextEditingController();

  /// 本地能找到的备份（Download + `<files>/backups/`）。
  List<File> _localBackups = <File>[];

  /// 刚备份完的 zip 路径，显示出来方便复制。
  String? _lastSavedPath;

  bool _obscurePass = true;
  bool _backingUp = false;
  bool _restoring = false;
  bool _testingDav = false;
  bool _uploading = false;
  bool _pulling = false;

  /// 坚果云账号直连登录进行中。
  bool _loggingIn = false;

  /// 有任何一个耗时操作在跑就禁用全部按钮，避免并发读写同一批文件。
  bool get _busy =>
      _backingUp ||
      _restoring ||
      _testingDav ||
      _uploading ||
      _pulling ||
      _loggingIn;

  @override
  void initState() {
    super.initState();
    _backup = BackupService(prefs: widget.prefs);
    _urlCtrl.text = widget.prefs.webdavUrl;
    _userCtrl.text = widget.prefs.webdavUser;
    _passCtrl.text = widget.prefs.webdavPass;
    _dirCtrl.text = widget.prefs.webdavDir;
    _refreshLocal();
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _dirCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshLocal() async {
    final list = await _backup.listLocalBackups();
    if (!mounted) return;
    setState(() => _localBackups = list);
  }

  // ---------------- 本地备份 / 恢复 ----------------

  Future<void> _runBackup() async {
    if (_busy) return;
    setState(() => _backingUp = true);
    try {
      final file = await _backup.createBackup();
      if (!mounted) return;
      setState(() => _lastSavedPath = file.path);
      _toast('备份好啦～存在 ${file.path}');
      await _refreshLocal();
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('备份失败了：$e', error: true);
    } finally {
      if (mounted) setState(() => _backingUp = false);
    }
  }

  /// 从本地备份列表点进来：二次确认后恢复。
  Future<void> _restoreFile(File file) async {
    if (_busy) return;
    final ok = await _confirm(
      title: '确定要恢复吗？',
      message:
          '会用「${_fileName(file.path)}」里的内容覆盖当前的设置、书架、'
          '书签和阅读统计。\n旧文件会留一份 .bak，但恢复了就回不去啦。',
      okText: '恢复',
    );
    if (!ok) return;
    if (!mounted) return;
    setState(() => _restoring = true);
    try {
      final result = await _backup.restore(file);
      await _showRestoreResult(result);
      await _refreshLocal();
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('恢复失败了：$e', error: true);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// 手动输入 zip 路径后恢复。
  Future<void> _restoreFromPath() async {
    if (_busy) return;
    final path = _pathCtrl.text.trim();
    if (path.isEmpty) {
      _toast('先把备份 zip 的完整路径粘进来吧');
      return;
    }
    final file = File(path);
    final exists = await file.exists();
    if (!exists) {
      _toast('这个路径下没有文件，检查一下有没有打错～', error: true);
      return;
    }
    await _restoreFile(file);
  }

  Future<void> _showRestoreResult(BackupRestoreResult result) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(result.hasRestored ? '恢复完成啦 ✿' : '没能恢复'),
        content: Text(result.summary),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道啦'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    _toast('路径复制好啦，粘到文件管理器里就能找到～');
  }

  // ---------------- WebDAV ----------------

  /// 每次操作都新建 client，用完立刻关，避免 http 连接一直挂着。
  Future<T> _withDav<T>(Future<T> Function(WebdavClient dav) run) async {
    final dav = WebdavClient(
      baseUrl: _urlCtrl.text,
      user: _userCtrl.text.trim(),
      pass: _passCtrl.text,
    );
    try {
      return await run(dav);
    } finally {
      dav.close();
    }
  }

  /// 云端目录：优先用输入框里的，空就用设置里存过的。
  String _effectiveDir() {
    final typed = _normalizeDir(_dirCtrl.text);
    if (typed.isNotEmpty) return typed;
    return _normalizeDir(widget.prefs.webdavDir);
  }

  void _saveDav() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _toast('WebDAV 地址还没填呢');
      return;
    }
    final dir = _normalizeDir(_dirCtrl.text);
    widget.prefs.setWebdav(
      url: url,
      user: _userCtrl.text.trim(),
      pass: _passCtrl.text,
      dir: dir.isEmpty ? null : dir,
    );
    _dirCtrl.text = widget.prefs.webdavDir;
    _toast('WebDAV 设置存好啦～');
  }

  Future<void> _testDav() async {
    if (_busy) return;
    if (_urlCtrl.text.trim().isEmpty) {
      _toast('先填一下 WebDAV 地址吧');
      return;
    }
    setState(() => _testingDav = true);
    try {
      final ok = await _withDav((dav) => dav.testConnection());
      _toast(
        ok ? '连上啦～云端可以正常访问 ✿' : '连上了，但服务器没返回 207/200，目录可能不存在哦',
        error: !ok,
      );
    } on WebdavException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('测试失败了：$e', error: true);
    } finally {
      if (mounted) setState(() => _testingDav = false);
    }
  }

  Future<void> _uploadBackup() async {
    if (_busy) return;
    if (_urlCtrl.text.trim().isEmpty) {
      _toast('先填一下 WebDAV 地址吧');
      return;
    }
    final dir = _effectiveDir();
    setState(() => _uploading = true);
    try {
      final file = await _backup.createBackup();
      final name = _fileName(file.path);
      final remote = _joinRemote(dir, name);
      final bytes = await file.readAsBytes();
      await _withDav((dav) async {
        await dav.ensureDir(dir);
        await dav.upload(remote, bytes);
      });
      if (!mounted) return;
      setState(() => _lastSavedPath = file.path);
      _toast('云端备份完成啦～（$remote）');
      await _refreshLocal();
    } on WebdavException catch (e) {
      _toast('云端备份失败：${e.message}', error: true);
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('云端备份失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// 从云端目录挑最新的一个备份下载下来，确认后恢复。
  Future<void> _pullFromCloud() async {
    if (_busy) return;
    if (_urlCtrl.text.trim().isEmpty) {
      _toast('先填一下 WebDAV 地址吧');
      return;
    }
    final dir = _effectiveDir();
    setState(() => _pulling = true);
    try {
      final bytes = await _withDav((dav) async {
        final entries = await dav.list(dir);
        final zips =
            entries
                .where((e) => !e.isDirectory && _isBackupName(e.name))
                .toList()
              ..sort(
                (a, b) => _timeOf(b.modified).compareTo(_timeOf(a.modified)),
              );
        if (zips.isEmpty) {
          throw const WebdavException('云端目录里还没有备份，先「上传备份」吧');
        }
        return dav.download(_joinRemote(dir, zips.first.name));
      });
      final dirs = await NativeBridge.appDirs();
      final temp = File('${dirs.cache}/sakura-cloud-restore.zip');
      await temp.writeAsBytes(bytes, flush: true);
      final ok = await _confirm(
        title: '从云端恢复？',
        message:
            '云端最新的备份会覆盖当前的设置、书架、书签和阅读统计，'
            '恢复完要重启 App 才生效哦。',
        okText: '恢复',
      );
      if (!ok) {
        await _tryDelete(temp);
        return;
      }
      final result = await _backup.restore(temp);
      await _tryDelete(temp);
      await _showRestoreResult(result);
      await _refreshLocal();
    } on WebdavException catch (e) {
      _toast(e.message, error: true);
    } on BackupException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('从云端恢复失败了：$e', error: true);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  Future<void> _tryDelete(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---------------- 通用 UI 小工具 ----------------

  void _toast(String message, {bool error = false}) {
    if (!mounted) return;
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        backgroundColor: error ? scheme.error : null,
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String okText = '确定',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(okText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Widget _spinner() => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.prefs,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('备份与恢复')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
            children: [
              _localCard(context),
              const SizedBox(height: 14),
              _fileRestoreCard(context),
              const SizedBox(height: 14),
              _webdavCard(context),
              const SizedBox(height: 16),
              Text(
                '小提示：备份只打包设置、书架、书签、桌宠、阅读统计和书源，'
                '不含书籍文件本身，所以体积很小～恢复后重启 App 才会生效哦 (๑•̀ㅂ•́)و✧',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.6,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _localCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _formatLast(widget.prefs.lastBackupAt);
    return SoftCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.sd_storage_rounded, title: '本地备份'),
          const SizedBox(height: 10),
          Text(
            '上次备份：$last',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            '打包成 zip 存到手机的 Download 文件夹，写不进去会自动改存 App 内部目录。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _busy ? null : _runBackup,
              icon: _backingUp
                  ? _spinner()
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_backingUp ? '正在备份…' : '立即备份'),
            ),
          ),
          if (_lastSavedPath != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    _lastSavedPath!,
                    style: const TextStyle(fontSize: 11.5, height: 1.4),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _copyPath(_lastSavedPath!),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('复制路径'),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            '已备份文件（点一下就能恢复）',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          if (_localBackups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '还没找到备份文件，点上面的「立即备份」试试～',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            )
          else
            for (final file in _localBackups.take(20))
              _backupTile(context, file),
        ],
      ),
    );
  }

  Widget _backupTile(BuildContext context, File file) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(Icons.folder_zip_rounded, color: scheme.primary),
      title: Text(
        _fileName(file.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _fileSubtitle(file),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: const Icon(Icons.settings_backup_restore_rounded, size: 20),
      onTap: _busy ? null : () => _restoreFile(file),
    );
  }

  Widget _fileRestoreCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.folder_open_rounded, title: '从文件恢复'),
          const SizedBox(height: 10),
          Text(
            '把备份 zip 的完整路径粘进来就行，恢复前会让你再确认一次。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pathCtrl,
            minLines: 1,
            maxLines: 3,
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDeco(
              '备份文件路径',
              hint:
                  '/storage/emulated/0/Download/sakura-backup-20250101-0900.zip',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _restoreFromPath,
              icon: _restoring
                  ? _spinner()
                  : const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: Text(_restoring ? '恢复中…' : '恢复'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _webdavCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SoftCard(
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(icon: Icons.cloud_rounded, title: 'WebDAV 云备份'),
          const SizedBox(height: 10),
          Text(
            '坚果云 / Nextcloud / 群晖 都能用。坚果云要在「安全选项」里生成应用密码，'
            '别直接填登录密码哦。',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          _jianguoyunLoginRow(context),
          const SizedBox(height: 12),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDeco(
              '服务器地址',
              hint: 'https://dav.jianguoyun.com/dav',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _userCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDeco('账号', hint: '邮箱 / 用户名'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passCtrl,
            obscureText: _obscurePass,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: '密码 / 应用专用密码',
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscurePass = !_obscurePass),
                icon: Icon(
                  _obscurePass
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _dirCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: _fieldDeco('云端目录', hint: 'sakura-read/'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _saveDav,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('保存'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testDav,
                icon: _testingDav
                    ? _spinner()
                    : const Icon(Icons.wifi_tethering_rounded, size: 18),
                label: Text(_testingDav ? '测试中…' : '测试连接'),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : _uploadBackup,
                icon: _uploading
                    ? _spinner()
                    : const Icon(Icons.cloud_upload_rounded, size: 18),
                label: Text(_uploading ? '上传中…' : '上传备份'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pullFromCloud,
                icon: _pulling
                    ? _spinner()
                    : const Icon(Icons.cloud_download_rounded, size: 18),
                label: Text(_pulling ? '拉取中…' : '从云端恢复'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------- 小函数 ----------------

  /// 坚果云一键登录：输一次账号密码就能填好 WebDAV，省得用户自己去翻应用密码。
  Widget _jianguoyunLoginRow(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cloud_queue_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                '用坚果云账号直接登录',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '输坚果云账号密码就行，密码只存在这台手机上；需要应用密码时 App 会带你去生成。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _jianguoyunLogin,
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                icon: _loggingIn
                    ? _spinner()
                    : const Icon(Icons.login_rounded, size: 16),
                label: Text(_loggingIn ? '登录中…' : '坚果云登录'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  final ok = await JianguoyunLogin.openAppPasswordPage();
                  if (!ok) {
                    _toast(
                      '打不开浏览器的话，手动访问 jianguoyun.com → 账户信息 → '
                      '安全选项 → 添加应用',
                    );
                  }
                },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('获取应用密码'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _jianguoyunLogin() async {
    if (_busy) return;
    final pair = await _askJianguoyunAccount();
    if (pair == null || !mounted) return;
    setState(() => _loggingIn = true);
    try {
      final cred = await JianguoyunLogin.login(
        account: pair.$1,
        password: pair.$2,
        appPasswordProvider: () async {
          if (!mounted) return null;
          final go = await JianguoyunLogin.openAppPasswordPage();
          if (!mounted) return null;
          return _askAppPassword(openedBrowser: go);
        },
      );
      if (!mounted) return;
      _urlCtrl.text = cred.webdavUrl;
      _userCtrl.text = cred.account;
      _passCtrl.text = cred.secret;
      if (_dirCtrl.text.trim().isEmpty) _dirCtrl.text = 'sakura-read/';
      _saveDav();
      _toast(
        cred.usedAccountPassword
            ? '坚果云登录成功，设置已经填好啦 ✿'
            : '坚果云登录成功（用的是应用密码），设置已经填好啦 ✿',
      );
    } on JianguoyunException catch (e) {
      _toast(e.message, error: true);
    } catch (e) {
      _toast('坚果云登录失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  /// 账号 + 密码输入框。
  Future<(String, String)?> _askJianguoyunAccount() async {
    final userCtrl = TextEditingController(text: _userCtrl.text.trim());
    final passCtrl = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('登录坚果云'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: userCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '坚果云账号',
                hintText: '注册邮箱 / 手机号',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(labelText: '密码', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final u = userCtrl.text.trim();
              final p = passCtrl.text;
              if (u.isEmpty || p.isEmpty) return;
              Navigator.pop(ctx, (u, p));
            },
            child: const Text('登录'),
          ),
        ],
      ),
    );
    userCtrl.dispose();
    passCtrl.dispose();
    return result;
  }

  /// 坚果云只认应用密码时弹出的输入框。
  Future<String?> _askAppPassword({required bool openedBrowser}) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还需要应用密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              openedBrowser
                  ? '已经帮你打开坚果云「安全选项」：点「添加应用」生成一个密码，'
                        '复制回来粘在下面就行。'
                  : '去坚果云「账户信息 → 安全选项 → 添加应用」生成应用密码，'
                        '粘在下面。',
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '应用密码',
                hintText: '在坚果云生成的那串密码',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('算了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  InputDecoration _fieldDeco(String label, {String? hint}) => InputDecoration(
    labelText: label,
    hintText: hint,
    hintMaxLines: 2,
    isDense: true,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
  );

  /// 上次备份时间：空 → 「还没有备份过」。
  String _formatLast(String iso) {
    if (iso.trim().isEmpty) return '还没有备份过';
    final t = DateTime.tryParse(iso);
    return t == null ? iso : _formatTime(t.toLocal());
  }

  String _fileSubtitle(File file) {
    final parts = <String>[_parentDir(file.path)];
    try {
      parts.add(_formatTime(file.lastModifiedSync()));
    } catch (_) {}
    try {
      parts.add(formatBytes(file.lengthSync()));
    } catch (_) {}
    return parts.join(' · ');
  }
}

/// `yyyyMMdd-HHmm` 时间戳 → 展示用 `yyyy/MM/dd HH:mm`。
String _formatTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}/${two(t.month)}/${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// 云端目录规范化：统一 `/`、去掉开头斜杠、末尾补 `/`。
String _normalizeDir(String raw) {
  var dir = raw.trim().replaceAll('\\', '/');
  while (dir.startsWith('/')) {
    dir = dir.substring(1);
  }
  if (dir.isNotEmpty && !dir.endsWith('/')) dir = '$dir/';
  return dir;
}

/// 拼远端路径（`sakura-read/` + `x.zip`）。
String _joinRemote(String dir, String name) {
  final d = _normalizeDir(dir);
  return d.isEmpty ? name : '$d$name';
}

bool _isBackupName(String name) =>
    name.startsWith('sakura-backup-') && name.endsWith('.zip');

DateTime _timeOf(DateTime? t) => t ?? DateTime.fromMillisecondsSinceEpoch(0);

String _fileName(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i < 0 ? path : path.substring(i + 1);
}

String _parentDir(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i <= 0 ? path : path.substring(0, i);
}
