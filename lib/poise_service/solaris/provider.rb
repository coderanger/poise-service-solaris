#
# Cookbook: poise-service-solaris
# License: Apache 2.0
#
# Copyright 2015, Noah Kantrowitz
# Copyright 2015-2016, Bloomberg Finance L.P.
#

require 'chef/mash'

require 'poise_service/error'
require 'poise_service/service_providers/base'

module PoiseService
  module ServiceProviders
    # Poise-service provider for Solaris.
    # @since 1.0.0
    class SolarisService < Base
      include Chef::Mixin::ShellOut
      provides(:solaris_service)

      # proritize this provider on solaris
      Chef::Platform::ProviderPriorityMap.instance.priority(:poise_service, [self])

      def self.provides_auto?(node, _)
        node['platform_family'] == 'solaris2'
      end

      # Parse the PID from `svcs -p <name>` output.
      # @return [Integer]
      def pid
        service = shell_out!("svcs -p #{@new_resource.service_name}").stdout
        service.split(' ')[-1].to_i
      end

      private

      def manifest_file
        "/lib/svc/manifest/site/#{new_resource.service_name}.xml"
      end

      def create_service
        Chef::Log.debug("Creating solaris service #{new_resource.service_name}")

        template manifest_file do
          source 'manifest.xml.erb'
          cookbook 'poise-service-solaris' # poise needs cookbook name for template
          verify 'svccfg validate %{path}'
          variables(
            name: new_resource.service_name,
            command: new_resource.command,
            user: new_resource.user,
            environment: new_resource.environment,
            directory: new_resource.directory
          )
        end

        execute 'load service manifest' do
          # we synchrously disable and enable instead of
          # calling restart to avoid timing problem
          command 'svcadm disable -s manifest-import && svcadm enable -s manifest-import'
          # svcs -o STATE -H <service_name> returns online if service is up
          not_if { `svcs -o STATE -H #{new_resource.service_name}`.strip == 'online' }
        end
      end


      def destroy_service
        Chef::Log.debug("Destroying solaris service #{new_resource.service_name}")
        file manifest_file do
          action :delete
        end

        execute 'load service manifest' do
          # we synchrously disable and enable instead of
          # calling restart to avoid timing problem
          command 'svcadm disable -s manifest-import && svcadm enable -s manifest-import'
          # svcs <service_name> returns 0 if service exists
          only_if "svcs #{new_resource.service_name}"
        end
      end

      def service_provider
        super.tap do |r|
          r.provider(Chef::Provider::Service::Solaris)
        end
      end
    end
  end
end
