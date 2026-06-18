import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/account/data/account_api.dart';
import 'package:hiddify/features/account/notifier/account_notifier.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum AccountSection { overview, packages, subscription, devices, password, orders }

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key, this.section = AccountSection.overview});

  final AccountSection section;

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!ref.read(accountNotifierProvider).isAuthenticated) {
        ref.read(accountNotifierProvider.notifier).loadPublicData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountNotifierProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_accountSectionTitle(widget.section)),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: state.loading ? null : () => _guard(context, ref.read(accountNotifierProvider.notifier).refresh),
            icon: const Icon(Icons.refresh_rounded),
          ),
          const Gap(8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _guard(context, ref.read(accountNotifierProvider.notifier).refresh),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedSwitcher(
                      duration: kAnimationDuration,
                      child: state.isAuthenticated ? _AccountSectionBody(section: widget.section) : const _AuthPanel(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthPanel extends ConsumerStatefulWidget {
  const _AuthPanel();

  @override
  ConsumerState<_AuthPanel> createState() => _AuthPanelState();
}

class _AuthPanelState extends ConsumerState<_AuthPanel> {
  int _mode = 0;
  final _loginEmail = TextEditingController();
  final _loginPassword = TextEditingController();
  final _registerUsername = TextEditingController();
  final _registerEmail = TextEditingController();
  final _registerPassword = TextEditingController();
  final _registerCode = TextEditingController();
  final _inviteCode = TextEditingController();
  final _resetEmail = TextEditingController();
  final _resetCode = TextEditingController();
  final _resetPassword = TextEditingController();

  @override
  void dispose() {
    _loginEmail.dispose();
    _loginPassword.dispose();
    _registerUsername.dispose();
    _registerEmail.dispose();
    _registerPassword.dispose();
    _registerCode.dispose();
    _inviteCode.dispose();
    _resetEmail.dispose();
    _resetCode.dispose();
    _resetPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountNotifierProvider);
    final theme = Theme.of(context);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ModeChip(label: '登录', selected: _mode == 0, onSelected: () => setState(() => _mode = 0)),
              _ModeChip(label: '注册', selected: _mode == 1, onSelected: () => setState(() => _mode = 1)),
              _ModeChip(label: '忘记密码', selected: _mode == 2, onSelected: () => setState(() => _mode = 2)),
            ],
          ),
          const Gap(20),
          Text(switch (_mode) {
            0 => '登录后可以购买套餐、查看订阅和管理设备。',
            1 => '注册会直接对接你的网站账号系统。',
            _ => '通过邮箱验证码重置网站账号密码。',
          }, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Gap(20),
          switch (_mode) {
            0 => _loginForm(context, state),
            1 => _registerForm(context, state),
            _ => _forgotForm(context, state),
          },
        ],
      ),
    );
  }

  Widget _loginForm(BuildContext context, AccountState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextField(
          controller: _loginEmail,
          label: '邮箱',
          hintText: '请输入邮箱地址',
          icon: Icons.mail_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const Gap(12),
        _TextField(controller: _loginPassword, label: '密码', icon: Icons.lock_rounded, obscureText: true),
        const Gap(18),
        FilledButton.icon(
          onPressed: state.loading
              ? null
              : () => _guard(
                  context,
                  () => ref.read(accountNotifierProvider.notifier).login(_loginEmail.text, _loginPassword.text),
                ),
          icon: state.loading
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login_rounded),
          label: const Text('登录'),
        ),
      ],
    );
  }

  Widget _registerForm(BuildContext context, AccountState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextField(controller: _registerUsername, label: '用户名', icon: Icons.person_rounded),
        const Gap(12),
        _TextField(
          controller: _registerEmail,
          label: '邮箱',
          icon: Icons.mail_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const Gap(12),
        _TextField(controller: _registerPassword, label: '密码', icon: Icons.lock_rounded, obscureText: true),
        const Gap(12),
        _VerificationCodeField(
          controller: _registerCode,
          label: '邮箱验证码',
          loading: state.loading,
          onSend: () => _guard(context, () async {
            final message = await ref.read(accountNotifierProvider.notifier).sendRegisterCode(_registerEmail.text);
            if (context.mounted) _showSnack(context, message);
          }),
        ),
        const Gap(12),
        _TextField(controller: _inviteCode, label: '邀请码（如网站要求）', icon: Icons.card_giftcard_rounded),
        const Gap(18),
        FilledButton.icon(
          onPressed: state.loading
              ? null
              : () => _guard(
                  context,
                  () => ref
                      .read(accountNotifierProvider.notifier)
                      .register(
                        username: _registerUsername.text,
                        email: _registerEmail.text,
                        password: _registerPassword.text,
                        verificationCode: _registerCode.text,
                        inviteCode: _inviteCode.text,
                      ),
                ),
          icon: const Icon(Icons.person_add_rounded),
          label: const Text('创建账号'),
        ),
      ],
    );
  }

  Widget _forgotForm(BuildContext context, AccountState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextField(
          controller: _resetEmail,
          label: '邮箱',
          icon: Icons.mail_rounded,
          keyboardType: TextInputType.emailAddress,
        ),
        const Gap(12),
        _VerificationCodeField(
          controller: _resetCode,
          label: '验证码',
          loading: state.loading,
          onSend: () => _guard(context, () async {
            final message = await ref.read(accountNotifierProvider.notifier).forgotPassword(_resetEmail.text);
            if (context.mounted) _showSnack(context, message);
          }),
        ),
        const Gap(12),
        _TextField(controller: _resetPassword, label: '新密码', icon: Icons.lock_reset_rounded, obscureText: true),
        const Gap(18),
        FilledButton.icon(
          onPressed: state.loading
              ? null
              : () => _guard(context, () async {
                  final message = await ref
                      .read(accountNotifierProvider.notifier)
                      .resetPassword(
                        email: _resetEmail.text,
                        verificationCode: _resetCode.text,
                        newPassword: _resetPassword.text,
                      );
                  if (context.mounted) _showSnack(context, message);
                  setState(() => _mode = 0);
                }),
          icon: const Icon(Icons.check_circle_rounded),
          label: const Text('重置密码'),
        ),
      ],
    );
  }
}

