# encoding: utf-8

require 'uri'
require 'chef/provider'

class Chef
  class Provider
    class MongodbRelease < Chef::Provider::LWRPBase

      include ::Opscode::MongoDB::ProviderHelpers

      def initialize(*args)
        super
        @url = nil
        @checksum = nil
        @download_prefix = nil
        @install_prefix = nil
        @user = nil
        @group = nil
      end

      def load_current_resource
        @current_resource = Chef::Resource::MongodbRelease.new(new_resource.name, run_context)
        @current_resource.install_prefix(new_resource.install_prefix)
        @current_resource
      end

      def instance_path
        ::File.join(@new_resource.install_prefix, @new_resource.name)
      end

      def action_install

        tarball_source = ::URI.parse(@new_resource.url)
        tarball_path = ::File.join(
          @new_resource.download_prefix, ::File.basename(tarball_source.path)
        )

        create_user_and_group(@new_resource.user, @new_resource.group)

        [@new_resource.download_prefix, instance_path].each do |dir|
          dir_resource = Chef::Resource::Directory.new(dir, run_context)
          dir_resource.mode(0755)
          dir_resource.owner(@new_resource.user)
          dir_resource.group(@new_resource.group)
          dir_resource.recursive(true)
          dir_resource.run_action(:create)
        end

        unless @new_resource.checksum
          Chef::Log.warn("mongodb_release[#{@new_resource.name}] did not specify a checksum, chef will download the corresponding mongodb tarball on every run")
        end

        tarball = Chef::Resource::RemoteFile.new(tarball_path, run_context)
        tarball.source @new_resource.url
        tarball.checksum(@new_resource.checksum) if @new_resource.checksum
        tarball.owner(@new_resource.user)
        tarball.group(@new_resource.group)
        tarball.run_action(:create)

        unpack_script = Chef::Resource::Execute.new("unpack #{tarball_path}", run_context)
        unpack_script.cwd(instance_path)
        unpack_script.command("tar --strip-components=1 -zxvf #{tarball_path}")
        unpack_script.user(@new_resource.user)
        unpack_script.group(@new_resource.group)
        unpack_script.subscribes(:run, "remote_file[#{tarball_path}]", :immediately)

        if tarball.updated_by_last_action?
          unpack_script.run_action(:run)
        end

      end

      def action_symlink
        executables = ::Dir.glob(::File.join(instance_path, 'bin', '*'))
        executables.each do |exe|
          symlink = ::File.join(
            @new_resource.symlink_prefix, ::File.basename(exe)
          )
          link symlink do
            to exe
          end
          @new_resource.updated_by_last_action(true)
        end
      end

      def action_remove
        # not yet implemented
      end

    end
  end
end
