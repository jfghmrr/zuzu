part of '../../main.dart';

// Figma «Готовое»: 27:3076. Original image: 27:3161.
const authYellow = Color(0xfffbeb90);
const authBrown = Color(0xff996440);
const authInk = Color(0xff39434f);

class WelcomePage extends StatelessWidget {
  const WelcomePage({
    super.key,
    required this.onRegister,
    required this.onLogin,
  });
  final VoidCallback onRegister, onLogin;

  static const privacyText =
      'Нажимая кнопку «Регистрация» или «У вас уже есть аккаунт», \n'
      'Вы подтверждаете, что ознакомились с Политикой '
      'конфиденциальности, и даёте согласие на обработку Ваших '
      'Персональных данных в соответствии с ней.';

  @override
  Widget build(BuildContext context) {
    final footer = Text.rich(
      const TextSpan(
        children: [
          TextSpan(
            text:
                'Нажимая кнопку «Регистрация» или «У вас уже есть аккаунт», \n'
                'Вы подтверждаете, что ознакомились с ',
          ),
          TextSpan(
            text: 'Политикой конфиденциальности',
            style: TextStyle(decoration: TextDecoration.underline),
          ),
          TextSpan(
            text:
                ', и даёте согласие на обработку Ваших '
                'Персональных данных в соответствии с ней.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: 'NotoSans',
        letterSpacing: 0,
        fontSize: 10,
        height: 1.15,
        color: Color(0x5939434f),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: authYellow,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ExcludeSemantics(
                            child: Opacity(opacity: 0, child: footer),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 36, bottom: 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/brand/welcome-logo.png',
                                  width: 250,
                                  height: 191.51,
                                  semanticLabel: 'ЗуЗу — кот и собака',
                                ),
                                const SizedBox(height: 32),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: onRegister,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: authBrown,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 10,
                                      ),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      textStyle: const TextStyle(
                                        fontFamily: 'NotoSans',
                                        letterSpacing: 0,
                                        fontSize: 14,
                                        height: 20 / 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    child: const Text('Регистрация'),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: onLogin,
                                  style: TextButton.styleFrom(
                                    foregroundColor: authInk,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 16,
                                    ),
                                    minimumSize: const Size(44, 40),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    textStyle: const TextStyle(
                                      fontFamily: 'NotoSans',
                                      letterSpacing: 0,
                                      fontSize: 14,
                                      height: 16 / 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  child: const Text('У вас уже есть аккаунт?'),
                                ),
                              ],
                            ),
                          ),
                          InkWell(
                            onTap: () => open(const LegalPage(kind: 'privacy')),
                            child: Padding(
                              padding: EdgeInsets.zero,
                              child: footer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