String _accountSectionTitle(AccountSection section) {
  return switch (section) {
    AccountSection.overview => '账户概览',
    AccountSection.packages => '套餐购买',
    AccountSection.subscription => '订阅同步',
    AccountSection.devices => '设备管理',
    AccountSection.password => '密码修改',
    AccountSection.orders => '订单记录',
  };
}

IconData accountSectionIcon(AccountSection section) {
  return switch (section) {
    AccountSection.overview => Icons.account_circle_rounded,
    AccountSection.packages => Icons.inventory_2_rounded,
    AccountSection.subscription => Icons.cloud_sync_rounded,
    AccountSection.devices => Icons.devices_rounded,
    AccountSection.password => Icons.password_rounded,
    AccountSection.orders => Icons.receipt_long_rounded,
  };
}

String accountSectionRouteName(AccountSection section) {
  return switch (section) {
    AccountSection.overview => 'account',
    AccountSection.packages => 'accountPackages',
    AccountSection.subscription => 'accountSubscription',
    AccountSection.devices => 'accountDevices',
    AccountSection.password => 'accountPassword',
    AccountSection.orders => 'accountOrders',
  };
}

class _AccountSectionBody extends ConsumerWidget {
  const _AccountSectionBody({required this.section});

  final AccountSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.authExpired) ...[const _AuthExpiredBanner(), const Gap(14)],
        AnimatedSwitcher(
          duration: kAnimationDuration,
          child: KeyedSubtree(key: ValueKey(section), child: _sectionContent(section)),
        ),
      ],
    );
  }

  Widget _sectionContent(AccountSection section) {
    return switch (section) {
      AccountSection.overview => const _AccountOverviewPanel(),
      AccountSection.packages => const _PackagesPanel(),
      AccountSection.subscription => const _SubscriptionPanel(),
      AccountSection.devices => const _DevicesPanel(),
      AccountSection.password => const _PasswordPanel(),
      AccountSection.orders => const _OrdersPanel(),
    };
  }
}

