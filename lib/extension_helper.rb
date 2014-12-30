module Concurrent
  
  @@c_ext_loaded ||= false
  @@java_ext_loaded ||= false

  # @!visibility private
  def self.allow_c_extensions?
    defined?(RUBY_ENGINE) && RUBY_ENGINE == 'ruby'
  end

  if allow_c_extensions? && !@@c_ext_loaded
    begin
      require 'concurrent/extension'
      @@c_ext_loaded = true
    rescue LoadError
      # may be a Windows cross-compiled native gem
      begin
        require "#{RUBY_VERSION[0..2]}/concurrent/extension"
        @@c_ext_loaded = true
      rescue LoadError
        warn 'Performance on MRI may be improved with the concurrent-ruby-ext gem. Please see http://concurrent-ruby.com'
      end
    end
  elsif RUBY_PLATFORM == 'java' && !@@java_ext_loaded
    begin
      require 'concurrent/extension'
      @@java_ext_loaded = true
    rescue LoadError
      #warn 'Attempted to load Java extensions on unsupported platform. Continuing with pure-Ruby.'
    end
  end
end
