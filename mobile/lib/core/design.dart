part of '../main.dart';

ThemeData zuzuTheme() {
  final base = ThemeData(useMaterial3: true, fontFamily: 'NotoSans');
  TextStyle style(TextStyle? s) => (s ?? const TextStyle()).copyWith(
    fontFamily: 'NotoSans',
    color: ink,
    letterSpacing: 0,
  );
  return base.copyWith(
    scaffoldBackgroundColor: paper,
    colorScheme: ColorScheme.fromSeed(
      seedColor: brown,
      primary: brown,
      secondary: orange,
      surface: Colors.white,
      onSurface: ink,
    ),
    textTheme: base.textTheme.copyWith(
      bodySmall: style(base.textTheme.bodySmall),
      bodyMedium: style(base.textTheme.bodyMedium),
      bodyLarge: style(base.textTheme.bodyLarge),
      labelSmall: style(base.textTheme.labelSmall),
      labelMedium: style(base.textTheme.labelMedium),
      labelLarge: style(base.textTheme.labelLarge),
      titleSmall: style(base.textTheme.titleSmall),
      titleMedium: style(base.textTheme.titleMedium),
      titleLarge: style(base.textTheme.titleLarge),
      headlineSmall: style(base.textTheme.headlineSmall),
      headlineMedium: style(base.textTheme.headlineMedium),
      headlineLarge: style(base.textTheme.headlineLarge),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: yellow,
      foregroundColor: ink,
      toolbarHeight: 46,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      titleTextStyle: TextStyle(
        fontFamily: 'NotoSans',
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: ink,
        letterSpacing: 0,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: divider,
      thickness: 1,
      space: 1,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      hintStyle: const TextStyle(color: iconGrey, fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: divider),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 40),
        foregroundColor: Colors.white,
        textStyle: const TextStyle(
          fontFamily: 'NotoSans',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: divider),
      ),
    ),
  );
}

class DesignIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color color;
  const DesignIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = iconGrey,
  });
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/icons/$name.png',
    width: size,
    height: size,
    color: color,
    filterQuality: FilterQuality.high,
    excludeFromSemantics: true,
  );
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ЗуЗу',
    image: true,
    child: Image.asset(
      'assets/brand/wordmark.png',
      width: 56,
      height: 24,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    ),
  );
}

class ZuzuNavigationBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const ZuzuNavigationBar({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  static const labels = ['Профиль', 'Лента', 'Чаты', 'Карта', 'Меню'];
  static const icons = ['home', 'globe', 'chat', 'pin', 'menu'];
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(15, 14, 15, 2),
    child: Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < labels.length; i++)
            Semantics(
              selected: selected == i,
              button: true,
              label: labels[i],
              child: Tooltip(
                message: labels[i],
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onSelected(i),
                  child: SizedBox(
                    width: 46,
                    height: 46,
                    child: Center(
                      child: DesignIcon(
                        icons[i],
                        color: selected == i ? orange : iconGrey,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class PairedAvatar extends StatelessWidget {
  final String? pet, owner;
  final double size, ownerSize;
  const PairedAvatar({
    super.key,
    this.pet,
    this.owner,
    this.size = 40,
    this.ownerSize = 16,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size + ownerSize / 4,
    height: size + ownerSize / 4,
    child: Stack(
      children: [
        Avatar(pet, size: size),
        Positioned(
          bottom: 0,
          right: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: Padding(
              padding: const EdgeInsets.all(1),
              child: Avatar(owner, size: ownerSize),
            ),
          ),
        ),
      ],
    ),
  );
}

class SearchBox extends StatelessWidget {
  final String hint;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  const SearchBox({super.key, this.hint = 'Поиск', this.onTap, this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
    readOnly: onTap != null,
    onTap: onTap,
    onChanged: onChanged,
    style: const TextStyle(fontSize: 14, height: 20 / 14),
    decoration: InputDecoration(
      hintText: hint,
      fillColor: paper,
      prefixIcon: const Padding(
        padding: EdgeInsets.all(10),
        child: DesignIcon('search', size: 20),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