class _AccountOverviewPanel extends ConsumerWidget {
  const _AccountOverviewPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    final theme = Theme.of(context);
    final user = state.user;
    final subscription = state.dashboard?.subscription;
    final hasSubscription = subscription != null && subscription.status.isNotEmpty;
    final deviceText =
        '${subscription?.onlineDevices ?? subscription?.currentDevices ?? 0}/${subscription?.deviceLimit ?? 0}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Surface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 26,
                    child: Text((user?.name.isNotEmpty ?? false) ? user!.name.characters.first.toUpperCase() : 'U'),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user?.name ?? '用户', style: theme.textTheme.titleLarge),
                        const Gap(2),
                        Text(
                          user?.email ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        const Gap(8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Tag(text: user?.isVerified == true ? '已验证' : '未验证'),
                            _Tag(text: user?.isActive == false ? '已停用' : '账号正常'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  OutlinedButton.icon(
                    onPressed: state.loading
                        ? null
                        : () => _guard(context, ref.read(accountNotifierProvider.notifier).refresh),
                    icon: state.loading
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('刷新'),
                  ),
                ],
              ),
              const Gap(18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(label: '余额', value: '¥${(user?.balance ?? 0).toStringAsFixed(2)}'),
                  _Metric(label: '订阅状态', value: _statusText(subscription?.status ?? 'none')),
                  _Metric(label: '到期时间', value: subscription?.expireTime ?? '未开通'),
                  _Metric(label: '在线设备', value: deviceText),
                  _Metric(label: '累计消费', value: '¥${(state.dashboard?.totalSpent ?? 0).toStringAsFixed(2)}'),
                ],
              ),
              const Gap(16),
              _OverviewSubscriptionStrip(
                subscription: subscription,
                syncing: state.syncingSubscription,
                onOpenSubscription: () => context.goNamed(accountSectionRouteName(AccountSection.subscription)),
              ),
            ],
          ),
        ),
        const Gap(14),
        LayoutBuilder(
          builder: (context, constraints) {
            final twoColumns = constraints.maxWidth >= 680;
            final children = [
              _OverviewAction(
                icon: Icons.inventory_2_rounded,
                title: '购买套餐',
                subtitle: state.packages.isEmpty ? '暂无可售套餐' : '${state.packages.length} 个套餐可选',
                buttonLabel: '去购买',
                onPressed: () => context.goNamed(accountSectionRouteName(AccountSection.packages)),
              ),
              _OverviewAction(
                icon: Icons.devices_rounded,
                title: '设备管理',
                subtitle: state.deviceTotal == 0 ? '暂无设备记录' : '${state.deviceTotal} 台设备记录',
                buttonLabel: '管理设备',
                onPressed: () => context.goNamed(accountSectionRouteName(AccountSection.devices)),
              ),
              _OverviewAction(
                icon: Icons.password_rounded,
                title: '密码修改',
                subtitle: '修改当前网站账号密码',
                buttonLabel: '去修改',
                onPressed: () => context.goNamed(accountSectionRouteName(AccountSection.password)),
              ),
              _OverviewAction(
                icon: Icons.receipt_long_rounded,
                title: '订单记录',
                subtitle: state.orders.isEmpty ? '暂无订单' : '最近 ${state.orders.length} 条订单',
                buttonLabel: '查看订单',
                onPressed: () => context.goNamed(accountSectionRouteName(AccountSection.orders)),
              ),
            ];
            if (!twoColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  children[0],
                  const Gap(12),
                  children[1],
                  const Gap(12),
                  children[2],
                  const Gap(12),
                  children[3],
                ],
              );
            }
            return Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children[0]),
                    const Gap(12),
                    Expanded(child: children[1]),
                  ],
                ),
                const Gap(12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: children[2]),
                    const Gap(12),
                    Expanded(child: children[3]),
                  ],
                ),
              ],
            );
          },
        ),
        if (!hasSubscription) ...[
          const Gap(14),
          _Surface(child: _EmptyLine(text: state.packages.isEmpty ? '当前没有开通中的订阅，可刷新或稍后查看套餐。' : '当前没有开通中的订阅，可先购买套餐。')),
        ],
      ],
    );
  }
}

class _OverviewSubscriptionStrip extends ConsumerWidget {
  const _OverviewSubscriptionStrip({
    required this.subscription,
    required this.syncing,
    required this.onOpenSubscription,
  });

  final AccountSubscription? subscription;
  final bool syncing;
  final VoidCallback onOpenSubscription;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subscription = this.subscription;
    final active = subscription?.canImport == true;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: active
            ? theme.colorScheme.primaryContainer.withValues(alpha: .42)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .42),
        border: Border.all(color: active ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              active ? Icons.check_circle_rounded : Icons.info_rounded,
              color: active ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(active ? '订阅可同步' : '订阅未就绪', style: theme.textTheme.titleSmall),
                  const Gap(2),
                  Text(
                    subscription == null
                        ? '购买套餐后可写入本机配置'
                        : '${subscription.packageName.isEmpty ? '当前套餐' : subscription.packageName} · ${_statusText(subscription.status)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const Gap(10),
            OutlinedButton.icon(
              onPressed: syncing ? null : onOpenSubscription,
              icon: syncing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.tune_rounded),
              label: const Text('管理'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverviewAction extends StatelessWidget {
  const _OverviewAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const Gap(10),
          Text(title, style: theme.textTheme.titleMedium),
          const Gap(4),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const Gap(14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
          ),
        ],
      ),
    );
  }
}

