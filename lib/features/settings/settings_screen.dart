import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/providers_domain.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final shop = ref.watch(currentShopProvider);
    final mode = ref.watch(themeModeProvider);

    return ListView(
      children: [
        if (session.isAdmin)
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('بيانات المحل'),
            subtitle: Text(shop?.name ?? 'اختر محلاً من الرئيسية لتعديل بياناته'),
            enabled: shop != null,
            onTap: shop == null
                ? null
                : () => showDialog(
                    context: context, builder: (_) => _ShopDialog(shop: shop)),
          ),
        if (session.isAdmin && shop != null)
          Builder(builder: (context) {
            final allow = ref.watch(allowOverpayProvider(shop.id)).valueOrNull ?? false;
            return SwitchListTile(
              secondary: const Icon(Icons.price_check_outlined),
              title: const Text('السماح بتجاوز المدفوع لسعر الطلب'),
              subtitle: const Text('افتراضياً يُمنع تسجيل دفعة تتجاوز المتبقي'),
              value: allow,
              onChanged: (v) async {
                await ref
                    .read(paymentRepositoryProvider)
                    .setAllowOverpay(session.user!.id, shop.id, v);
                ref.invalidate(allowOverpayProvider(shop.id));
              },
            );
          }),
        ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('المظهر'),
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode)),
              ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode)),
              ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android)),
            ],
            selected: {mode},
            onSelectionChanged: (v) =>
                ref.read(themeModeProvider.notifier).set(v.first),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.lock_reset),
          title: const Text('تغيير كلمة المرور'),
          onTap: () => showDialog(
              context: context, builder: (_) => const _PasswordDialog()),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('عن التطبيق'),
          subtitle: Text('خياطتي • الإصدار 0.1.0 • يعمل بدون إنترنت'),
        ),
        ListTile(
          leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
          title: const Text('تسجيل الخروج'),
          onTap: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('تسجيل الخروج'),
                content: const Text('هل تريد تسجيل الخروج؟'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('خروج')),
                ],
              ),
            );
            if (ok == true) ref.read(sessionProvider.notifier).logout();
          },
        ),
      ],
    );
  }
}

class _ShopDialog extends ConsumerStatefulWidget {
  const _ShopDialog({required this.shop});
  final Shop shop;

  @override
  ConsumerState<_ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends ConsumerState<_ShopDialog> {
  late final _name = TextEditingController(text: widget.shop.name);
  late final _phone = TextEditingController(text: widget.shop.phone ?? '');
  late final _address = TextEditingController(text: widget.shop.address ?? '');
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref.read(authRepositoryProvider).updateShop(
          ref.read(sessionProvider).user!.id,
          widget.shop.id,
          _name.text,
          _phone.text,
          _address.text);
      if (mounted) Navigator.pop(context);
    } on AppException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('بيانات المحل'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم المحل')),
          const SizedBox(height: 8),
          TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'الهاتف')),
          const SizedBox(height: 8),
          TextField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'العنوان')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: _save,
            child: const Text('حفظ')),
      ],
    );
  }
}

class _PasswordDialog extends ConsumerStatefulWidget {
  const _PasswordDialog();

  @override
  ConsumerState<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends ConsumerState<_PasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text != _confirm.text) {
      setState(() => _error = 'كلمتا المرور غير متطابقتين');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).changePassword(
          ref.read(sessionProvider).user!.id, _old.text, _new.text);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تغيير كلمة المرور')));
    } on AppException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('تغيير كلمة المرور'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _old,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'كلمة المرور الحالية')),
          const SizedBox(height: 8),
          TextField(
              controller: _new,
              obscureText: true,
              decoration:
                  const InputDecoration(labelText: 'الجديدة (8 أحرف على الأقل)')),
          const SizedBox(height: 8),
          TextField(
              controller: _confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'تأكيد الجديدة')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('إلغاء')),
        FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: _busy ? null : _save,
            child: const Text('حفظ')),
      ],
    );
  }
}
