$:.push File.join(File.dirname(__FILE__), 'lib')

require 'concurrent/version'

Gem::Specification.new do |s|
  s.name        = 'concurrent-ruby'
  s.version     = Concurrent::VERSION
  s.platform    = Gem::Platform::RUBY
  s.author      = "Jerry D'Antonio"
  s.email       = 'jerry.dantonio@gmail.com'
  s.homepage    = 'http://www.concurrent-ruby.com'
  s.summary     = 'Modern concurrency tools including agents, futures, promises, thread pools, reactors, and more.'
  s.license     = 'MIT'
  s.date        = Time.now.strftime('%Y-%m-%d')

  s.description = <<-EOF
    Modern concurrency tools including agents, futures, promises, thread pools, reactors, and more.
    Inspired by Erlang, Clojure, Go, JavaScript, actors, and classic concurrency patterns.
  EOF

  s.files            = Dir['README*', 'LICENSE*', 'CHANGELOG*']
  s.files           += Dir['{lib,md,spec}/**/*']
  s.test_files       = Dir['{spec}/**/*']
  s.extra_rdoc_files = ['README.md']
  s.extra_rdoc_files = Dir['README*', 'LICENSE*', 'CHANGELOG*']
  s.require_paths    = ['lib']

  s.required_ruby_version = '>= 1.9.2'
  s.post_install_message  = <<-MSG
    future = Concurrent::Future.new{ 'Hello, world!' }
    puts future.value
    #=> Hello, world!
  MSG

  s.add_dependency 'functional-ruby', '~> 0.7.4'

  s.add_development_dependency 'bundler'
end