class _AuthExpiredBanner extends ConsumerWidget {
  const _AuthExpiredBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: .45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: theme.colorScheme.onErrorContainer),
            const Gap(8),
            Expanded(
              child: Text(
                '登录授权已失效，请重新登录后同步订阅。本地配置不会自动删除。',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
            ),
            TextButton(
              onPressed: () => _guard(context, ref.read(accountNotifierProvider.notifier).logout),
              child: const Text('退出'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackagesPanel extends ConsumerWidget {
  const _PackagesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            icon: Icons.inventory_2_rounded,
            title: '套餐购买',
            subtitle: state.paymentMethods.isEmpty ? '暂无可用支付方式' : '支持 ${state.paymentMethods.length} 种支付方式',
          ),
          const Gap(12),
          if (state.packages.isEmpty)
            const _EmptyLine(text: '暂无套餐，请确认网站后台已启用套餐。')
          else
            for (final package in state.packages) ...[
              _PackageTile(package: package),
              if (package != state.packages.last) const Gap(10),
            ],
        ],
      ),
    );
  }
}

class _PackageTile extends ConsumerWidget {
  const _PackageTile({required this.package});

  final AccountPackage package;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final methods = ref.watch(accountNotifierProvider).paymentMethods;
    final loading = ref.watch(accountNotifierProvider).loading;
    final buyButton = FilledButton.tonalIcon(
      onPressed: loading ? null : () => _showPaymentSheet(context, package: package, paymentMethods: methods),
      icon: const Icon(Icons.shopping_bag_rounded),
      label: const Text('购买'),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: package.isRecommended ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
        color: package.isRecommended
            ? theme.colorScheme.primaryContainer.withValues(alpha: .36)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .34),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 520;
            final details = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Flexible(child: Text(package.name, style: theme.textTheme.titleMedium)),
                    if (package.isRecommended) ...[const Gap(8), const _Tag(text: '推荐')],
                  ],
                ),
                const Gap(6),
                Text(
                  package.description.isEmpty
                      ? '${package.durationDays} 天 · ${package.deviceLimit} 台设备'
                      : package.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '¥${package.price.toStringAsFixed(2)}',
                      style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                    _InlineFact(icon: Icons.schedule_rounded, text: '${package.durationDays} 天'),
                    _InlineFact(icon: Icons.devices_rounded, text: '${package.deviceLimit} 台设备'),
                  ],
                ),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const Gap(12), buyButton],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const Gap(12),
                buyButton,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InlineFact extends StatelessWidget {
  const _InlineFact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const Gap(4),
        Text(text, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SubscriptionPanel extends ConsumerWidget {
  const _SubscriptionPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    final subscription = state.dashboard?.subscription;
    final theme = Theme.of(context);
    final syncing = state.syncingSubscription;
    final canImport = subscription?.canImport == true;
    final hasSyncUrl = subscription?.hasImportUrl == true;

    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(icon: Icons.cloud_sync_rounded, title: '订阅同步', subtitle: '写入本机配置并刷新当前订阅'),
          const Gap(14),
          if (subscription == null)
            const _EmptyLine(text: '当前没有可同步的订阅，购买套餐后会自动生成订阅信息。')
          else ...[
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .36),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          canImport ? Icons.verified_rounded : Icons.info_rounded,
                          color: canImport ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                        ),
                        const Gap(10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subscription.packageName.isEmpty ? '当前订阅' : subscription.packageName,
                                style: theme.textTheme.titleMedium,
                              ),
                              const Gap(2),
                              Text(
                                canImport
                                    ? '订阅可写入本机配置'
                                    : hasSyncUrl
                                    ? '同步后会写入服务端返回的状态配置'
                                    : '订阅暂不可导入，请检查状态或到期时间',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _Metric(label: '状态', value: _statusText(subscription.status)),
                        _Metric(label: '到期时间', value: subscription.expireTime.isEmpty ? '未知' : subscription.expireTime),
                        _Metric(label: '剩余天数', value: '${subscription.remainingDays} 天'),
                        _Metric(
                          label: '设备',
                          value:
                              '${subscription.onlineDevices == 0 ? subscription.currentDevices : subscription.onlineDevices}/${subscription.deviceLimit}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(14),
            _SubscriptionSyncStatus(syncing: syncing),
          ],
          const Gap(14),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 520;
              final syncButton = FilledButton.icon(
                onPressed: syncing || !hasSyncUrl
                    ? null
                    : () => _guard(context, ref.read(accountNotifierProvider.notifier).syncSubscription),
                icon: syncing
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload_rounded),
                label: const Text('同步到本机'),
              );
              final refreshButton = OutlinedButton.icon(
                onPressed: syncing || !hasSyncUrl
                    ? null
                    : () => _guard(context, ref.read(accountNotifierProvider.notifier).refreshActiveSubscription),
                icon: const Icon(Icons.update_rounded),
                label: const Text('刷新当前订阅'),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [syncButton, const Gap(8), refreshButton],
                );
              }
              return Row(children: [syncButton, const Gap(10), refreshButton]);
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.package, required this.paymentMethods});

  final AccountPackage package;
  final List<PaymentMethod> paymentMethods;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  static const _paymentPollInterval = Duration(seconds: 3);
  static const _paymentPollTimeout = Duration(minutes: 10);

  PaymentMethod? _selectedMethod;
  OrderResult? _order;
  OrderResult? _payment;
  AccountOrderStatus? _status;
  Timer? _pollTimer;
  DateTime? _pollStartedAt;
  bool _busy = false;
  bool _openingPayment = false;

  String? get _qrCodeValue {
    final value = _payment?.paymentQrCode ?? _order?.paymentQrCode ?? _payment?.paymentUrl ?? _order?.paymentUrl;
    return value?.isEmpty ?? true ? null : value;
  }

  String? get _externalPaymentUrl {
    final value = _payment?.paymentUrl ?? _order?.paymentUrl;
    return value?.isEmpty ?? true ? null : value;
  }

  bool get _canOpenExternalPayment => PlatformUtils.isAndroid;

  @override
  void initState() {
    super.initState();
    _selectedMethod = widget.paymentMethods.isEmpty ? null : widget.paymentMethods.first;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = _payment ?? _order;
    final qrCodeValue = _qrCodeValue;
    final externalPaymentUrl = _externalPaymentUrl;
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      title: const Text('确认购买'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .42),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.package.name, style: theme.textTheme.titleMedium),
                      const Gap(4),
                      Text(
                        '${widget.package.durationDays} 天 · ${widget.package.deviceLimit} 台设备',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Gap(8),
                      Text(
                        '¥${widget.package.price.toStringAsFixed(2)}',
                        style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(14),
              Text('支付方式', style: theme.textTheme.titleSmall),
              const Gap(8),
              if (widget.paymentMethods.isEmpty)
                const _EmptyLine(text: '暂无可用支付方式，请在网站后台启用。')
              else
                ...widget.paymentMethods.map(
                  (method) => _PaymentMethodOption(
                    method: method,
                    selected: _selectedMethod?.id == method.id,
                    enabled: !_busy && order?.status != 'paid',
                    onTap: () => setState(() => _selectedMethod = method),
                  ),
                ),
              if (qrCodeValue != null) ...[
                const Gap(12),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: QrImageView(data: qrCodeValue, size: 220),
                    ),
                  ),
                ),
                const Gap(8),
                Text(
                  _canOpenExternalPayment
                      ? '用支付宝扫码，或点击“打开支付”跳转到手机支付应用。支付完成后本窗口会自动刷新状态。'
                      : '电脑端请使用支付宝扫码支付，本软件不会自动打开浏览器。支付完成后本窗口会自动刷新状态。',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              if (_status != null || order != null) ...[
                const Gap(12),
                _PaymentStatusLine(status: _status?.status ?? order?.status ?? 'pending'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('关闭')),
        if (_canOpenExternalPayment && externalPaymentUrl != null)
          OutlinedButton.icon(
            onPressed: _openingPayment ? null : _openPaymentUrl,
            icon: _openingPayment
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.open_in_new_rounded),
            label: const Text('打开支付'),
          ),
        FilledButton.icon(
          onPressed: _busy || widget.paymentMethods.isEmpty ? null : _startPayment,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.qr_code_2_rounded),
          label: Text(qrCodeValue == null ? '生成支付二维码' : '重新生成'),
        ),
      ],
    );
  }

  Future<void> _startPayment() async {
    if (_busy) return;
    final method = _selectedMethod;
    if (method == null) return;
    setState(() => _busy = true);
    try {
      final notifier = ref.read(accountNotifierProvider.notifier);
      final order = _order?.id == 0 || _order == null ? await notifier.createPackageOrder(widget.package) : _order!;
      final payment = order.id > 0
          ? await notifier.createOrderPayment(orderId: order.id, paymentMethod: method)
          : order;
      if (!mounted) return;
      setState(() {
        _order = order;
        _payment = payment;
        _status = AccountOrderStatus(
          orderNo: payment.orderNo,
          status: payment.status.isEmpty ? 'pending' : payment.status,
        );
      });
      _startPolling(payment.orderNo);
      final url = _externalPaymentUrl;
      if (_canOpenExternalPayment && url != null) {
        await _launchPaymentUrl(url);
      }
    } on AccountApiException catch (error) {
      if (mounted) _showSnack(context, error.message);
    } catch (error) {
      if (mounted) _showSnack(context, error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startPolling(String orderNo) {
    _pollTimer?.cancel();
    if (orderNo.isEmpty) return;
    _pollStartedAt = DateTime.now();
    _pollTimer = Timer.periodic(_paymentPollInterval, (_) => _checkStatus(orderNo));
    unawaited(_checkStatus(orderNo));
  }

  Future<void> _checkStatus(String orderNo) async {
    final startedAt = _pollStartedAt;
    if (startedAt != null && DateTime.now().difference(startedAt) >= _paymentPollTimeout) {
      _pollTimer?.cancel();
      if (mounted) _showSnack(context, '支付状态查询超时，请稍后在订单列表刷新查看');
      return;
    }
    try {
      final status = await ref.read(accountNotifierProvider.notifier).checkOrderStatus(orderNo);
      if (!mounted) return;
      setState(() => _status = status);
      if (status.isPaid) {
        _pollTimer?.cancel();
        await ref.read(accountNotifierProvider.notifier).refreshAfterPayment();
        if (!mounted) return;
        _showSnack(context, '支付成功，套餐已自动开通并同步订阅');
        Navigator.of(context).pop();
      } else if (status.isFinished) {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Keep polling; transient network failures should not close the payment flow.
    }
  }

  Future<void> _openPaymentUrl() async {
    final url = _externalPaymentUrl;
    if (url == null) return;
    setState(() => _openingPayment = true);
    try {
      await _launchPaymentUrl(url);
    } finally {
      if (mounted) setState(() => _openingPayment = false);
    }
  }

  Future<void> _launchPaymentUrl(String url) async {
    if (!_canOpenExternalPayment) {
      if (mounted) _showSnack(context, '电脑端请使用二维码扫码支付');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) _showSnack(context, '支付链接无效');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (mounted) _showSnack(context, opened ? '已打开支付页面' : '无法打开支付页面');
  }
}

class _PaymentStatusLine extends StatelessWidget {
  const _PaymentStatusLine({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = status == 'paid';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: paid ? theme.colorScheme.primaryContainer : theme.colorScheme.surface,
        border: Border.all(color: paid ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(paid ? Icons.check_circle_rounded : Icons.hourglass_top_rounded),
            const Gap(8),
            Expanded(child: Text('支付状态：${_statusText(status)}')),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodOption extends StatelessWidget {
  const _PaymentMethodOption({
    required this.method,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final PaymentMethod method;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? theme.colorScheme.primary : theme.colorScheme.outlineVariant),
            color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: .42) : theme.colorScheme.surface,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(method.name, style: theme.textTheme.bodyMedium),
                      if (method.key.isNotEmpty)
                        Text(
                          method.key,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DevicesPanel extends ConsumerWidget {
  const _DevicesPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    final devices = state.devices;
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final header = _SectionHeader(
                icon: Icons.devices_rounded,
                title: '设备管理',
                subtitle: devices.isEmpty ? '查看并移除订阅设备记录' : '最近访问的设备排在前面',
              );
              final refreshButton = OutlinedButton.icon(
                onPressed: state.loading
                    ? null
                    : () => _guard(context, ref.read(accountNotifierProvider.notifier).refreshDevices),
                icon: state.loading
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded),
                label: const Text('刷新'),
              );
              if (constraints.maxWidth < 480) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [header, const Gap(12), refreshButton],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: header),
                  const Gap(12),
                  refreshButton,
                ],
              );
            },
          ),
          const Gap(14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Metric(label: '总设备', value: '${state.deviceTotal}'),
              _Metric(label: '近 24 小时', value: '${state.deviceOnline}'),
              _Metric(label: '移动设备', value: '${state.deviceMobile}'),
              _Metric(label: '桌面设备', value: '${state.deviceDesktop}'),
            ],
          ),
          const Gap(14),
          if (devices.isEmpty)
            const _EmptyLine(text: '暂无设备记录。设备首次拉取订阅配置后会显示在这里。')
          else
            for (final device in devices) ...[_DeviceTile(device: device), if (device != devices.last) const Gap(10)],
        ],
      ),
    );
  }
}

