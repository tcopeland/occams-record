require_relative 'lib/occams-record/version'

Gem::Specification.new do |s|
  s.name = 'occams-record'
  s.version = OccamsRecord::VERSION
  s.licenses = ['MIT']
  s.summary = 'The missing high-efficiency query API for ActiveRecord'
  s.description = 'A faster, lower-memory querying API for ActiveRecord that returns results as unadorned, read-only objects.'
  s.date = '2017-08-19'
  s.authors = ['Jordan Hollinger']
  s.email = 'jordan.hollinger@gmail.com'
  s.homepage = 'https://github.com/jhollinger/occams-record'
  s.require_paths = ['lib']
  s.files = [Dir.glob('lib/**/*'), 'README.md'].flatten
  s.required_ruby_version = '>= 2.1.0'
  s.add_runtime_dependency 'activerecord', ['>= 4.2', '< 5.2']
end
