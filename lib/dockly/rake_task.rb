require 'rake'
require 'dockly'

class Rake::DebTask < Rake::Task
  def needed?
    raise "Package does not exist" if package.nil?
    !package.exists?
  end

  def package
    Dockly::Deb[name.split(':').last.to_sym]
  end
end

module Rake::DSL
  def deb(*args, &block)
    Rake::DebTask.define_task(*args, &block)
  end
end

namespace :dockly do
  task :load do
    raise "No dockly.rb found!" unless File.exist?('dockly.rb')
  end

  namespace :deb do
    Dockly.debs.values.each do |inst|
      deb inst.name => 'dockly:load' do |name|
        Thread.current[:rake_task] = name
        inst.build
      end
    end
  end

  namespace :docker do
    Dockly.dockers.values.each do |inst|
      task inst.name => 'dockly:load' do
        Thread.current[:rake_task] = inst.name
        inst.generate!
      end

      namespace :noexport do
        task inst.name => 'dockly:load' do
          Thread.current[:rake_task] = inst.name
          inst.generate_build
        end
      end
    end
  end
end