class _DeviceTile extends ConsumerWidget {
  const _DeviceTile({required this.device});

  final AccountDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final subtitle = [
      device.softwareLabel,
      device.osLabel,
      device.modelLabel,
    ].where((value) => value.isNotEmpty).join(' · ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_deviceIcon(device.deviceType), color: theme.colorScheme.primary),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          const Gap(3),
                          Text(
                            subtitle.isEmpty ? _truncateText(device.userAgent, 80) : subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const Gap(8),
                    _DeviceStatusPill(device: device),
                  ],
                ),
                const Gap(10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _InlineFact(icon: Icons.category_rounded, text: _deviceTypeText(device.deviceType)),
                    if (device.ipAddress.isNotEmpty) _InlineFact(icon: Icons.public_rounded, text: device.ipAddress),
                    if (device.location.isNotEmpty) _InlineFact(icon: Icons.location_on_rounded, text: device.location),
                    if (device.accessLabel.isNotEmpty)
                      _InlineFact(icon: Icons.schedule_rounded, text: device.accessLabel),
                    if (device.accessCount > 0)
                      _InlineFact(icon: Icons.query_stats_rounded, text: '${device.accessCount} 次访问'),
                  ],
                ),
                if (device.remark.isNotEmpty) ...[
                  const Gap(8),
                  Text(
                    device.remark,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            );
            final actions = _DeviceActions(device: device);

            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const Gap(12), actions]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const Gap(12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DeviceActions extends ConsumerWidget {
  const _DeviceActions({required this.device});

  final AccountDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountNotifierProvider);
    final theme = Theme.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: state.loading ? null : () => _showDeviceRemarkDialog(context, ref, device),
          icon: const Icon(Icons.edit_note_rounded),
          label: Text(device.remark.isEmpty ? '备注' : '改备注'),
        ),
        OutlinedButton.icon(
          onPressed: state.loading ? null : () => _confirmDeleteDevice(context, ref, device),
          style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('移除'),
        ),
      ],
    );
  }
}

