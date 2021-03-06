require 'fog/compute'
require 'fog/rackspace/service'


module Fog
  module Compute
    class RackspaceV2 < Fog::Service

      class ServiceError < Fog::Rackspace::Errors::ServiceError; end
      class InternalServerError < Fog::Rackspace::Errors::InternalServerError; end
      class BadRequest < Fog::Rackspace::Errors::BadRequest; end

      DFW_ENDPOINT = 'https://dfw.servers.api.rackspacecloud.com/v2'
      ORD_ENDPOINT = 'https://ord.servers.api.rackspacecloud.com/v2'
      LON_ENDPOINT = 'https://lon.servers.api.rackspacecloud.com/v2'

      requires :rackspace_username, :rackspace_api_key
      recognizes :rackspace_endpoint
      recognizes :rackspace_auth_url
      recognizes :rackspace_auth_token
      recognizes :rackspace_region
      recognizes :rackspace_compute_url

      model_path 'fog/rackspace/models/compute_v2'
      model :server
      collection :servers
      model :flavor
      collection :flavors
      model :image
      collection :images
      model :attachment
      collection :attachments
      model :network
      collection :networks

      request_path 'fog/rackspace/requests/compute_v2'
      request :list_servers
      request :get_server
      request :create_server
      request :update_server
      request :delete_server
      request :change_server_password
      request :reboot_server
      request :rebuild_server
      request :resize_server
      request :confirm_resize_server
      request :revert_resize_server
      request :list_addresses
      request :list_addresses_by_network

      request :create_image
      request :list_images
      request :get_image
      request :delete_image

      request :list_flavors
      request :get_flavor

      request :attach_volume
      request :get_attachment
      request :list_attachments
      request :delete_attachment

      request :list_metadata
      request :set_metadata
      request :update_metadata
      request :get_metadata_item
      request :set_metadata_item
      request :delete_metadata_item

      request :list_networks
      request :get_network
      request :create_network
      request :delete_network

      class Mock < Fog::Rackspace::Service
        include Fog::Rackspace::MockData      

        def initialize(options)
          @rackspace_api_key = options[:rackspace_api_key]
        end

        def request(params)
          Fog::Mock.not_implemented
        end

        def response(params={})
          body    = params[:body] || {}
          status  = params[:status] || 200
          headers = params[:headers] || {}

          response = Excon::Response.new(:body => body, :headers => headers, :status => status)
          if params.has_key?(:expects) && ![*params[:expects]].include?(response.status)
            raise(Excon::Errors.status_error(params, response))
          else response
          end
        end
      end

      class Real < Fog::Rackspace::Service
        
        def initialize(options = {})
          @rackspace_api_key = options[:rackspace_api_key]
          @rackspace_username = options[:rackspace_username]
          @rackspace_auth_url = options[:rackspace_auth_url]
          setup_custom_endpoint(options)
          @rackspace_must_reauthenticate = false
          @connection_options = options[:connection_options] || {}

          authenticate

          deprecation_warnings(options)
          
          @persistent = options[:persistent] || false
          @connection = Fog::Connection.new(endpoint_uri.to_s, @persistent, @connection_options)
        end

        def request(params)
          begin
            response = @connection.request(params.merge!({
              :headers  => {
                'Content-Type' => 'application/json',
                'Accept' => 'application/json',
                'X-Auth-Token' => auth_token
              }.merge!(params[:headers] || {}),
              :host     => endpoint_uri.host,
              :path     => "#{endpoint_uri.path}/#{params[:path]}"
            }))
          rescue Excon::Errors::NotFound => error
            raise NotFound.slurp error
          rescue Excon::Errors::BadRequest => error
            raise BadRequest.slurp error
          rescue Excon::Errors::InternalServerError => error
            raise InternalServerError.slurp error
          rescue Excon::Errors::HTTPStatusError => error
            raise ServiceError.slurp error
          end

          unless response.body.empty?
            begin
              response.body = Fog::JSON.decode(response.body)
            rescue MultiJson::DecodeError => e
              response.body = {}
            end
          end
          response
        end
        
        def authenticate
          options = {
            :rackspace_api_key => @rackspace_api_key,
            :rackspace_username => @rackspace_username,
            :rackspace_auth_url => @rackspace_auth_url
          }
          super(options)
        end

        def service_name
          :cloudServersOpenStack
        end

        def region
          @rackspace_region
        end

        def endpoint_uri(service_endpoint_url=nil)
          @uri = super(@rackspace_endpoint || service_endpoint_url, :rackspace_compute_url)
        end

        private

        def setup_custom_endpoint(options)
          @rackspace_endpoint = options[:rackspace_compute_url] || options[:rackspace_endpoint]

          if v2_authentication?
            case @rackspace_endpoint
            when DFW_ENDPOINT
              @rackspace_endpoint = nil
              @rackspace_region = :dfw
            when ORD_ENDPOINT
              @rackspace_endpoint = nil
              @rackspace_region = :ord
            when LON_ENDPOINT
              @rackspace_endpoint = nil
              @rackspace_region = :lon
            else
              # we are actually using a custom endpoint
              @rackspace_region = options[:rackspace_region] || :dfw
            end
          end
        end

        def deprecation_warnings(options)
          Fog::Logger.deprecation("The :rackspace_endpoint option is deprecated. Please use :rackspace_compute_url for custom endpoints") if options[:rackspace_endpoint]

          if [DFW_ENDPOINT, ORD_ENDPOINT, LON_ENDPOINT].include?(@rackspace_endpoint) && v2_authentication?
            regions = @identity_service.service_catalog.display_service_regions(service_name)
            Fog::Logger.deprecation("Please specify region using :rackspace_region rather than :rackspace_endpoint. Valid regions for :rackspace_region are #{regions}.")
          end
        end

        def append_tenant_v1(credentials)
          account_id = credentials['X-Server-Management-Url'].match(/.*\/([\d]+)$/)[1]
          
          endpoint = @rackspace_endpoint || credentials['X-Server-Management-Url'] || DFW_ENDPOINT
          @uri = URI.parse(endpoint)
          @uri.path = "#{@uri.path}/#{account_id}"
        end

        def authenticate_v1(options)
          credentials = Fog::Rackspace.authenticate(options, @connection_options)
          append_tenant_v1 credentials
          @auth_token = credentials['X-Auth-Token']
        end
      end
    end
  end
end
