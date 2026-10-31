import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_failure.dart';
import '../../services/api_service.dart';
import '../../services/auth_provider.dart';
import '../../utils/theme.dart';

class _ChatMessage {
  final String role;
  final String content;
  final List<Map<String, dynamic>> choices;
  const _ChatMessage(this.role, this.content, {this.choices = const []});
}

class AiChatScreen extends StatefulWidget {
  final String? initialPrompt;
  final String? initialContext;
  final String? initialContextTitle;
  const AiChatScreen({
    super.key,
    this.initialPrompt,
    this.initialContext,
    this.initialContextTitle,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const _currentConversationKey = 'attenda_ai_current_conversation';
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_ChatMessage> _messages = [];
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final Set<int> _usedChoiceMessages = {};
  String? _conversationId;
  String? _context;
  String? _contextTitle;
  String? _historyError;
  bool _historyTruncated = false;
  int _sessionVersion = 0;
  bool _sending = false;
  bool _listening = false;
  bool _speaking = false;
  String get _userConversationKey =>
      '$_currentConversationKey:${context.read<AuthProvider>().user?.orgId ?? ''}:${context.read<AuthProvider>().user?.id ?? ''}';

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _speaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _speaking = false);
    });
    _context = widget.initialContext;
    _contextTitle = widget.initialContextTitle;
    final prompt = widget.initialPrompt?.trim();
    final hasLaunchContext = (prompt?.isNotEmpty ?? false) ||
        (widget.initialContext?.isNotEmpty ?? false);
    if (hasLaunchContext) {
      if (prompt?.isNotEmpty ?? false) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _send(prompt);
        });
      }
    } else {
      _restoreCurrentConversation();
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _tts.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restoreCurrentConversation() async {
    final sessionVersion = _sessionVersion;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getString(_userConversationKey);
      final conversations = await api.getAiConversations();
      if (!mounted || sessionVersion != _sessionVersion) return;
      final ids = conversations
          .whereType<Map>()
          .map((c) => c['id']?.toString())
          .whereType<String>()
          .toList();
      final conversationId = savedId != null && ids.contains(savedId)
          ? savedId
          : (ids.isNotEmpty ? ids.first : null);
      if (conversationId != null && mounted) {
        await _openConversation(conversationId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _historyError = ApiFailure.fromError(error).userMessage);
      }
    }
  }

  Future<void> _send([String? suggestedPrompt, int? choiceIndex]) async {
    if (_sending) return;
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
    }
    final text = (suggestedPrompt ?? _input.text).trim();
    if (text.isEmpty) return;
    final sessionVersion = ++_sessionVersion;
    _input.clear();
    setState(() {
      _messages.add(_ChatMessage('user', text));
      _sending = true;
    });
    _scrollToBottom();
    try {
      final result = await api.chatWithAi(text,
          conversationId: _conversationId, context: _context);
      if (!mounted || sessionVersion != _sessionVersion) return;
      final answer =
          result['response']?.toString() ?? 'I could not create a response.';
      final nextConversationId =
          result['conversation_id']?.toString() ?? _conversationId;
      final choices = (result['choices'] as List? ?? [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      setState(() {
        _conversationId = nextConversationId;
        _messages.add(_ChatMessage('assistant', answer, choices: choices));
      });
      if (nextConversationId != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userConversationKey, nextConversationId);
      }
    } catch (error) {
      if (!mounted || sessionVersion != _sessionVersion) return;
      final failure = ApiFailure.fromError(error);
      final timedOut = failure is TimeoutFailure;
      setState(() {
        // A write may have completed even when its response timed out. Keep a
        // confirmation choice consumed so the user does not accidentally send
        // the same action again; they can check Requests before retrying.
        if (choiceIndex != null && !timedOut) {
          _usedChoiceMessages.remove(choiceIndex);
        }
        final message = timedOut
            ? 'I did not receive a response in time. If you asked me to submit or change something, check its status in Requests before trying again.'
            : failure.userMessage;
        _messages.add(_ChatMessage('error', message));
      });
    } finally {
      if (mounted && sessionVersion == _sessionVersion) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: AppMotion.duration, curve: AppMotion.curve);
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_speech.isListening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final available = await _speech.initialize(
      onStatus: (status) {
        if (mounted) setState(() => _listening = status == 'listening');
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (!available) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Voice input is unavailable. Check microphone permission and device speech services.')));
      }
      return;
    }
    try {
      await _speech.listen(
        listenOptions: stt.SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          listenMode: stt.ListenMode.dictation,
        ),
        onResult: (SpeechRecognitionResult result) {
          _input.value = TextEditingValue(
              text: result.recognizedWords,
              selection: TextSelection.collapsed(
                  offset: result.recognizedWords.length));
          if (mounted) setState(() {});
        },
      );
      if (mounted) setState(() => _listening = _speech.isListening);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Voice input is not available for your device language.')));
      }
    }
  }

  Future<void> _speak(String content) async {
    if (_speaking) {
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    final plainText = content
        .replaceAll(RegExp(r'```[\s\S]*?```'), 'Code omitted.')
        .replaceAll(RegExp(r'[#*_>`]'), '')
        .trim();
    final locale = _speechLocaleFor(plainText);
    await _tts.stop();
    final available = await _tts.isLanguageAvailable(locale);
    if (available != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Speech for this language is not installed on this device.')));
      }
      return;
    }
    await _tts.setLanguage(locale);
    await _tts.setSpeechRate(0.48);
    if (mounted) setState(() => _speaking = true);
    await _tts.speak(plainText);
  }

  String _speechLocaleFor(String text) {
    if (RegExp(r'[ٹڈڑںےھ]').hasMatch(text)) return 'ur-PK';
    if (RegExp(r'[\u0600-\u06ff]').hasMatch(text)) return 'ar-SA';
    if (RegExp(r'[\u0900-\u097f]').hasMatch(text)) return 'hi-IN';
    if (RegExp(r'[\u0980-\u09ff]').hasMatch(text)) return 'bn-BD';
    final lower = text.toLowerCase();
    if (RegExp(r'[¿¡ñáíóú]').hasMatch(lower) ||
        RegExp(r'\b(hola|gracias|quiero|solicitud|permiso)\b')
            .hasMatch(lower)) {
      return 'es-ES';
    }
    if (RegExp(r'[àâçéèêëîïôûùüÿœ]').hasMatch(lower) ||
        RegExp(r'\b(bonjour|merci|congé|demande)\b').hasMatch(lower)) {
      return 'fr-FR';
    }
    if (RegExp(r'[ãõ]').hasMatch(lower) ||
        RegExp(r'\b(olá|obrigado|solicitação|férias)\b').hasMatch(lower)) {
      return 'pt-BR';
    }
    return WidgetsBinding.instance.platformDispatcher.locale
        .toString()
        .replaceAll('_', '-');
  }

  void _newChat() {
    _sessionVersion++;
    setState(() {
      _conversationId = null;
      _context = null;
      _contextTitle = null;
      _historyError = null;
      _historyTruncated = false;
      _sending = false;
      _messages.clear();
      _usedChoiceMessages.clear();
    });
    final key = _userConversationKey;
    SharedPreferences.getInstance().then((prefs) => prefs.remove(key));
  }

  Future<void> _showHistory() async {
    final sessionVersion = _sessionVersion;
    setState(() => _historyError = null);
    try {
      final conversations = await api.getAiConversations();
      if (!mounted || sessionVersion != _sessionVersion) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                child: Row(children: [
                  const Expanded(
                      child: Text('Recent conversations',
                          style: AppTextStyles.headline)),
                  IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close)),
                ]),
              ),
              Expanded(
                child: conversations.isEmpty
                    ? const Center(
                        child: Text('No saved conversations yet',
                            style: AppTextStyles.body))
                    : ListView.separated(
                        itemCount: conversations.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, index) {
                          final item = Map<String, dynamic>.from(
                              conversations[index] as Map);
                          return ListTile(
                            leading: const CircleAvatar(
                                child: Icon(Icons.auto_awesome, size: 18)),
                            title: Text(
                                item['title']?.toString() ?? 'Conversation',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                            subtitle: Text(_conversationSubtitle(item)),
                            onTap: () async {
                              Navigator.pop(sheetContext);
                              await _openConversation(item['id'].toString());
                            },
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)),
        );
      }
    }
  }

  String _conversationSubtitle(Map<String, dynamic> item) {
    final count = item['message_count'] ?? 0;
    final contextTitle = item['context_title']?.toString();
    final updatedAt = DateTime.tryParse(item['updated_at']?.toString() ?? '');
    final details = <String>[
      if (contextTitle != null && contextTitle.isNotEmpty) contextTitle,
      '$count messages',
      if (updatedAt != null)
        DateFormat('MMM d, h:mm a').format(updatedAt.toLocal()),
    ];
    return details.join(' · ');
  }

  Future<void> _openConversation(String id, {bool persist = true}) async {
    setState(() {
      _historyError = null;
    });
    final sessionVersion = ++_sessionVersion;
    setState(() => _sending = true);
    try {
      final result = await api.getAiConversation(id);
      if (!mounted || sessionVersion != _sessionVersion) return;
      final raw = result['messages'] as List? ?? [];
      final restoredMessages = raw
          .whereType<Map>()
          .map((item) => _ChatMessage(
                item['role']?.toString() ?? 'assistant',
                item['content']?.toString() ?? '',
                choices:
                    ((item['toolCalls'] as Map?)?['choices'] as List? ?? [])
                        .whereType<Map>()
                        .map((choice) => Map<String, dynamic>.from(choice))
                        .toList(),
              ))
          .where((message) =>
              message.role == 'user' || message.role == 'assistant')
          .toList();
      setState(() {
        _conversationId = id;
        _context = result['context']?.toString();
        _contextTitle = _contextTitleFrom(_context);
        _historyTruncated = result['has_older_messages'] == true;
        _messages
          ..clear()
          ..addAll(restoredMessages);
        _usedChoiceMessages.clear();
        for (var i = 0; i < _messages.length; i++) {
          if (_messages[i].choices.isNotEmpty &&
              _messages.skip(i + 1).any((message) => message.role == 'user')) {
            _usedChoiceMessages.add(i);
          }
        }
      });
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_userConversationKey, id);
      }
      _scrollToBottom();
    } catch (error) {
      if (mounted && sessionVersion == _sessionVersion) {
        setState(() => _historyError =
            'Could not load this conversation: ${ApiFailure.fromError(error).userMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiFailure.fromError(error).userMessage)),
        );
      }
    } finally {
      if (mounted && sessionVersion == _sessionVersion) {
        setState(() => _sending = false);
      }
    }
  }

  String? _contextTitleFrom(String? context) {
    if (context == null || context.isEmpty) return null;
    try {
      final decoded = jsonDecode(context);
      if (decoded is Map) {
        final project = (decoded['project'] as Map?)?['name']?.toString();
        final task = (decoded['task'] as Map?)?['title']?.toString();
        if (project != null && task != null) return '$project · $task';
        if (project != null) return project;
      }
    } on FormatException {
      return 'Context attached';
    }
    return 'Context attached';
  }

  @override
  Widget build(BuildContext context) {
    final userName =
        context.watch<AuthProvider>().user?.name.split(' ').first ?? 'there';
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [
          Icon(Icons.auto_awesome, color: AppColors.primary, size: 20),
          SizedBox(width: 9),
          Text('Attenda AI'),
        ]),
        actions: [
          IconButton(
              tooltip: 'Conversation history',
              onPressed: _sending ? null : _showHistory,
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'New chat',
              onPressed: _sending ? null : _newChat,
              icon: const Icon(Icons.add_comment_outlined)),
        ],
      ),
      body: Column(children: [
        if (_context != null)
          Material(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .08),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.link, size: 18),
              title: Text(_contextTitle ?? 'Page context',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle:
                  const Text('Snapshot; I’ll verify live details when needed.'),
              trailing: IconButton(
                tooltip: 'Clear context and start a new chat',
                onPressed: _sending ? null : _newChat,
                icon: const Icon(Icons.close, size: 18),
              ),
            ),
          ),
        if (_historyError != null)
          MaterialBanner(
            content: Text(_historyError!),
            actions: [
              TextButton(
                onPressed: () => setState(() => _historyError = null),
                child: const Text('Dismiss'),
              ),
            ],
          ),
        if (_historyTruncated)
          const MaterialBanner(
            content: Text(
                'Showing the latest 100 messages. Older messages are saved but not loaded into this chat yet.'),
            actions: [],
          ),
        Expanded(
          child: _messages.isEmpty
              ? _WelcomePanel(userName: userName, onPrompt: _send)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (_, index) {
                    if (_sending && index == _messages.length) {
                      return const _TypingBubble();
                    }
                    final message = _messages[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _MessageBubble(
                            message: message,
                            onSpeak: message.role == 'assistant'
                                ? () => _speak(message.content)
                                : null,
                            speaking: _speaking),
                        if (message.choices.isNotEmpty)
                          Builder(builder: (context) {
                            final isConfirmation = message.choices.any(
                              (choice) => RegExp(
                                r'^confirm (action|decision)$',
                                caseSensitive: false,
                              ).hasMatch(choice['label']?.toString() ?? ''),
                            );
                            final used =
                                _usedChoiceMessages.contains(index);
                            if (isConfirmation) {
                              return Padding(
                                padding:
                                    const EdgeInsets.only(left: 2, bottom: 14),
                                child: _ConfirmationPanel(
                                  choices: message.choices,
                                  disabled: _sending || used,
                                  selected: used,
                                  onSelect: (choice) {
                                    setState(
                                        () => _usedChoiceMessages.add(index));
                                    _send(choice['prompt']?.toString(), index);
                                  },
                                ),
                              );
                            }
                            return Padding(
                              padding:
                                  const EdgeInsets.only(left: 2, bottom: 14),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: message.choices.map((choice) {
                                  final label =
                                      choice['label']?.toString() ?? 'Continue';
                                  return ActionChip(
                                    avatar: Icon(
                                      used
                                          ? Icons.check_circle
                                          : Icons.arrow_forward,
                                      size: 15,
                                      color: used
                                          ? AppColors.success700
                                          : Theme.of(context)
                                              .colorScheme
                                              .primary,
                                    ),
                                    label: Text(
                                        used ? 'Selected: $label' : label),
                                    onPressed: _sending || used
                                        ? null
                                        : () {
                                            setState(() =>
                                                _usedChoiceMessages
                                                    .add(index));
                                            _send(
                                                choice['prompt']?.toString(),
                                                index);
                                          },
                                  );
                                }).toList(),
                              ),
                            );
                          }),
                      ],
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_listening)
                Padding(
                  padding:
                      const EdgeInsets.only(left: 14, right: 14, bottom: 7),
                  child: Row(children: [
                    Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                            color: AppColors.danger500,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text('Listening · tap the mic when you’re done',
                        style: AppTextStyles.caption),
                  ]),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                      color: _listening
                          ? AppColors.primary.withValues(alpha: .65)
                          : AppColors.border),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: .08),
                        blurRadius: 16,
                        offset: const Offset(0, 4))
                  ],
                ),
                child:
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 5, bottom: 4),
                    child: IconButton(
                      tooltip:
                          _listening ? 'Stop voice input' : 'Dictate a message',
                      onPressed: _sending ? null : _toggleListening,
                      icon: Icon(
                          _listening
                              ? Icons.stop_rounded
                              : Icons.mic_none_rounded,
                          color: _listening
                              ? Theme.of(context).colorScheme.error
                              : AppColors.textSecondary),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          shape: const CircleBorder()),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textDirection:
                          RegExp(r'[\u0600-\u06ff]').hasMatch(_input.text)
                              ? ui.TextDirection.rtl
                              : ui.TextDirection.ltr,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Message Attenda AI…',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 15),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 5, bottom: 4),
                    child: IconButton.filled(
                      tooltip: _sending ? 'Sending message' : 'Send message',
                      onPressed: _sending || _input.text.trim().isEmpty
                          ? null
                          : () => _send(),
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.arrow_upward_rounded, size: 20),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(42, 42),
                          shape: const CircleBorder()),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _WelcomePanel extends StatelessWidget {
  final String userName;
  final ValueChanged<String> onPrompt;
  const _WelcomePanel({required this.userName, required this.onPrompt});

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .1),
                  shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome,
                  color: AppColors.primary, size: 30),
            ),
            const SizedBox(height: 18),
            Text('Hi $userName', style: AppTextStyles.display),
            const SizedBox(height: 8),
            const Text(
                'Get live answers about attendance, leave, shifts, approvals, and projects. Ask for a summary or help with a request. Changes are only applied after you confirm them.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body),
            const SizedBox(height: 22),
            for (final prompt in [
              'Summarize my attendance this month',
              'What shifts do I have coming up?',
              'Do I have any pending approvals?',
              'Summarize my projects and overdue tasks',
            ]) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => onPrompt(prompt),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: Text(prompt, textAlign: TextAlign.left),
                  style: OutlinedButton.styleFrom(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ]),
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  final _ChatMessage message;
  final VoidCallback? onSpeak;
  final bool speaking;
  const _MessageBubble(
      {required this.message, this.onSpeak, this.speaking = false});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final isError = message.role == 'error';
    final theme = Theme.of(context);
    final color = isError
        ? theme.colorScheme.errorContainer
        : isUser
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface;
    final maxWidth = MediaQuery.sizeOf(context).width > 760
        ? 700.0
        : MediaQuery.sizeOf(context).width * (isUser ? .88 : .96);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isUser) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 3, bottom: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Text(
                      isError ? 'MESSAGE' : 'ATTENDA AI',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .7,
                      ),
                    ),
                  ]),
                ),
              ],
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isUser ? 18 : 5),
                    bottomRight: Radius.circular(isUser ? 5 : 18),
                  ),
                  border: isUser || isError
                      ? null
                      : Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: isUser || isError
                    ? SelectableText(
                        message.content,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: isUser
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onErrorContainer,
                        ),
                      )
                    : Directionality(
                        textDirection:
                            RegExp(r'[\u0600-\u06ff]').hasMatch(message.content)
                                ? ui.TextDirection.rtl
                                : ui.TextDirection.ltr,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _AssistantMarkdown(content: message.content),
                              if (onSpeak != null)
                                Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                        tooltip: speaking
                                            ? 'Stop speaking'
                                            : 'Read aloud',
                                        visualDensity: VisualDensity.compact,
                                        onPressed: onSpeak,
                                        icon: Icon(
                                            speaking
                                                ? Icons.stop_circle_outlined
                                                : Icons.volume_up_outlined,
                                            size: 19))),
                            ]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssistantMarkdown extends StatelessWidget {
  final String content;
  const _AssistantMarkdown({required this.content});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    final base = MarkdownStyleSheet.fromTheme(theme);
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: base.copyWith(
        p: TextStyle(fontSize: 14, height: 1.55, color: textColor),
        pPadding: const EdgeInsets.only(bottom: 8),
        h1: TextStyle(
            fontSize: 21,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: textColor),
        h1Padding: const EdgeInsets.only(top: 8, bottom: 8),
        h2: TextStyle(
            fontSize: 18,
            height: 1.3,
            fontWeight: FontWeight.w700,
            color: textColor),
        h2Padding: const EdgeInsets.only(top: 8, bottom: 6),
        h3: TextStyle(
            fontSize: 16,
            height: 1.35,
            fontWeight: FontWeight.w700,
            color: textColor),
        h3Padding: const EdgeInsets.only(top: 6, bottom: 4),
        strong: TextStyle(fontWeight: FontWeight.w700, color: textColor),
        em: TextStyle(fontStyle: FontStyle.italic, color: textColor),
        a: TextStyle(color: primary, decoration: TextDecoration.underline),
        code: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: textColor,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(left: BorderSide(color: primary, width: 3)),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquotePadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        tableHead: TextStyle(
            fontWeight: FontWeight.w700, color: textColor, fontSize: 13),
        tableBody: TextStyle(color: textColor, fontSize: 13, height: 1.4),
        tableCellsPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        tableBorder: TableBorder.all(color: theme.colorScheme.outlineVariant),
        listIndent: 22,
        blockSpacing: 10,
      ),
      onTapLink: (_, href, __) {
        final uri = href == null ? null : Uri.tryParse(href);
        if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();
  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> {
  static const labels = [
    'Thinking through your request',
    'Working through the details',
    'Putting together a helpful answer',
    'Taking a little longer — thanks for waiting'
  ];
  int step = 0;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && step < labels.length - 1) setState(() => step++);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            liveRegion: true,
            label: labels[step],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome,
                    size: 17, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 9),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 9),
                AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text('${labels[step]}…',
                        key: ValueKey(step), style: AppTextStyles.caption)),
              ]),
            ),
          ),
        ),
      );
}

