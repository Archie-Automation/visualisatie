import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import '../ui/widgets/confirm_dialog.dart';
import '../ui/widgets/luxe_form.dart';
import 'installer_api.dart';
import 'intercom_sip_config.dart';
import 'voip_installer_section.dart';

/// Three-step intercom setup for integrators without SIP knowledge.
class IntercomInstallerWizard extends StatelessWidget {
  const IntercomInstallerWizard({
    super.key,
    required this.device,
    required this.house,
    required this.onChanged,
    this.getToken,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> house;
  final VoidCallback onChanged;
  final Future<String?> Function()? getToken;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntercomDeviceSetupCard(
          device: device,
          house: house,
          onChanged: onChanged,
          getToken: getToken,
        ),
        BelgroepSetupCard(
          house: house,
          onChanged: onChanged,
        ),
        IntercomActionMappingCard(
          device: device,
          house: house,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({
    required this.step,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final int step;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: LuxeColors.brass.withValues(alpha: 0.16),
              border: Border.all(
                color: LuxeColors.brass.withValues(alpha: 0.45),
              ),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$step',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: LuxeColors.brassDeep,
                  ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: LuxeColors.ink, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: LuxeColors.inkSoft,
                        ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class IntercomDeviceSetupCard extends StatelessWidget {
  const IntercomDeviceSetupCard({
    super.key,
    required this.device,
    required this.house,
    required this.onChanged,
    this.getToken,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> house;
  final VoidCallback onChanged;
  final Future<String?> Function()? getToken;

  @override
  Widget build(BuildContext context) {
    final o = ensureIntercomMap(device);
    final name = (device['name'] as String?) ?? '';
    final sipUser = (o['sipExt'] as String?) ?? '';
    final sipPass = (o['sipPassword'] as String?) ?? '';
    final rtsp = (o['rtsp'] as String?) ?? '';
    final dtmf = (o['dtmfDigit'] as String?) ?? defaultDtmfDigit;
    final taken = usedSipExts(
      house,
      exceptIntercomId: '${device['id']}',
    );
    final own = sipUser.trim();
    final clash = own.isNotEmpty && taken.contains(own);

    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle(
            step: 1,
            icon: Icons.doorbell_outlined,
            title: 'Deurstation',
            subtitle: 'Gegevens zoals ingesteld op het fysieke toestel '
                '(2N, DoorBird, Axis).',
            trailing: LuxeInfoIconButton(
              title: 'Deurstation',
              body:
                  'Vul hier in wat er op het deurstation zelf staat. '
                  'Tablets en telefoons krijgen automatisch een eigen account; '
                  'die instellingen hoef je niet over te nemen.\n\n'
                  'De camerastream (RTSP) is hetzelfde adres als je in VLC zou openen.',
            ),
          ),
          _WizardTextField(
            label: 'Naam intercom',
            value: name,
            hint: 'Voordeur',
            errorText: validateIntercomName(name),
            onChanged: (s) {
              device['name'] = s;
              onChanged();
            },
          ),
          _WizardTextField(
            label: 'SIP-gebruiker / account',
            value: sipUser,
            hint: 'Zoals op het deurstation',
            tooltip:
                'De inlognaam van het deurstation. Staat in de webinterface van 2N, DoorBird of Axis, vaak onder SIP of Telefoon.',
            errorText: clash
                ? 'Dit account is al in gebruik. Kies hetzelfde als op het toestel, maar uniek in dit huis.'
                : validateIntercomSipUser(sipUser),
            onChanged: (s) {
              o['sipExt'] = s.trim();
              onChanged();
            },
          ),
          _WizardTextField(
            label: 'SIP-wachtwoord',
            value: sipPass,
            hint: 'Zoals op het deurstation',
            tooltip:
                'Het wachtwoord dat bij het SIP-account op het deurstation hoort. Niet het wachtwoord van de webinterface, tenzij die hetzelfde is.',
            obscure: true,
            errorText: validateIntercomSipPassword(sipPass),
            onChanged: (s) {
              o['sipPassword'] = s;
              onChanged();
            },
          ),
          _WizardTextField(
            label: 'Camerastream (RTSP)',
            value: rtsp,
            hint: 'rtsp://...',
            tooltip:
                'Adres van het live beeld van de deurbelcamera. Begint altijd met rtsp:// of rtsps://. Je vindt het in de handleiding of de camera-instellingen van het deurstation.',
            maxLines: 3,
            errorText: validateRtspUrl(rtsp),
            onChanged: (s) {
              o['rtsp'] = s.trim();
              onChanged();
            },
          ),
          const SizedBox(height: 4),
          _RtspTestButton(rtsp: rtsp, getToken: getToken),
          const SizedBox(height: 16),
          _WizardTextField(
            label: 'Deuropen-code (DTMF)',
            value: dtmf,
            hint: defaultDtmfDigit,
            tooltip:
                'Toets die tijdens het gesprek naar het deurstation gaat om het slot te openen. Meestal #. Eén teken: 0–9, #, * of A–D.',
            errorText: validateDtmfDigit(dtmf),
            inputFormatters: [
              LengthLimitingTextInputFormatter(1),
              FilteringTextInputFormatter.allow(RegExp(r'[0-9A-Da-d#*]')),
            ],
            onChanged: (s) {
              final t = s.trim();
              o['dtmfDigit'] = t.isEmpty ? defaultDtmfDigit : t;
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class BelgroepSetupCard extends StatelessWidget {
  const BelgroepSetupCard({
    super.key,
    required this.house,
    required this.onChanged,
  });

  final Map<String, dynamic> house;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = voipGroupMaps(house);
    final users = houseUserMaps(house);
    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle(
            step: 2,
            icon: Icons.groups_outlined,
            title: 'Belgroep',
            subtitle: 'Welke tablets en telefoons overgaan bij aanbellen.',
            trailing: LuxeInfoIconButton(
              title: 'Belgroep',
              body:
                  'Een belgroep is een lijst toestellen die tegelijk overgaan. '
                  'Wie als eerste opneemt, stopt het rinkelen op de andere toestellen.\n\n'
                  'Elke aangevinkte gebruiker krijgt automatisch een account. '
                  'Log op het tablet of de telefoon in met die gebruiker.',
            ),
          ),
          if (users.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Voeg eerst gebruikers toe onder Gebruikers. '
                'Tablets en telefoons loggen in met die accounts.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (groups.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Nog geen belgroep. Voeg er één toe en vink de toestellen aan.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (var i = 0; i < groups.length; i++)
            _BelgroepEditor(
              key: ValueKey(groups[i]['id']),
              house: house,
              group: groups[i],
              canDelete: true,
              onChanged: onChanged,
              onDelete: () {
                deleteBelgroep(house, '${groups[i]['id']}');
                onChanged();
              },
            ),
          LuxeAddRow(
            label: 'Belgroep toevoegen',
            onTap: () {
              createBelgroep(house);
              onChanged();
            },
          ),
        ],
      ),
    );
  }
}

class _BelgroepEditor extends StatelessWidget {
  const _BelgroepEditor({
    super.key,
    required this.house,
    required this.group,
    required this.canDelete,
    required this.onChanged,
    required this.onDelete,
  });

  final Map<String, dynamic> house;
  final Map<String, dynamic> group;
  final bool canDelete;
  final VoidCallback onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final users = houseUserMaps(house);
    final members = (group['memberIds'] is List)
        ? (group['memberIds'] as List).map((e) => '$e').toSet()
        : <String>{};
    final timeout = '${belgroepTimeoutSec(group)}';
    final selectedCount = users.where((u) {
      final ep = sipEndpointForUser(house, u);
      return ep != null && members.contains('${ep['id']}');
    }).length;

    return LuxeInsetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _WizardTextField(
                  label: 'Naam groep',
                  value: (group['name'] as String?) ?? '',
                  hint: defaultBelgroepName,
                  errorText: ((group['name'] as String?) ?? '').trim().isEmpty
                      ? 'Vul een groepsnaam in.'
                      : null,
                  onChanged: (s) {
                    group['name'] = s;
                    onChanged();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Belgroep verwijderen',
                onPressed: canDelete ? onDelete : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _WizardTextField(
            label: 'Afringduur (seconden)',
            value: timeout,
            hint: '$defaultRingTimeoutSec',
            tooltip:
                'Hoe lang tablets en telefoons overgaan als niemand opneemt.',
            errorText: validateRingTimeout(timeout),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (s) {
              setBelgroepTimeoutSec(group, s);
              onChanged();
            },
          ),
          const LuxeFieldLabel(
            'Doeltoestellen',
            tooltip:
                'Vink elk tablet, iPhone of Android-toestel aan dat moet overgaan. '
                'Het toestel hoort bij de gebruiker die erop is ingelogd.',
          ),
          if (users.isEmpty)
            Text(
              'Geen gebruikers om te kiezen.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Text(
              selectedCount == 0
                  ? 'Nog geen toestel aangevinkt.'
                  : '$selectedCount toestel${selectedCount == 1 ? '' : 'len'} in deze groep.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 4),
          for (final u in users)
            _UserDeviceTile(
              house: house,
              user: u,
              selected: () {
                final ep = sipEndpointForUser(house, u);
                return ep != null && members.contains('${ep['id']}');
              }(),
              onChanged: (v) {
                enableIntercomCalling(house);
                if (v) {
                  bindSipToUser(house, u);
                  final ep = sipEndpointForUser(house, u);
                  final list = (group['memberIds'] is List)
                      ? List<dynamic>.from(group['memberIds'] as List)
                      : <dynamic>[];
                  if (ep != null && !list.contains(ep['id'])) {
                    list.add(ep['id']);
                  }
                  group['memberIds'] = list;
                } else {
                  final ep = sipEndpointForUser(house, u);
                  final list = (group['memberIds'] is List)
                      ? List<dynamic>.from(group['memberIds'] as List)
                      : <dynamic>[];
                  if (ep != null) list.remove(ep['id']);
                  group['memberIds'] = list;
                }
                onChanged();
              },
            ),
        ],
      ),
    );
  }
}

class _UserDeviceTile extends StatelessWidget {
  const _UserDeviceTile({
    required this.house,
    required this.user,
    required this.selected,
    required this.onChanged,
  });

  final Map<String, dynamic> house;
  final Map<String, dynamic> user;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ep = sipEndpointForUser(house, user);
    final type = (ep?['type'] as String?) ?? '';
    final typeLabel = switch (type) {
      'panel' => 'Tablet',
      'phone' => 'Telefoon',
      'app' => 'App',
      _ => 'Tablet of telefoon',
    };
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(userSipLabel(user)),
      subtitle: Text(
        selected ? typeLabel : 'Wordt automatisch gekoppeld',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      value: selected,
      activeColor: LuxeColors.brassDeep,
      onChanged: (v) => onChanged(v == true),
    );
  }
}

class IntercomActionMappingCard extends StatelessWidget {
  const IntercomActionMappingCard({
    super.key,
    required this.device,
    required this.house,
    required this.onChanged,
  });

  final Map<String, dynamic> device;
  final Map<String, dynamic> house;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final o = ensureIntercomMap(device);
    final groups = voipGroupMaps(house);
    final current = (o['ringGroupId'] as String?)?.trim() ?? '';
    final valid = groups.any((g) => '${g['id']}' == current) ? current : null;
    final err = validateRingGroupId(valid, groups);

    return LuxeListCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepTitle(
            step: 3,
            icon: Icons.alt_route_outlined,
            title: 'Koppeling belknop',
            subtitle: 'Wat er gebeurt als iemand op knop 1 van het deurstation drukt.',
            trailing: LuxeInfoIconButton(
              title: 'Belknop',
              body:
                  'Knop 1 is de hoofdbel op het deurstation. '
                  'Die start de gekozen belgroep: alle aangevinkte toestellen gaan over.',
            ),
          ),
          const LuxeFieldLabel(
            'Als belknop 1 wordt ingedrukt',
            tooltip:
                'De fysieke belknop op het deurstation. Geen KNX-knop — dit is de knop op 2N, DoorBird of Axis.',
          ),
          if (groups.isEmpty)
            Text(
              'Maak eerst een belgroep in stap 2.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            DropdownButtonFormField<String>(
              key: ValueKey('ring-${device['id']}-$valid'),
              initialValue: valid,
              decoration: luxeFilledDecoration(
                hint: 'Kies een belgroep',
                helper: err,
              ),
              items: [
                for (final g in groups)
                  DropdownMenuItem(
                    value: '${g['id']}',
                    child: Text(
                      ((g['name'] as String?)?.trim().isNotEmpty == true)
                          ? (g['name'] as String).trim()
                          : 'Belgroep',
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v == null || v.isEmpty) {
                  o.remove('ringGroupId');
                } else {
                  o['ringGroupId'] = v;
                }
                onChanged();
              },
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.touch_app_outlined, size: 18, color: LuxeColors.inkSoft),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belknop 1  →  Start belgroep',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RtspTestButton extends StatefulWidget {
  const _RtspTestButton({required this.rtsp, this.getToken});

  final String rtsp;
  final Future<String?> Function()? getToken;

  @override
  State<_RtspTestButton> createState() => _RtspTestButtonState();
}

class _RtspTestButtonState extends State<_RtspTestButton> {
  bool _busy = false;
  String? _status;
  Color? _statusColor;

  Future<void> _run() async {
    final formatErr = validateRtspUrl(widget.rtsp);
    if (formatErr != null) {
      setState(() {
        _status = formatErr;
        _statusColor = Colors.red.shade700;
      });
      return;
    }
    final token = await widget.getToken?.call();
    if (!mounted) return;
    if (token == null) {
      setState(() {
        _status = 'Niet ingelogd — kan de stream niet testen.';
        _statusColor = Colors.red.shade700;
      });
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
      _statusColor = null;
    });
    try {
      final r = await postInstallerCameraProbe(token, rtsp: widget.rtsp.trim());
      if (!mounted) return;
      final live = r.live;
      if (live.ok) {
        final res = live.width != null && live.height != null
            ? ' · ${live.width}×${live.height}'
            : '';
        setState(() {
          _status = 'Beeld OK$res';
          _statusColor = null;
        });
      } else {
        setState(() {
          _status =
              'Geen beeld. Controleer de URL, gebruikersnaam en wachtwoord.';
          _statusColor = Colors.red.shade700;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '$e';
        _statusColor = Colors.red.shade700;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.videocam_outlined, size: 18),
          label: const Text('Camerastream testen'),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _status!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _statusColor,
                  ),
            ),
          ),
      ],
    );
  }
}

class _WizardTextField extends StatefulWidget {
  const _WizardTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.tooltip,
    this.errorText,
    this.obscure = false,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? tooltip;
  final String? errorText;
  final bool obscure;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<_WizardTextField> createState() => _WizardTextFieldState();
}

class _WizardTextFieldState extends State<_WizardTextField> {
  late final TextEditingController _c;
  late bool _hide;

  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.value);
    _hide = widget.obscure;
  }

  @override
  void didUpdateWidget(covariant _WizardTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _c.text != widget.value) {
      _c.text = widget.value;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String? get _shownError {
    if (widget.errorText == null) return null;
    if (_c.text.trim().isEmpty &&
        (widget.label == 'SIP-gebruiker / account' ||
            widget.label == 'SIP-wachtwoord' ||
            widget.label == 'Camerastream (RTSP)')) {
      return null;
    }
    return widget.errorText;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LuxeFieldLabel(widget.label, tooltip: widget.tooltip),
          TextField(
            controller: _c,
            obscureText: widget.obscure && _hide,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            keyboardType: widget.keyboardType ??
                (widget.maxLines > 1
                    ? TextInputType.multiline
                    : TextInputType.text),
            inputFormatters: widget.inputFormatters,
            decoration: luxeFilledDecoration(
              hint: widget.hint,
              helper: _shownError,
              helperMaxLines: 3,
              suffixIcon: widget.obscure
                  ? IconButton(
                      tooltip: _hide ? 'Tonen' : 'Verbergen',
                      icon: Icon(
                        _hide
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _hide = !_hide),
                    )
                  : null,
            ),
            onChanged: (s) {
              widget.onChanged(s);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }
}
