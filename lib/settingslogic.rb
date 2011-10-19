require "yaml"
require "erb"

class Hash
  def deep_merge!(other_hash)
    other_hash.each_pair do |k,v|
      tv = self[k]
      self[k] = tv.is_a?(Hash) && v.is_a?(Hash) ? tv.deep_merge!(v) : v
    end
    self
  end

  def deep_delete_nil
    delete_if{|k, v| v.nil? or v.instance_of?(Hash) && v.deep_delete_nil.empty?}
  end
end

# A simple settings solution using a YAML file. See README for more information.
class Settingslogic < Hash
  class MissingSetting < StandardError; end
  class InvalidSettingsFile < StandardError; end

  class << self
    def name # :nodoc:
      instance.key?("name") ? instance.name : super
    end

    # Enables Settings.get('nested.key.name') for dynamic access
    def get(key)
      parts = key.split('.')
      curs = self
      while p = parts.shift
        curs = curs.send(p)
      end
      curs
    end

    def source(value = nil)
      #puts "source! #{value.inspect}"
      if value.nil? || value.empty?
        @source
      else
        @source = value
      end
    end

    def namespace(value = nil)
      if value.nil?
        @namespace
      else
        @namespace = value
      end
    end
    
    def [](key)
      instance.fetch(key.to_s, nil)
    end

    def []=(key, val)
      # Setting[:key][:key2] = 'value' for dynamic settings
      val = new(val, source) if val.is_a? Hash
      instance.store(key.to_s, val)
      instance.create_accessor_for(key, val)
    end

    def load!
      instance
      true
    end
    
    def reload!
      @instance = nil
      load!
    end
    
    private
      def instance
        return @instance if @instance
        @instance = new
        create_accessors!
        @instance
      end
      
      def method_missing(name, *args, &block)
        instance.send(name, *args, &block)
      end

      # It would be great to DRY this up somehow, someday, but it's difficult because
      # of the singleton pattern.  Basically this proxies Setting.foo to Setting.instance.foo
      def create_accessors!
        instance.each do |key,val|
          create_accessor_for(key)
        end
      end

      def create_accessor_for(key)
        return unless key.to_s =~ /^\w+$/  # could have "some-setting:" which blows up eval
        instance_eval "def #{key}; instance.send(:#{key}); end"
      end

  end

  # Initializes a new settings object. You can initialize an object in any of the following ways:
  #
  #   Settings.new(:application) # will look for config/application.yml
  #   Settings.new("application.yaml") # will look for application.yaml
  #   Settings.new("/var/configs/application.yml") # will look for /var/configs/application.yml
  #   Settings.new(:config1 => 1, :config2 => 2)
  #   Settings.new(["defaults.yml", "test.yml"]) # will look for defaults.yml and test.yml and merge them
  #
  # Basically if you pass a symbol it will look for that file in the configs directory of your rails app, if you are using this in rails.
  # If you pass a string it should be an absolute path to your settings file.
  # If you pass an array, it should have strings that are absolute paths to your settings files.
  # Then you can pass a hash, and it just allows you to access the hash via methods.
  #
  # Options
  # - deep_delete_nil: remove nil values from hash ex. {:a=>{:b=>nil}}.deep_delete_nil => {}
  # - replace: if true, replace existing value, by new one, otherwise merge
  def initialize(hash_or_file_or_array = self.class.source, section = nil, options={})
    load_source(hash_or_file_or_array, section, {:replace => true}.merge(options))
  end

  def load_source(hash_or_file_or_array, section = nil, options={})
    hash = case hash_or_file_or_array
    when nil
      raise Errno::ENOENT, "No file specified as Settingslogic source"
    when Hash
      hash_or_file_or_array
    when Array
      merge_settings_from_files(hash_or_file_or_array, options)
    else
      merge_settings_from_files([hash_or_file_or_array], options)
    end
    hash.deep_delete_nil if options[:deep_delete_nil]
    options[:replace] ? self.replace(hash) : self.deep_merge!(hash)
    @section = section || self.class.source  # so end of error says "in application.yml"
    create_accessors!
  end

  # For each array element - if file exists, parse it to hash
  # if namespace is present take only specified part
  def merge_settings_from_files(array, options={})
    hash = array.inject({}) do |sum, file|
      if File.exists?(file)
        begin
          tmp_hash = YAML.load(ERB.new(File.read(file)).result).to_hash
          if self.class.namespace
            tmp_hash = tmp_hash[self.class.namespace] || {}
          end
        rescue
          tmp_hash = {}
        end
        sum.deep_merge!(tmp_hash)
      end
      sum
    end
    raise InvalidSettingsFile, "No correct settings in any of files #{array.inspect}" if hash.empty?
    hash
  end

  # Called for dynamically-defined keys, and also the first key deferenced at the top-level, if load! is not used.
  # Otherwise, create_accessors! (called by new) will have created actual methods for each key.
  def method_missing(name, *args, &block)
    key = name.to_s
    raise MissingSetting, "Missing setting '#{key}' in #{@section}" unless has_key? key
    value = fetch(key)
    create_accessor_for(key)
    value.is_a?(Hash) ? self.class.new(value, "'#{key}' section in #{@section}") : value
  end

  def [](key)
    fetch(key.to_s, nil)
  end

  def []=(key,val)
    # Setting[:key][:key2] = 'value' for dynamic settings
    val = self.class.new(val, @section) if val.is_a? Hash
    store(key.to_s, val)
    create_accessor_for(key, val)
  end

  # This handles naming collisions with Sinatra/Vlad/Capistrano. Since these use a set()
  # helper that defines methods in Object, ANY method_missing ANYWHERE picks up the Vlad/Sinatra
  # settings!  So settings.deploy_to title actually calls Object.deploy_to (from set :deploy_to, "host"),
  # rather than the app_yml['deploy_to'] hash.  Jeezus.
  def create_accessors!
    self.each do |key,val|
      create_accessor_for(key)
    end
  end

  # Use instance_eval/class_eval because they're actually more efficient than define_method{}
  # http://stackoverflow.com/questions/185947/ruby-definemethod-vs-def
  # http://bmorearty.wordpress.com/2009/01/09/fun-with-rubys-instance_eval-and-class_eval/
  def create_accessor_for(key, val=nil)
    return unless key.to_s =~ /^\w+$/  # could have "some-setting:" which blows up eval
    instance_variable_set("@#{key}", val) if val
    self.class.class_eval <<-EndEval
      def #{key}
        return @#{key} if @#{key}
        raise MissingSetting, "Missing setting '#{key}' in #{@section}" unless has_key? '#{key}'
        value = fetch('#{key}')
        @#{key} = value.is_a?(Hash) ? self.class.new(value, "'#{key}' section in #{@section}") : value
      end
    EndEval
  end
end

class Settings < Settingslogic
  source ['spec/settings.yml', 'spec/settings2.yml', 'spec/settings3.yml']
end