class _ConfirmationPanel extends StatelessWidget {
  final List<Map<String, dynamic>> choices;
  final bool disabled;
  final bool selected;
  final ValueChanged<Map<String, dynamic>> onSelect;

  const _ConfirmationPanel({
    required this.choices,
    required this.disabled,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.tertiaryContainer.withValues(alpha: .24),
        border: Border.all(color: colors.tertiary.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified_user_outlined, color: colors.tertiary, size: 19),
          const SizedBox(width: 8),
          Text('Review before continuing',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 7),
        Text(
          'Nothing has changed yet. Confirm to proceed, or cancel to leave everything as it is.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: choices.map((choice) {
            final label = choice['label']?.toString() ?? 'Continue';
            final isConfirm = label.toLowerCase().startsWith('confirm ');
            final buttonLabel = selected
                ? 'Selected: $label'
                : isConfirm
                    ? 'Confirm and continue'
                    : 'Cancel safely';
            return isConfirm
                ? FilledButton.icon(
                    onPressed: disabled ? null : () => onSelect(choice),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(buttonLabel),
                  )
                : OutlinedButton.icon(
                    onPressed: disabled ? null : () => onSelect(choice),
                    icon: const Icon(Icons.close, size: 18),
                    label: Text(buttonLabel),
                  );
          }).toList(),
        ),
      ]),
    );
  }
}
