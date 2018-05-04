require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

BASE_DIR = 'spec/support/thrift'.freeze
GEN_FILES = ['test_constants.rb', 'test_types.rb'].freeze

THRIFT_IN = File.join(BASE_DIR, 'test.thrift'.freeze)
THRIFT_OUT = Rake::FileList[*GEN_FILES.map { |f| File.join(BASE_DIR, 'gen-rb', f) }]

THRIFT_OUT.each do |output|
  file output => THRIFT_IN do
    sh 'thrift', '-o', BASE_DIR, '--gen', 'rb', THRIFT_IN
  end
end

namespace :spec do
  namespace :thrift do
    desc 'Generates Thrift definitions for specs'
    task generate: THRIFT_OUT

    desc 'Cleans generated Thrift definitions from workspace'
    task :clean do
      rm_rf THRIFT_OUT
    end
  end
end

RSpec::Core::RakeTask.new(:spec)
task spec: THRIFT_OUT # add dependency
task default: :spec
