class SettingOption {
  String name;
  bool value;

  SettingOption({required this.name, this.value = false});
}

class AdvancedSettings {
  static List<SettingOption> settings = [
    SettingOption(name: 'Option 1'),
    SettingOption(name: 'Option 2'),
    SettingOption(name: 'Option 3'),
  ];
}