class _DeviceStatusPill extends StatelessWidget {
  const _DeviceStatusPill({required this.device});

  final AccountDevice device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normal = device.isActive && device.isAllowed;
    final background = normal ? theme.colorScheme.primaryContainer : theme.colorScheme.errorContainer;
    final foreground = normal ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onErrorContainer;
    final border = normal
        ? theme.colorScheme.primary.withValues(alpha: .35)
        : theme.colorScheme.error.withValues(alpha: .35);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(normal ? '允许' : '受限', style: theme.textTheme.labelSmall?.copyWith(color: foreground)),
      ),
    );
  }
}

class _PasswordPanel extends ConsumerStatefulWidget {
  const _PasswordPanel();

  @override
  ConsumerState<_PasswordPanel> createState() => _PasswordPanelState();
}

class _PasswordPanelState extends ConsumerState<_PasswordPanel> {
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();

  @override
  void dispose() {
    _oldPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountNotifierProvider);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(icon: Icons.password_rounded, title: '密码修改', subtitle: '修改当前网站账号密码'),
          const Gap(14),
          _TextField(controller: _oldPassword, label: '当前密码', icon: Icons.lock_open_rounded, obscureText: true),
          const Gap(10),
          _TextField(controller: _newPassword, label: '新密码', icon: Icons.lock_reset_rounded, obscureText: true),
          const Gap(12),
          FilledButton.icon(
            onPressed: state.loading
                ? null
                : () => _guard(context, () async {
                    await ref
                        .read(accountNotifierProvider.notifier)
                        .changePassword(oldPassword: _oldPassword.text, newPassword: _newPassword.text);
                    _oldPassword.clear();
                    _newPassword.clear();
                  }),
            icon: const Icon(Icons.password_rounded),
            label: const Text('修改密码'),
          ),
        ],
      ),
    );
  }
}

