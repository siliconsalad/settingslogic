class SettingsInst < Settingslogic
end

class Settings < Settingslogic
  source "#{File.dirname(__FILE__)}/settings.yml"
end

class Settings2 < Settingslogic
  source "#{File.dirname(__FILE__)}/settings.yml"
  namespace "setting1"
end

class Settings3 < Settingslogic
  source "#{File.dirname(__FILE__)}/settings.yml"
  load!  # test of load
end

# settings.yml, settings2.yml and settings3.yml should be merged
class Settings4 < Settingslogic
  source ["#{File.dirname(__FILE__)}/settings.yml", "#{File.dirname(__FILE__)}/settings2.yml", "#{File.dirname(__FILE__)}/settings3.yml"]
end

# settings should be taken only from settings.yml
class Settings5 < Settingslogic
  source ["#{File.dirname(__FILE__)}/settings_invalid.yml", "#{File.dirname(__FILE__)}/settings.yml", "#{File.dirname(__FILE__)}/non_exisiting.yml"]
end

# should raise an error - no valid settings file
class Settings6 < Settingslogic
  source ["#{File.dirname(__FILE__)}/settings_invalid.yml", "#{File.dirname(__FILE__)}/non_exisiting.yml"]
end