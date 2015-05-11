require 'spec_helper'

describe Dockly::Docker do
  subject { described_class.new(:name => :test_docker) }

  describe '#ensure_tar' do
    let(:action) { subject.ensure_tar(file) }

    context 'when the file is not a tar' do
      let(:file) { __FILE__ }
      it 'raises an error' do
        expect { action }.to raise_error
      end
    end

    context 'when the file is gzipped' do
      let(:file) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'test-2.tar.gz') }

      it 'calls unzips it and calls #ensure_tar on result' do
        action.should == file
      end
    end

    context 'when the file is a tar' do
      let(:file) { File.join(File.dirname(__FILE__), '..', 'fixtures', 'test-1.tar') }

      it 'returns the file name' do
        action.should == file
      end
    end
  end

  describe '#make_git_archive' do
    [:name, :git_archive].each do |ivar|
      context "when the #{ivar} is null" do
        before { subject.instance_variable_set(:"@#{ivar}", nil) }

        it 'raises an error' do
          expect { subject.make_git_archive }.to raise_error
        end
      end
    end

    context 'when both the name and git archive are specified' do
      before do
        subject.tag 'my-sweet-archive'
        subject.git_archive '/dev/random'
        FileUtils.rm(subject.git_archive_path) if File.exist?(subject.git_archive_path)
      end

      it 'makes a git archive' do
        expect { subject.make_git_archive }
            .to change { File.exist?(subject.git_archive_path) }
            .from(false)
            .to(true)

        names = []
        Gem::Package::TarReader.new(File.new(subject.git_archive_path, 'r')).each do |entry|
          names << entry.header.name
        end
        names.should include('/dev/random/dockly.gemspec')
      end
    end
  end

  describe '#import_base', :docker do
    let(:docker_file) { 'docker-export-ubuntu-latest.tar.gz' }

    # TODO: since we used to run this w/ Vagrant, we put it all together; break it up
    it 'works' do
      # it 'docker imports'
      subject.tag 'my-app'
      unless File.exist?(docker_file)
        File.open(docker_file, 'wb') do |file|
          Excon.get('https://s3.amazonaws.com/swipely-pub/docker-export-ubuntu-latest.tgz',
                    :response_block => lambda { |chunk, _, _| file.write(chunk) })
        end
      end
      image = subject.import_base(subject.ensure_tar(docker_file))
      image.should_not be_nil
      image.id.should_not be_nil

      # it 'builds'
      subject.build "run touch /lol"
      image = subject.build_image(image)
      container = Docker::Container.create('Image' => image.id, 'Cmd' => ['ls', '-1', '/'])
      output = container.tap(&:start).attach(logs: true)
      output[0].grep(/lol/).should_not be_empty
      # TODO: stop resetting the connection, once no longer necessary after attach
      Docker.reset_connection!
      subject.instance_variable_set(:@connection, Docker.connection)

      # it 'exports'
      subject.export_image(image)
      File.exist?('build/docker/test_docker-image.tgz').should be_true
    end
  end

  describe '#fetch_import' do
    [:name, :import].each do |ivar|
      context "when @#{ivar} is nil" do
        before { subject.instance_variable_set(:"@#{ivar}", nil) }

        it 'raises an error' do
          expect { subject.fetch_import }.to raise_error
        end
      end
    end

    context 'when both import and name are present present' do
      before do
        subject.import url
        subject.tag 'test-name'
      end

      context 'and it points at S3' do
        let(:url) { 's3://bucket/object' }
        let(:data) { 'sweet, sweet data' }

        before do
          subject.send(:connection).put_bucket('bucket')
          subject.send(:connection).put_object('bucket', 'object', data)
        end

        it 'pulls the file from S3' do
          File.read(subject.fetch_import).should == data
        end
      end

      context 'and it points to a non-S3 url' do
        let(:url) { 'http://www.html5zombo.com' }

       before { subject.tag 'yolo' }

        it 'pulls the file', :vcr do
          subject.fetch_import.should be_a String
        end
      end

      context 'and it does not point at a url' do
        let(:url) { 'lol-not-a-real-url' }

        it 'raises an error' do
          expect { subject.fetch_import }.to raise_error
        end
      end
    end
  end

  describe "#export_image", :docker do
    let(:image) { Docker::Image.create('fromImage' => 'ubuntu:14.04') }

    context "with a registry export" do
      let(:registry) { double(:registry) }
      before do
        subject.instance_variable_set(:"@registry", registry)
        expect(subject).to receive(:push_to_registry)
      end

      it "pushes the image to the registry" do
        subject.export_image(image)
      end
    end

    context "with an S3 export" do
      let(:export) { double(:export) }
      before do
        expect(Dockly::AWS::S3Writer).to receive(:new).and_return(export)
        expect(export).to receive(:write).once
        expect(export).to receive(:close).once
        subject.s3_bucket "test-bucket"
      end

      context "and a whole export" do
        before do
          expect(subject).to receive(:export_image_whole)
        end

        it "exports the whole image" do
          subject.export_image(image)
        end
      end

      context "and a diff export" do
        before do
          subject.tar_diff true
          expect(subject).to receive(:export_image_diff)
        end

        it "exports the diff image" do
          subject.export_image(image)
        end
      end
    end

    context "with a file export" do
      let(:export) { double(:export) }
      before do
        expect(File).to receive(:open).and_return(export)
        expect(export).to receive(:write).once
        expect(export).to receive(:close)
      end

      context "and a whole export" do
        before do
          expect(subject).to receive(:export_image_whole)
        end

        it "exports the whole image" do
          subject.export_image(image)
        end
      end

      context "and a diff export" do
        before do
          subject.tar_diff true
          expect(subject).to receive(:export_image_diff)
        end

        it "exports the diff image" do
          subject.export_image(image)
        end
      end
    end
  end

  describe '#export_image_diff', :docker do
    let(:output) { StringIO.new }
    before do
      subject.instance_eval do
        import 'https://s3.amazonaws.com/swipely-pub/docker-export-ubuntu-test.tgz'
        build "run touch /it_worked"
        repository "dockly_export_image_diff"
      end
    end

    it "should export only the tar with the new file" do
      docker_tar = File.absolute_path(subject.ensure_tar(subject.fetch_import))
      image = subject.import_base(docker_tar)
      image = subject.build_image(image)
      container = image.run('true').tap { |c| c.wait(10) }
      subject.export_image_diff(container, output)

      expect(output.string).to include('it_worked')
      expect(output.string).to_not include('bin')
    end
  end

  describe '#generate!', :docker do
    let(:docker_file) { 'build/docker/dockly_test-image.tgz' }
    before { FileUtils.rm_rf(docker_file) }

    context 'without cleaning up' do
      before do
        subject.instance_eval do
          import 'https://s3.amazonaws.com/swipely-pub/docker-export-ubuntu-latest.tgz'
          git_archive '.'
          build "run touch /it_worked"
          repository 'dockly_test'
          build_dir 'build/docker'
          cleanup_images false
        end
      end

      it 'builds a docker image' do
        expect {
          subject.generate!
          File.exist?(docker_file).should be_true
          Dockly::Util::Tar.is_gzip?(docker_file).should be_true
          File.size(docker_file).should be > (1024 * 1024)
          paths = []
          Gem::Package::TarReader.new(gz = Zlib::GzipReader.new(File.new(docker_file))).each do |entry|
            paths << entry.header.name
          end
          paths.size.should be > 1000
          paths.should include('sbin/init')
          paths.should include('lib/dockly.rb')
          paths.should include('it_worked')
        }.to change { ::Docker::Image.all(:all => true).length }.by(3)
      end
    end

    context 'with cleaning up' do
      before do
        subject.instance_eval do
          import 'https://s3.amazonaws.com/swipely-pub/docker-export-ubuntu-latest.tgz'
          git_archive '.'
          build "run touch /it_worked"
          repository 'dockly_test'
          build_dir 'build/docker'
          cleanup_images true
        end
      end

      it 'builds a docker image' do
        expect {
          subject.generate!
          File.exist?(docker_file).should be_true
          Dockly::Util::Tar.is_gzip?(docker_file).should be_true
          File.size(docker_file).should be > (1024 * 1024)
          paths = []
          Gem::Package::TarReader.new(gz = Zlib::GzipReader.new(File.new(docker_file))).each do |entry|
            paths << entry.header.name
          end
          paths.size.should be > 1000
          paths.should include('sbin/init')
          paths.should include('lib/dockly.rb')
          paths.should include('it_worked')
        }.to_not change { ::Docker::Image.all(:all => true).length }
      end
    end

    context 'when there is a registry' do
      subject {
        Dockly::Docker.new do
          registry_import 'nahiluhmot/base', :tag => 'latest'
          git_archive '.'
          build "run touch /it_worked"
          repository 'dockly_test'
          build_dir 'build/docker'

          registry do
            username 'tlunter'
            email 'tlunter@gmail.com'
            password '******'
          end
        end
      }

      it 'pushes the image to the registry instead of exporting it' do
        subject.generate!
        expect { ::Docker::Image.build('from nahiluhmot/dockly_test') }.to_not raise_error
      end
    end
  end
end