class _OrdersPanel extends ConsumerWidget {
  const _OrdersPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(accountNotifierProvider).orders;
    final recentOrders = orders.take(20).toList(growable: false);
    return _Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(icon: Icons.receipt_long_rounded, title: '最近订单', subtitle: '显示最近 20 条'),
          const Gap(12),
          if (orders.isEmpty)
            const _EmptyLine(text: '暂无订单')
          else
            for (final order in recentOrders) ...[
              _OrderTile(order: order),
              if (order != recentOrders.last) const Gap(8),
            ],
        ],
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order});

  final AccountOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .3),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 480;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.packageName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const Gap(4),
                Text(
                  [order.orderNo, order.createdAt].where((value) => value.isNotEmpty).join(' · '),
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            );
            final amount = Column(
              crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text('¥${order.amount.toStringAsFixed(2)}', style: theme.textTheme.titleSmall),
                const Gap(4),
                _StatusPill(status: order.status),
              ],
            );

            if (compact) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const Gap(10), amount]);
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const Gap(12),
                amount,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SubscriptionSyncStatus extends ConsumerWidget {
  const _SubscriptionSyncStatus({required this.syncing});

  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            if (syncing)
              const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              const Icon(Icons.cloud_sync_rounded),
            const Gap(8),
            Expanded(
              child: Text(
                syncing ? '正在同步账户订阅' : '账户订阅已自动写入本机配置',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ),
            OutlinedButton.icon(
              onPressed: syncing
                  ? null
                  : () => _guard(context, ref.read(accountNotifierProvider.notifier).syncSubscription),
              icon: const Icon(Icons.update_rounded),
              label: const Text('同步'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 132,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const Gap(4),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.autofillHints,
    this.maxLength,
    this.helperText,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final String? helperText;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      maxLength: maxLength,
      decoration: InputDecoration(
        prefixIcon: Icon(icon),
        labelText: label,
        hintText: hintText,
        helperText: helperText,
        counterText: maxLength == null ? null : '',
        border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
      ),
    );
  }
}

class _VerificationCodeField extends StatelessWidget {
  const _VerificationCodeField({
    required this.controller,
    required this.label,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final String label;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final field = _TextField(
      controller: controller,
      label: label,
      icon: Icons.verified_rounded,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.oneTimeCode],
      maxLength: 6,
      helperText: '6 位数字验证码',
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
    );

    final button = SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        onPressed: loading ? null : onSend,
        icon: loading
            ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.mark_email_read_rounded),
        label: const Text('发送验证码'),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const Gap(8), button]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: field),
            const Gap(8),
            SizedBox(width: 132, child: button),
          ],
        );
      },
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onSelected());
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(4)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(text, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onPrimary)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paid = status == 'paid' || status == 'active';
    final failed = status == 'failed' || status == 'expired' || status == 'cancelled';
    final background = paid
        ? theme.colorScheme.primaryContainer
        : failed
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surface;
    final foreground = paid
        ? theme.colorScheme.onPrimaryContainer
        : failed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSurfaceVariant;
    final border = paid
        ? theme.colorScheme.primary.withValues(alpha: .35)
        : failed
        ? theme.colorScheme.error.withValues(alpha: .35)
        : theme.colorScheme.outlineVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(_statusText(status), style: theme.textTheme.labelSmall?.copyWith(color: foreground)),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    if (context.mounted) _showSnack(context, '操作成功');
  } on AccountApiException catch (error) {
    if (context.mounted) _showSnack(context, error.message);
  } catch (error) {
    if (context.mounted) _showSnack(context, error.toString());
  }
}

