module Redirus
  module Worker
    class NginxConfigGenerator

      def initialize(proxies, properties)
        @proxies, @properties = proxies, properties
      end

      attr_reader :proxies, :properties

      def generate
        result = {
          http:  { proxy_conf: StringIO.new, upstream_conf: StringIO.new },
          https: { proxy_conf: StringIO.new, upstream_conf: StringIO.new }
        }

        proxies.each do |proxy|
          result[proxy[:type]][:proxy_conf]    << generate_proxy_conf(proxy)
          result[proxy[:type]][:upstream_conf] << generate_upstream_conf(proxy)
        end

        string_values(result)
      end

      private

      def string_values(result)
        result = {
          http:  {
            proxy_conf: result[:http][:proxy_conf].string,
            upstream_conf: result[:http][:upstream_conf].string
          },
          https: {
            proxy_conf: result[:https][:proxy_conf].string,
            upstream_conf: result[:https][:upstream_conf].string
          }
        }
      end

      def generate_proxy_conf(proxy)
        proxy_path = proxy_path(proxy)

        conf = "location \"/#{proxy_path}/\" {\n"\
        "  proxy_pass http:\/\/#{proxy_pass(proxy_path)}\/;\n"\
        "#{properties_config(proxy)}}\n"
      end

      def proxy_path(proxy)
        proxy_path = proxy[:path]
        proxy_path = proxy_path[0..-2] if proxy_path[proxy_path.size - 1] == '/'
        proxy_path = proxy_path[1..(proxy_path.size - 1)] if proxy_path[0] == '/'

        proxy_path
      end

      def proxy_pass(proxy_path)
        proxy_path.gsub('/', '.')
      end

      def generate_upstream_conf(proxy)
        proxy_pass = proxy_pass proxy_path(proxy)
        "upstream #{proxy_pass} {\n#{workers_conf(proxy)}\}\n"
      end

      def workers_conf(proxy)
        proxy[:workers].collect do |worker|
          "  server #{worker};\n"
        end.join
      end

      def properties_config(proxy)
        properties.collect do |prop|
          "  #{prop.gsub('{{path}}', proxy[:path])};\n"
        end.join
      end
    end
  end
end