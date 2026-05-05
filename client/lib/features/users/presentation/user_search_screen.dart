import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_public_profile.dart';
import '../data/user_search_result.dart';
import 'user_profile_screen.dart';

typedef UserSearchQueryCallback = Future<List<UserSearchResult>> Function(
  String query,
);

/// Загрузить полный публичный профиль по id (если null — из результата поиска).
typedef UserPublicProfileLoader = Future<UserPublicProfile> Function(
  int userId,
);

/// Поиск пользователей: поле ввода (debounce + отправка), список результатов.
///
/// [onWrite] передаётся в [UserProfileScreen] при открытии профиля из списка.
class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({
    super.key,
    required this.onSearch,
    required this.onWrite,
    this.loadPublicProfile,
    this.debounce = const Duration(milliseconds: 400),
  });

  final UserSearchQueryCallback onSearch;

  /// Создание/открытие директа для выбранного пользователя.
  final Future<void> Function(int otherUserId) onWrite;

  /// Если задан — перед показом профиля; иначе [UserPublicProfile.fromSearchResult].
  final UserPublicProfileLoader? loadPublicProfile;

  final Duration debounce;

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounceTimer;

  List<UserSearchResult> _results = [];
  bool _loading = false;
  String? _error;
  int? _openingUserId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleSearch(String raw) {
    _debounceTimer?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounceTimer = Timer(widget.debounce, () => _runSearch(q));
  }

  Future<void> _runSearch(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.onSearch(query);
      if (!mounted) return;
      setState(() {
        _results = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openProfile(UserSearchResult row) async {
    if (_openingUserId != null) return;
    setState(() => _openingUserId = row.id);
    try {
      final UserPublicProfile profile;
      final loader = widget.loadPublicProfile;
      if (loader != null) {
        profile = await loader(row.id);
      } else {
        profile = UserPublicProfile.fromSearchResult(row);
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => UserProfileScreen(
            profile: profile,
            onWrite: widget.onWrite,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _openingUserId = null);
    }
  }

  String _snippet(String? text, {int maxLen = 120}) {
    if (text == null) return '';
    final t = text.trim();
    if (t.length <= maxLen) return t;
    return '${t.substring(0, maxLen)}…';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Поиск пользователей'),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Имя или @username',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _controller.clear();
                                _debounceTimer?.cancel();
                                setState(() {
                                  _results = [];
                                  _error = null;
                                  _loading = false;
                                });
                              },
                            )
                          : null,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) {
                  setState(() {});
                  _scheduleSearch(v);
                },
                onSubmitted: (v) {
                  _debounceTimer?.cancel();
                  final q = v.trim();
                  if (q.isEmpty) {
                    setState(() {
                      _results = [];
                      _error = null;
                      _loading = false;
                    });
                  } else {
                    _runSearch(q);
                  }
                },
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(color: scheme.error),
                ),
              ),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? Center(
                      child: Text(
                        _controller.text.trim().isEmpty
                            ? 'Введите запрос для поиска'
                            : 'Ничего не найдено',
                        style: textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final r = _results[index];
                        final opening = _openingUserId == r.id;
                        final name = r.displayName?.trim().isNotEmpty == true
                            ? r.displayName!.trim()
                            : r.username;
                        final snippet = _snippet(r.about);

                        return ListTile(
                          enabled: !opening,
                          leading: CircleAvatar(
                            backgroundColor: scheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '@${r.username}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.primary,
                                ),
                              ),
                              if (snippet.isNotEmpty)
                                Text(
                                  snippet,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall,
                                ),
                            ],
                          ),
                          trailing: opening
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : null,
                          onTap: () => _openProfile(r),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