Future<void> _showPaymentSheet(
  BuildContext context, {
  required AccountPackage package,
  required List<PaymentMethod> paymentMethods,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _PaymentSheet(package: package, paymentMethods: paymentMethods),
  );
}

Future<void> _confirmDeleteDevice(BuildContext context, WidgetRef ref, AccountDevice device) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('移除设备'),
      content: Text('确定移除“${device.displayName}”吗？移除后该设备需要重新拉取订阅配置才会再次登记。'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.delete_outline_rounded),
          label: const Text('移除'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  await _guard(context, () => ref.read(accountNotifierProvider.notifier).deleteDevice(device.id));
}

Future<void> _showDeviceRemarkDialog(BuildContext context, WidgetRef ref, AccountDevice device) async {
  final controller = TextEditingController(text: device.remark);
  final remark = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('设备备注'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 200,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '备注',
            prefixIcon: Icon(Icons.edit_note_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(controller.text),
          icon: const Icon(Icons.save_rounded),
          label: const Text('保存'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
  if (remark == null || !context.mounted || remark.trim() == device.remark.trim()) {
    return;
  }
  await _guard(
    context,
    () => ref.read(accountNotifierProvider.notifier).updateDeviceRemark(id: device.id, remark: remark),
  );
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

String _statusText(String status) {
  return switch (status) {
    'active' => '正常',
    'pending' => '待支付',
    'paid' => '已支付',
    'cancelled' => '已取消',
    'expired' => '已过期',
    'failed' => '失败',
    _ => status.isEmpty || status == 'none' ? '未开通' : status,
  };
}

IconData _deviceIcon(String type) {
  return switch (type) {
    'mobile' => Icons.phone_android_rounded,
    'tablet' => Icons.tablet_mac_rounded,
    'desktop' => Icons.desktop_windows_rounded,
    'router' => Icons.router_rounded,
    'tv_box' => Icons.tv_rounded,
    'server' => Icons.dns_rounded,
    _ => Icons.devices_other_rounded,
  };
}

String _deviceTypeText(String type) {
  return switch (type) {
    'mobile' => '手机',
    'tablet' => '平板',
    'desktop' => '桌面端',
    'router' => '路由器',
    'tv_box' => '电视盒子',
    'server' => '服务器',
    _ => type.isEmpty || type == 'unknown' ? '未知类型' : type,
  };
}

String _truncateText(String value, int maxLength) {
  if (value.isEmpty) {
    return '未知';
  }
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}
