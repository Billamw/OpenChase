import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:openchase/player_join_screen.dart';
import 'package:openchase/host_invite_screen.dart';
import 'package:openchase/theme.dart';
import 'package:openchase/utils/game_manager.dart';
import 'package:openchase/utils/location_service.dart';
import 'package:openchase/utils/name_cache.dart';
import 'package:openchase/utils/protocol/room_session.dart';
import 'package:openchase/utils/ui_helper.dart';

/// Entry screen: asks for location permission on open (it is mandatory),
/// the name is asked next (pre-filled from the device cache), then host or
/// join. The name persists across sessions via NameCache.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  String? _nameError;
  bool _locationOk = false;
  bool _locChecked = false;
  bool _deniedDialogOpen = false;
  RoomSession? _session;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureLocation());
    RoomSession.load().then((s) {
      if (!mounted || s == null) return;
      setState(() => _session = s);
    });
    NameCache.load().then((name) {
      if (!mounted) return;
      _nameController.text = name;
      if (name.isEmpty) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) FocusScope.of(context).requestFocus(_nameFocus);
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  /// Location is mandatory: prompt on open; on decline show a modal that
  /// forces a retry until granted.
  Future<void> _ensureLocation() async {
    final ok = await ensureLocationPermission();
    if (!mounted) return;
    setState(() {
      _locChecked = true;
      _locationOk = ok;
    });
    if (!ok) await _showLocationDeniedDialog();
  }

  Future<void> _showLocationDeniedDialog() async {
    if (_deniedDialogOpen || !mounted) return;
    _deniedDialogOpen = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Location is required'),
        content: const Text(
          "OpenChase is a real-world hide and seek game - it cannot run "
          "without your location.\n\n"
          "Allow location access, then press \"Try again\". If the browser "
          "now rejects silently, you declined earlier: re-allow it via the "
          "address bar site settings (lock/info icon) and try again.",
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _deniedDialogOpen = false;
              Geolocator.openAppSettings();
            },
            child: const Text('Open settings'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              _deniedDialogOpen = false;
              final ok = await ensureLocationPermission();
              if (!mounted) return;
              setState(() => _locationOk = ok);
              if (!ok) await _showLocationDeniedDialog();
            },
            child: const Text('Try again'),
          ),
        ],
      ),
    );
    _deniedDialogOpen = false;
  }

  /// Returns the trimmed name, or null with an inline error when empty.
  String? _validatedName() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = "Enter a name to continue");
      return null;
    }
    setState(() => _nameError = null);
    NameCache.save(name);
    return name;
  }

  void _host() {
    if (!_locationOk) {
      _showLocationDeniedDialog();
      return;
    }
    final name = _validatedName();
    if (name == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HostInviteScreen(playerName: name),
      ),
    );
  }

  void _join() {
    if (!_locationOk) {
      _showLocationDeniedDialog();
      return;
    }
    final name = _validatedName();
    if (name == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PlayerJoinScreen()),
    );
  }

  /// Reload-resume: rejoin the persisted room with the stored session key.
  void _resume() {
    if (!_locationOk) {
      _showLocationDeniedDialog();
      return;
    }
    final s = _session!;
    GameManager.userName = s.name;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => s.host
            ? HostInviteScreen(
                playerName: s.name,
                resumeCode: s.code,
                resumePriv: s.playerPrivkey,
              )
            : PlayerJoinScreen(
                resumeCode: s.code,
                resumePriv: s.playerPrivkey,
              ),
      ),
    );
  }

  Future<void> _discardSession() async {
    await RoomSession.clear();
    if (!mounted) return;
    setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    final logoPath = UiHelper.getLogoPath(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(logoPath, height: 120, fit: BoxFit.contain),
                const SizedBox(height: 8),
                Text(
                  'Outdoor hide & seek',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: OcColors.mutedFg, fontSize: 16),
                ),
                const SizedBox(height: 32),
                if (_locChecked && !_locationOk)
                  Card(
                    color: const Color(0xFF2A1620),
                    child: ListTile(
                      leading: const Icon(
                        Icons.location_off,
                        color: OcColors.danger,
                      ),
                      title: const Text('Location not allowed'),
                      subtitle: const Text('This game needs your location.'),
                      trailing: TextButton(
                        onPressed: _showLocationDeniedDialog,
                        child: const Text('FIX'),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_session != null)
                  Card(
                    color: const Color(0xFF16222A),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _session!.host
                                ? 'You are hosting room ${_session!.code}'
                                : 'You are in room ${_session!.code}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reconnect after this page reload without '
                            're-entering the code?',
                            style: TextStyle(
                              color: OcColors.mutedFg,
                              fontSize: 14,
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: _discardSession,
                                child: const Text('Forget'),
                              ),
                              const SizedBox(width: 4),
                              FilledButton(
                                onPressed: _resume,
                                child: const Text('Resume'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Your name',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _nameController,
                          focusNode: _nameFocus,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: 'Name',
                            hintText: 'How others will see you',
                            helperText: 'Saved on this device',
                            errorText: _nameError,
                            prefixIcon: const Icon(Icons.person_outline),
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _host(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _host,
                  icon: const Icon(Icons.flag),
                  label: const Text('Host a game'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _join,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Join a game'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
