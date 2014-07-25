require 'dockly/util'
require 'dockly/util/tar'
require 'dockly/util/git'
require 'fog'
require 'foreman/cli_fix'
require 'foreman/export/base_fix'

module Dockly
  attr_reader :instance, :git_sha
  attr_writer :load_file

  autoload :AWS, 'dockly/aws'
  autoload :Foreman, 'dockly/foreman'
  autoload :BashBuilder, 'dockly/bash_builder'
  autoload :BuildCache, 'dockly/build_cache'
  autoload :Docker, 'dockly/docker'
  autoload :Deb, 'dockly/deb'
  autoload :TarDiff, 'dockly/tar_diff'

  LOAD_FILE = 'dockly.rb'

  def load_file
    @load_file || LOAD_FILE
  end

  def inst
    @instance ||= load_inst
  end

  def load_inst
    setup.tap do |state|
      if File.exists?(load_file)
        instance_eval(IO.read(load_file), load_file)
      end
    end
  end

  def setup
    {
      :debs => Dockly::Deb.instances,
      :dockers => Dockly::Docker.instances,
      :foremans => Dockly::Foreman.instances
    }
  end

  {
    :deb => Dockly::Deb,
    :docker => Dockly::Docker,
    :foreman => Dockly::Foreman
  }.each do |method, klass|
    define_method(method) do |sym, &block|
      if block.nil?
        inst[:"#{method}s"][sym]
      else
        klass.new!(:name => sym, &block)
      end
    end
  end

  [:debs, :dockers, :foremans].each do |method|
    define_method(method) do
      inst[method]
    end
  end

  def git_sha
    @git_sha ||= Dockly::Util::Git.git_sha
  end

  module_function :inst, :load_inst, :setup, :load_file, :load_file=,
                  :deb,  :docker,  :foreman, :git_sha,
                  :debs, :dockers, :foremans
end

require 'dockly/rake_task'
