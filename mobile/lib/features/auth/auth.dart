part of '../../main.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});
  @override
  Widget build(BuildContext context) => WelcomePage(
    onRegister: () => open(const AuthFormPage(registering: true)),
    onLogin: () => open(const AuthFormPage(registering: false)),
  );
}

class AuthFormPage extends StatefulWidget {
  const AuthFormPage({super.key, required this.registering});
  final bool registering;
  @override
  State<AuthFormPage> createState() => _AuthFormPageState();
}

class _AuthFormPageState extends State<AuthFormPage> {
  final contact = TextEditingController();
  final registrationEmail = TextEditingController();
  final code = TextEditingController();
  final codeFocus = FocusNode();
  bool email = false, busy = false;
  bool policy = false, privacy = false, terms = false, needsConsent = false;
  Map<String, dynamic>? challenge;
  String? error;
  String requestedContact = '';
  String secondaryContact = '';
  int cooldown = 0;
  Timer? timer;
  bool get consentsAccepted => policy && privacy && terms;
  bool get requireConsent => widget.registering || needsConsent;

  @override
  void dispose() {
    contact.dispose();
    registrationEmail.dispose();
    code.dispose();
    codeFocus.dispose();
    timer?.cancel();
    super.dispose();
  }

  Future<void> request() async {
    if (busy) return;
    if (challenge == null && requireConsent && !consentsAccepted) {
      setState(() => error = 'Подтвердите каждое согласие перед регистрацией.');
      return;
    }
    if (challenge == null) {
      requestedContact = contact.text.trim();
      secondaryContact = '';
      if (widget.registering) {
        final mail = registrationEmail.text.trim();
        if (mail.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(mail)) {
          setState(() => error = 'Проверьте электронную почту.');
          return;
        }
        if (requestedContact.isEmpty) {
          requestedContact = mail;
        } else {
          secondaryContact = mail;
        }
      }
      if (requestedContact.isEmpty) {
        setState(() => error = 'Введите номер телефона или электронную почту.');
        return;
      }
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final response = Map<String, dynamic>.from(
        await api.call('POST', '/auth/request', {'contact': requestedContact}),
      );
      if (!mounted) return;
      challenge = response;
      code.clear();
      cooldown = (response['resend_after'] as num?)?.toInt() ?? 60;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return;
        setState(() => cooldown = cooldown > 0 ? cooldown - 1 : 0);
        if (cooldown == 0) t.cancel();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) codeFocus.requestFocus();
      });
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> verify() async {
    if (busy) return;
    if (code.text.length != 6) {
      setState(() => error = 'Введите все шесть цифр кода.');
      return;
    }
    if (requireConsent && !consentsAccepted) {
      setState(() => error = 'Подтвердите каждое согласие перед регистрацией.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final v = await api.call('POST', '/auth/verify', {
        'challenge_id': challenge!['challenge_id'],
        'code': code.text,
        'device': api.device,
        'privacy': policy && privacy ? api.health['legal_version'] : null,
        'terms': terms ? api.health['legal_version'] : null,
      });
      final secondary = secondaryContact;
      await api.login(v['token']);
      await platform.connectPush(api);
      nav.currentState?.popUntil((route) => route.isFirst);
      if (secondary.isNotEmpty) {
        await open(LinkContactPage(initialContact: secondary));
      }
      if (pendingRoute != null) await routeTo(pendingRoute!);
    } catch (e) {
      if (mounted) {
        error = '$e';
        if (e is ApiFailure &&
            e.status == 422 &&
            e.message.contains('согласие')) {
          needsConsent = true;
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void back() {
    if (busy) return;
    if (challenge == null) {
      Navigator.of(context).pop();
    } else {
      timer?.cancel();
      setState(() {
        challenge = null;
        code.clear();
        error = null;
      });
    }
  }

  Widget field(
    TextEditingController controller,
    String hint, {
    required bool mail,
  }) => TextField(
    controller: controller,
    enabled: !busy,
    keyboardType: mail ? TextInputType.emailAddress : TextInputType.phone,
    autofillHints: [mail ? AutofillHints.email : AutofillHints.telephoneNumber],
    textInputAction: TextInputAction.next,
    style: const TextStyle(
      fontFamily: 'NotoSans',
      letterSpacing: 0,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
      color: authInk,
    ),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontFamily: 'NotoSans',
        letterSpacing: 0,
        color: Color(0xffb9c1cc),
        fontSize: 16,
        fontWeight: FontWeight.w400,
      ),
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xffd4dae1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xffd4dae1)),
      ),
    ),
  );

  Widget consent(
    String label,
    bool value,
    ValueChanged<bool> change,
    String document,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 24),
    child: Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Checkbox(
            value: value,
            onChanged: busy ? null : (v) => setState(() => change(v!)),
            activeColor: authBrown,
            fillColor: const WidgetStatePropertyAll(Colors.white),
            checkColor: const Color(0xffa4b1c4),
            side: const BorderSide(color: Color(0xffd4dae1)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(3),
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => open(LegalPage(kind: document)),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                height: 1.3,
                color: Color(0xff92959a),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  List<Widget> get consentFields => [
    consent(
      'Я принимаю Политику конфиденциальности',
      policy,
      (v) => policy = v,
      'privacy',
    ),
    consent(
      'Согласие на обработку Персональных данных',
      privacy,
      (v) => privacy = v,
      'privacy',
    ),
    consent(
      'Я принимаю Пользовательское соглашение',
      terms,
      (v) => terms = v,
      'terms',
    ),
  ];

  Widget action(String title, VoidCallback? onPressed) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: authBrown,
        foregroundColor: Colors.white,
        disabledBackgroundColor: authBrown.withValues(alpha: .45),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(
          fontFamily: 'NotoSans',
          letterSpacing: 0,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 20 / 14,
        ),
      ),
      child: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(title),
    ),
  );

  Widget codeInput() => SizedBox(
    height: 54,
    child: Stack(
      children: [
        ExcludeSemantics(
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: code,
            builder: (context, value, _) => Row(
              children: List.generate(
                6,
                (i) => Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i == 5 ? 0 : 6),
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: codeFocus.hasFocus && i == value.text.length
                            ? const Color(0xff007aff)
                            : const Color(0xffd4dae1),
                      ),
                    ),
                    child: Text(
                      i < value.text.length ? value.text[i] : '_',
                      style: TextStyle(
                        fontSize: 20,
                        color: i < value.text.length
                            ? authInk
                            : const Color(0xffa4b1c4),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        TextField(
          controller: code,
          focusNode: codeFocus,
          enabled: !busy,
          keyboardType: TextInputType.number,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          style: const TextStyle(
            color: Colors.transparent,
            fontSize: 20,
            letterSpacing: 30,
          ),
          showCursor: false,
          decoration: const InputDecoration(
            semanticCounterText: 'Шестизначный код',
            hintText: 'Шестизначный код',
            hintStyle: TextStyle(color: Colors.transparent),
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.all(14),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => verify(),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isCode = challenge != null;
    final title = isCode
        ? 'Код для входа'
        : widget.registering
        ? 'Регистрация'
        : 'Войти';
    return PopScope(
      canPop: !busy && !isCode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: authYellow,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 15,
                      vertical: 24,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 540),
                        child: DefaultTextStyle(
                          style: const TextStyle(
                            fontFamily: 'NotoSans',
                            letterSpacing: 0,
                            color: authInk,
                            fontSize: 14,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Image.asset(
                                'assets/brand/horizontal-logo.png',
                                width: 215.48,
                                height: 51.02,
                                semanticLabel: 'ЗуЗу',
                              ),
                              const SizedBox(height: 32),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 26,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: .7),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      title,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 24,
                                        height: 1,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    if (!isCode) ...[
                                      if (widget.registering) ...[
                                        field(
                                          registrationEmail,
                                          'Электронная почта',
                                          mail: true,
                                        ),
                                        const SizedBox(height: 12),
                                        field(
                                          contact,
                                          'Номер телефона',
                                          mail: false,
                                        ),
                                        const SizedBox(height: 8),
                                        ...consentFields,
                                      ] else ...[
                                        field(
                                          contact,
                                          email ? 'Почта' : 'Телефон',
                                          mail: email,
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: InkWell(
                                            onTap: busy
                                                ? null
                                                : () => setState(() {
                                                    email = !email;
                                                    contact.clear();
                                                    error = null;
                                                  }),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 6,
                                                  ),
                                              child: Text(
                                                email
                                                    ? 'Войти с помощью номера телефона'
                                                    : 'Войти с помощью электронной почты',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  height: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ] else ...[
                                      Text(
                                        api.health['demo'] == true
                                            ? 'Код для локальной проверки контакта\n$requestedContact'
                                            : requestedContact.contains('@')
                                            ? 'Сообщение с кодом пришло на вашу электронную почту\n$requestedContact'
                                            : 'Текстовое сообщение с кодом пришло на ваш номер телефона\n$requestedContact',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          height: 22 / 16,
                                        ),
                                      ),
                                      const SizedBox(height: 24),
                                      codeInput(),
                                      if (challenge!['dev_code'] != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 12,
                                          ),
                                          child: SelectableText(
                                            'DEV-код: ${challenge!['dev_code']}',
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      const SizedBox(height: 18),
                                      TextButton(
                                        onPressed: busy || cooldown > 0
                                            ? null
                                            : request,
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 24),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          foregroundColor: authInk,
                                        ),
                                        child: Text(
                                          cooldown > 0
                                              ? 'Отправить новый код через $cooldown с'
                                              : 'Не получили код проверки? Отправить новый код.',
                                          style: const TextStyle(
                                            fontFamily: 'NotoSans',
                                            letterSpacing: 0,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      if (needsConsent) ...[
                                        const SizedBox(height: 12),
                                        ...consentFields,
                                      ],
                                    ],
                                    if (error != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(
                                          error!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xffb42318),
                                          ),
                                        ),
                                      ),
                                    SizedBox(height: isCode ? 12 : 20),
                                    action(
                                      isCode
                                          ? 'Войти'
                                          : widget.registering
                                          ? 'Получить код-пароль'
                                          : 'Далее',
                                      busy
                                          ? null
                                          : isCode
                                          ? verify
                                          : request,
                                    ),
                                    if (isCode) ...[
                                      const SizedBox(height: 12),
                                      TextButton(
                                        onPressed: busy ? null : back,
                                        style: TextButton.styleFrom(
                                          foregroundColor: const Color(
                                            0xff92959a,
                                          ),
                                          textStyle: const TextStyle(
                                            fontFamily: 'NotoSans',
                                            letterSpacing: 0,
                                            fontSize: 14,
                                          ),
                                        ),
                                        child: const Text('Назад'),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
