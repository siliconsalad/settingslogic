class Settings4 < Settingslogic
  source ["#{File.dirname(__FILE__)}/settings.yml", "#{File.dirname(__FILE__)}/settings2.yml", "#{File.dirname(__FILE__)}/settings3.yml"]
end